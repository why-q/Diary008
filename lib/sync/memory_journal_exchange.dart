/// In-memory [JournalExchange] used to exercise the contract without a provider.
///
/// This adapter exists to make the exchange contract testable. It keeps
/// operations in process memory, keyed by [JournalScope], and adds no
/// persistence, no transport, no credential handling, and no retry policy. It
/// is not a production provider and must not be wired into the app.
///
/// Guarantees, all enforced here rather than in the caller:
///
/// * Every request names its own scope, and scopes are isolated: operations for
///   another notebook or another epoch never reach a journal and never see
///   another scope's content.
/// * A batch is refused as a whole when any operation is invalid or out of
///   scope, so a refused batch appends nothing.
/// * Admission is by identity only. Identical replays are no-ops; divergent
///   identity collisions are typed refusals that keep both variants; accepted
///   text is never overwritten.
/// * The commit step is synchronous, so a publish that overlaps another cannot
///   lose the other's changes, and no last-writer-wins rule exists.
library;

import '../journal/journal.dart';
import '../journal/journal_operation.dart';
import 'journal_exchange.dart';
import 'journal_scope.dart';

/// Awaited before a publish enters its commit step.
///
/// This is a test seam for ordering and failure simulation: it lets a test
/// interleave two publishes, or fail one before it commits anything.
typedef MemoryPublishGate = Future<void> Function();

class MemoryJournalExchange implements JournalExchange {
  MemoryJournalExchange({this.gate});

  final MemoryPublishGate? gate;

  final Map<JournalScope, Journal> _journals = {};

  /// Scopes that currently hold at least one accepted operation.
  Set<JournalScope> get scopes => Set.unmodifiable(_journals.keys);

  @override
  Future<JournalPublishResult> publish({
    required JournalScope scope,
    required Iterable<JournalOperation> operations,
  }) async {
    final batch = List<JournalOperation>.unmodifiable(operations);
    final rejected = <JournalRefusal>[];
    final validated = <JournalOperation>[];
    for (final operation in batch) {
      if (!scope.contains(operation)) {
        rejected.add(
          JournalRefusal(
            scope: scope,
            kind: JournalRefusalKind.outOfScope,
            reason:
                'operation "${operation.operationId}" belongs to '
                '${operation.notebookId}/${operation.epochId}, not $scope',
            incoming: operation,
          ),
        );
        continue;
      }
      if (!_isWellFormed(operation)) {
        rejected.add(
          JournalRefusal(
            scope: scope,
            kind: JournalRefusalKind.invalidOperation,
            reason:
                'operation "${operation.operationId}" is not a valid '
                'journal operation',
            incoming: operation,
          ),
        );
        continue;
      }
      validated.add(operation);
    }
    if (rejected.isNotEmpty) {
      return JournalPublishRejected(scope: scope, refusals: rejected);
    }

    await gate?.call();

    // Everything below is synchronous, so a concurrent publish cannot observe
    // a half-applied batch or have its own appended operations dropped.
    return _commit(scope, validated);
  }

  @override
  Future<JournalSnapshot> fetch({required JournalScope scope}) async {
    final journal = _journals[scope];
    if (journal == null) {
      return JournalSnapshot(scope: scope, operations: const []);
    }
    return JournalSnapshot(scope: scope, operations: journal.operations);
  }

  JournalPublishResult _commit(
    JournalScope scope,
    List<JournalOperation> batch,
  ) {
    final existing = _journals[scope];
    // Stage on a copy so an unexpected failure mid-batch leaves the committed
    // journal exactly as it was.
    final staged = Journal(
      notebookId: scope.notebookId,
      epochId: scope.epochId,
      operations: existing?.operations ?? const [],
    );
    final appended = <JournalOperation>[];
    final replayed = <JournalOperation>[];
    final conflicts = <JournalRefusal>[];
    for (final operation in batch) {
      final result = staged.admit(operation);
      switch (result.admission) {
        case JournalAdmission.appended:
          appended.add(operation);
        case JournalAdmission.replayed:
          replayed.add(result.operation!);
        case JournalAdmission.collided:
          conflicts.add(
            JournalRefusal(
              scope: scope,
              kind: _kindOf(operation, result.conflict!.conflicting!),
              reason: result.conflict!.reason,
              incoming: operation,
              accepted: result.conflict!.conflicting,
            ),
          );
        case JournalAdmission.rejected:
          conflicts.add(
            JournalRefusal(
              scope: scope,
              kind: JournalRefusalKind.outOfScope,
              reason: result.conflict!.reason,
              incoming: operation,
            ),
          );
      }
    }
    if (appended.isNotEmpty) {
      _journals[scope] = staged;
    }
    return JournalPublishCommitted(
      scope: scope,
      appended: appended,
      replayed: replayed,
      conflicts: conflicts,
    );
  }

  static JournalRefusalKind _kindOf(
    JournalOperation incoming,
    JournalOperation accepted,
  ) {
    if (accepted.operationId == incoming.operationId) {
      return JournalRefusalKind.operationIdCollision;
    }
    if (accepted.actorId == incoming.actorId &&
        accepted.sequence == incoming.sequence) {
      return JournalRefusalKind.actorSequenceCollision;
    }
    return JournalRefusalKind.entryCreationCollision;
  }

  /// Re-decodes the operation's canonical JSON, which is the same validation
  /// applied to stored data, so a subclass that bypasses construction checks
  /// cannot slip into a journal.
  static bool _isWellFormed(JournalOperation operation) {
    try {
      JournalOperation.fromJson(operation.toJson());
      return true;
    } on Object {
      return false;
    }
  }
}
