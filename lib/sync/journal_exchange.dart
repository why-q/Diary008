/// Provider-neutral operation exchange contract.
///
/// An exchange moves immutable journal operations for one notebook epoch
/// between a local journal and a remote store. It is deliberately tiny: publish
/// a scoped batch, and fetch a detached snapshot. Nothing here knows about a
/// transport, a credential, a file, or a clock, and nothing here decides how
/// operations are applied to a notebook.
///
/// Two rules shape the contract:
///
/// * The exchange never rewrites accepted text. Divergent variants are reported
///   as refusals that carry both the incoming and the accepted operation, so a
///   caller can present the disagreement instead of losing it.
/// * Ordering of arrival is not identity. Identity is the operation's own
///   `operationId`, `actorId`+`sequence`, and `entryId`, so a delayed, repeated,
///   or out-of-order batch cannot change what an operation means.
library;

import '../journal/journal_operation.dart';
import 'journal_scope.dart';

/// A scoped, immutable view of the operations an exchange holds.
///
/// The snapshot is detached: it owns its operation list, and the operations it
/// carries are immutable, so a caller cannot mutate exchange state through it.
class JournalSnapshot {
  JournalSnapshot({
    required this.scope,
    required List<JournalOperation> operations,
  }) : _operations = List.unmodifiable(operations);

  final JournalScope scope;
  final List<JournalOperation> _operations;

  /// Operations in the order the exchange accepted them.
  List<JournalOperation> get operations => _operations;

  int get length => _operations.length;

  bool get isEmpty => _operations.isEmpty;

  JournalOperation? byOperationId(String operationId) {
    for (final operation in _operations) {
      if (operation.operationId == operationId) return operation;
    }
    return null;
  }

  JournalOperation? byActorSequence(String actorId, int sequence) {
    for (final operation in _operations) {
      if (operation.actorId == actorId && operation.sequence == sequence) {
        return operation;
      }
    }
    return null;
  }

  /// Every operation that addresses [entryId], oldest first.
  List<JournalOperation> operationsForEntry(String entryId) =>
      List.unmodifiable(
        _operations.where((operation) => operation.entryId == entryId),
      );

  /// Stable text for the whole snapshot, for comparison and diagnostics.
  ///
  /// Operations are sorted by `operationId`, so arrival order is not part of a
  /// snapshot's identity: two exchanges that accepted the same operations in a
  /// different order have the same canonical form.
  String get canonicalForm {
    final ordered = [..._operations]
      ..sort((a, b) => a.operationId.compareTo(b.operationId));
    return '${scope.notebookId}/${scope.epochId}\n'
        '${ordered.map((operation) => operation.canonicalForm).join('\n')}';
  }

  @override
  bool operator ==(Object other) =>
      other is JournalSnapshot && other.canonicalForm == canonicalForm;

  @override
  int get hashCode => canonicalForm.hashCode;

  @override
  String toString() =>
      'JournalSnapshot($scope, ${_operations.length} operations)';
}

/// Why an operation was not appended by a publish.
enum JournalRefusalKind {
  /// The operation claims another notebook or another epoch of this notebook.
  outOfScope,

  /// The operation is not a valid journal operation.
  invalidOperation,

  /// An accepted operation already uses this `operationId` for other content.
  operationIdCollision,

  /// An accepted operation already uses this `actorId` and `sequence`.
  actorSequenceCollision,

  /// An accepted creation already owns this `entryId`.
  entryCreationCollision,
}

/// A refused operation, retaining both variants when they disagree.
class JournalRefusal {
  JournalRefusal({
    required this.scope,
    required this.kind,
    required this.reason,
    required this.incoming,
    this.accepted,
  });

  final JournalScope scope;
  final JournalRefusalKind kind;
  final String reason;

  /// The operation the caller submitted.
  final JournalOperation incoming;

  /// The operation already accepted under the same identity, if any. It is
  /// never replaced: accepted text stays as it was.
  final JournalOperation? accepted;

  @override
  String toString() => 'JournalRefusal(${kind.name}: $reason)';
}

/// Result of publishing one scoped batch.
sealed class JournalPublishResult {
  const JournalPublishResult({required this.scope});

  final JournalScope scope;

  /// Whether any operation was appended by this call.
  bool get appendedAny;
}

/// The batch passed validation and was processed.
///
/// [appended] lists newly accepted operations, [replayed] lists identical
/// operations that changed nothing, and [conflicts] lists divergent operations
/// that were refused without touching accepted text. A batch may append some
/// operations and refuse others, because a collision is a property of a single
/// identity, not of the batch.
final class JournalPublishCommitted extends JournalPublishResult {
  JournalPublishCommitted({
    required super.scope,
    required List<JournalOperation> appended,
    required List<JournalOperation> replayed,
    required List<JournalRefusal> conflicts,
  }) : appended = List.unmodifiable(appended),
       replayed = List.unmodifiable(replayed),
       conflicts = List.unmodifiable(conflicts);

  final List<JournalOperation> appended;
  final List<JournalOperation> replayed;
  final List<JournalRefusal> conflicts;

  @override
  bool get appendedAny => appended.isNotEmpty;

  bool get hasConflicts => conflicts.isNotEmpty;

  /// True when nothing was appended, which is the normal outcome of a replay.
  bool get isNoOp => appended.isEmpty;
}

/// The batch was refused before anything was appended.
///
/// This is the whole-batch case: a batch carrying any operation that is
/// out of scope is refused entirely, so a caller never has to reason about a
/// partially applied request.
final class JournalPublishRejected extends JournalPublishResult {
  JournalPublishRejected({
    required super.scope,
    required List<JournalRefusal> refusals,
  }) : refusals = List.unmodifiable(refusals);

  final List<JournalRefusal> refusals;

  @override
  bool get appendedAny => false;
}

/// Provider-neutral operation exchange for one notebook epoch at a time.
abstract class JournalExchange {
  /// Publishes [operations] into [scope].
  ///
  /// A batch is validated as a whole: if any operation is out of scope, nothing
  /// is appended and the result is a [JournalPublishRejected]. Otherwise each
  /// operation is admitted by identity, so identical replays are no-ops and
  /// divergent identities become [JournalRefusal]s.
  ///
  /// The call must not mutate [operations] or any operation it contains. A
  /// failure must leave both the input and the exchange state unchanged.
  Future<JournalPublishResult> publish({
    required JournalScope scope,
    required Iterable<JournalOperation> operations,
  });

  /// Reads a detached snapshot of [scope].
  ///
  /// A scope that has never been published to yields an empty snapshot; an
  /// unknown scope is not an error. The returned snapshot must not change when
  /// the exchange changes later.
  Future<JournalSnapshot> fetch({required JournalScope scope});
}
