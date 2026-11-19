/// Admission log for offline entry operations.
///
/// The journal only decides whether an operation may be appended. It never
/// rewrites an accepted operation, never merges divergent text, and never
/// derives notebook or entry lineage from content. Applying operations to a
/// notebook is a separate concern.
library;

import 'dart:convert';

import 'journal_operation.dart';
import 'journal_values.dart';

enum JournalAdmission {
  /// The operation was new and is now the last accepted operation.
  appended,

  /// An identical operation was already present; nothing changed.
  replayed,

  /// The operation contradicts accepted content and was refused.
  collided,

  /// The operation does not belong to this journal.
  rejected,
}

/// Why an operation could not be appended.
class JournalConflict {
  const JournalConflict(this.admission, this.reason, {this.conflicting});

  final JournalAdmission admission;
  final String reason;

  /// The already accepted operation the incoming one contradicts.
  final JournalOperation? conflicting;

  bool get isCollision => admission == JournalAdmission.collided;
}

class JournalAdmissionResult {
  const JournalAdmissionResult(this.admission, {this.conflict, this.operation});

  final JournalAdmission admission;
  final JournalConflict? conflict;

  /// The accepted operation for [JournalAdmission.appended] and
  /// [JournalAdmission.replayed], otherwise the refused input.
  final JournalOperation? operation;

  bool get accepted =>
      admission == JournalAdmission.appended ||
      admission == JournalAdmission.replayed;
}

/// An append-only, versioned journal for one notebook epoch.
///
/// [notebookId] and [epochId] are supplied explicitly. Nothing in this class
/// infers either from entry text, entry identifiers, or volume numbers, and no
/// migration or production storage is attached.
///
/// Admission judges identity and consistency only. A revision whose entry has
/// no accepted creation is still admitted, because cross-actor ordering is not
/// decided here; replay must surface it as unresolved instead of dropping it.
class Journal {
  Journal({
    required this.notebookId,
    required this.epochId,
    Iterable<JournalOperation> operations = const [],
  }) {
    requireOpaqueId(notebookId, field: 'notebookId');
    requireOpaqueId(epochId, field: 'epochId');
    for (final operation in operations) {
      final result = admit(operation);
      if (result.admission != JournalAdmission.appended) {
        throw JournalFormatException(
          'stored journal contains a ${result.admission.name} operation '
          '"${operation.operationId}"',
          field: 'operations',
        );
      }
    }
  }

  /// Builds a journal from a stored document, rejecting unknown versions.
  factory Journal.fromJson(Object? value) {
    final json = requireJsonObject(value, field: 'journal');
    requireExactKeys(json, const {
      'schemaVersion',
      'notebookId',
      'epochId',
      'operations',
    }, field: 'journal');
    final version = json['schemaVersion'];
    if (version is! int) {
      throw const JournalFormatException(
        'schemaVersion must be an integer',
        field: 'journal.schemaVersion',
      );
    }
    if (version != journalSchemaVersion) {
      throw JournalFormatException(
        'unsupported journal schema version $version',
        field: 'journal.schemaVersion',
      );
    }
    final stored = json['operations'];
    if (stored is! List) {
      throw const JournalFormatException(
        'operations must be a list',
        field: 'journal.operations',
      );
    }
    return Journal(
      notebookId: requireOpaqueId(json['notebookId'], field: 'notebookId'),
      epochId: requireOpaqueId(json['epochId'], field: 'epochId'),
      operations: stored.map(JournalOperation.fromJson),
    );
  }

  final String notebookId;
  final String epochId;

  final List<JournalOperation> _operations = [];
  final Map<String, JournalOperation> _byOperationId = {};
  final Map<String, Map<int, JournalOperation>> _byActorSequence = {};
  final Map<String, JournalOperation> _createByEntryId = {};

  /// Accepted operations in admission order.
  List<JournalOperation> get operations => List.unmodifiable(_operations);

  int get length => _operations.length;

  bool get isEmpty => _operations.isEmpty;

  JournalOperation? byOperationId(String operationId) =>
      _byOperationId[operationId];

  JournalOperation? byActorSequence(String actorId, int sequence) =>
      _byActorSequence[actorId]?[sequence];

  /// Every accepted operation that addresses [entryId], oldest first.
  List<JournalOperation> operationsForEntry(String entryId) =>
      List.unmodifiable(_operations.where((op) => op.entryId == entryId));

  /// Appends [operation] if it is new, valid, and consistent.
  ///
  /// An exact replay returns [JournalAdmission.replayed] without appending.
  /// A reused operation id, a reused actor sequence, or a second creation of
  /// the same entry with different content returns
  /// [JournalAdmission.collided]; the accepted operation is left untouched.
  JournalAdmissionResult admit(JournalOperation operation) {
    if (operation.notebookId != notebookId) {
      return JournalAdmissionResult(
        JournalAdmission.rejected,
        conflict: const JournalConflict(
          JournalAdmission.rejected,
          'operation belongs to another notebook',
        ),
        operation: operation,
      );
    }
    if (operation.epochId != epochId) {
      return JournalAdmissionResult(
        JournalAdmission.rejected,
        conflict: const JournalConflict(
          JournalAdmission.rejected,
          'operation belongs to another notebook epoch',
        ),
        operation: operation,
      );
    }
    return _appendValidated(operation);
  }

  JournalAdmissionResult _appendValidated(JournalOperation operation) {
    final byId = _byOperationId[operation.operationId];
    if (byId != null) {
      if (byId.hasSameContent(operation)) {
        return JournalAdmissionResult(
          JournalAdmission.replayed,
          operation: byId,
        );
      }
      return JournalAdmissionResult(
        JournalAdmission.collided,
        conflict: JournalConflict(
          JournalAdmission.collided,
          'operation id "${operation.operationId}" is already used by '
          'different content',
          conflicting: byId,
        ),
        operation: operation,
      );
    }

    final bySequence = byActorSequence(operation.actorId, operation.sequence);
    if (bySequence != null) {
      return JournalAdmissionResult(
        JournalAdmission.collided,
        conflict: JournalConflict(
          JournalAdmission.collided,
          'actor "${operation.actorId}" already used sequence '
          '${operation.sequence} for a different operation',
          conflicting: bySequence,
        ),
        operation: operation,
      );
    }

    if (operation is JournalCreateEntry) {
      final existing = _createByEntryId[operation.entryId];
      if (existing != null) {
        return JournalAdmissionResult(
          JournalAdmission.collided,
          conflict: JournalConflict(
            JournalAdmission.collided,
            'entry "${operation.entryId}" was already created by '
            '"${existing.operationId}"',
            conflicting: existing,
          ),
          operation: operation,
        );
      }
    }

    _operations.add(operation);
    _byOperationId[operation.operationId] = operation;
    (_byActorSequence[operation.actorId] ??= {})[operation.sequence] =
        operation;
    if (operation is JournalCreateEntry) {
      _createByEntryId[operation.entryId] = operation;
    }
    return JournalAdmissionResult(
      JournalAdmission.appended,
      operation: operation,
    );
  }

  /// Stable JSON encoding of the whole journal.
  Map<String, Object?> toJson() => {
    'schemaVersion': journalSchemaVersion,
    'notebookId': notebookId,
    'epochId': epochId,
    'operations': [for (final op in _operations) op.toJson()],
  };

  String encode() => jsonEncode(toJson());
}
