/// Versioned, immutable entry operations for the offline journal.
///
/// The protocol is deliberately small: an operation either creates an entry or
/// replaces the text of an existing entry. Deletion, restore, merge, and volume
/// rules are out of scope until they can be specified without losing text.
library;

import 'dart:convert';

import 'journal_values.dart';

enum JournalOperationKind { create, revise }

/// One immutable, fully validated entry operation.
///
/// Identity is carried by [operationId] (the operation) and [entryId] (the
/// entry it addresses). Neither is derived from diary text, a volume ordinal,
/// or a wall-clock reading. [recordedAt] is an explicit UTC instant supplied by
/// the caller; this library never reads a clock.
abstract class JournalOperation {
  const JournalOperation({
    required this.notebookId,
    required this.epochId,
    required this.actorId,
    required this.sequence,
    required this.operationId,
    required this.recordedAt,
    required this.entryId,
    required this.text,
  });

  final String notebookId;
  final String epochId;
  final String actorId;

  /// Per-actor monotonic counter, starting at 1.
  final int sequence;

  final String operationId;
  final DateTime recordedAt;
  final String entryId;
  final String text;

  JournalOperationKind get kind;

  /// Payload fields specific to [kind], excluding the shared header.
  Map<String, Object?> payloadFields();

  /// Stable JSON encoding. Key order is fixed so encodings can be compared.
  Map<String, Object?> toJson() => {
    'schemaVersion': journalSchemaVersion,
    'kind': kind.name,
    'notebookId': notebookId,
    'epochId': epochId,
    'actorId': actorId,
    'sequence': sequence,
    'operationId': operationId,
    'recordedAt': formatUtcInstant(recordedAt, field: 'recordedAt'),
    'entryId': entryId,
    'text': text,
    ...payloadFields(),
  };

  /// Canonical text used for replay and collision comparison.
  String get canonicalForm => jsonEncode(toJson());

  bool hasSameContent(JournalOperation other) =>
      canonicalForm == other.canonicalForm;

  /// Parses and validates one operation from decoded JSON.
  ///
  /// Unknown keys, missing keys, unsupported [journalSchemaVersion] values,
  /// and payload fields that do not belong to the declared kind are rejected
  /// rather than ignored.
  static JournalOperation fromJson(Object? value) {
    final json = requireJsonObject(value, field: 'operation');
    final version = requireJsonValue(json, 'schemaVersion', field: 'operation');
    if (version is! int) {
      throw const JournalFormatException(
        'schemaVersion must be an integer',
        field: 'operation.schemaVersion',
      );
    }
    if (version != journalSchemaVersion) {
      throw JournalFormatException(
        'unsupported journal schema version $version',
        field: 'operation.schemaVersion',
      );
    }
    final kindName = requireJsonValue(json, 'kind', field: 'operation');
    if (kindName is! String) {
      throw const JournalFormatException(
        'kind must be a string',
        field: 'operation.kind',
      );
    }
    final kind = switch (kindName) {
      'create' => JournalOperationKind.create,
      'revise' => JournalOperationKind.revise,
      _ => throw JournalFormatException(
        'unsupported operation kind "$kindName"',
        field: 'operation.kind',
      ),
    };
    requireExactKeys(
      json,
      kind == JournalOperationKind.create
          ? {..._sharedKeys, 'createdOn'}
          : _sharedKeys,
      field: 'operation',
    );
    final sequence = requireJsonValue(json, 'sequence', field: 'operation');
    if (sequence is! int) {
      throw const JournalFormatException(
        'sequence must be an integer',
        field: 'operation.sequence',
      );
    }
    final header = <String, Object?>{
      'notebookId': requireOpaqueId(
        requireJsonValue(json, 'notebookId', field: 'operation'),
        field: 'notebookId',
      ),
      'epochId': requireOpaqueId(
        requireJsonValue(json, 'epochId', field: 'operation'),
        field: 'epochId',
      ),
      'actorId': requireOpaqueId(
        requireJsonValue(json, 'actorId', field: 'operation'),
        field: 'actorId',
      ),
      'sequence': sequence,
      'operationId': requireOpaqueId(
        requireJsonValue(json, 'operationId', field: 'operation'),
        field: 'operationId',
      ),
      'recordedAt': parseUtcInstant(
        requireJsonValue(json, 'recordedAt', field: 'operation'),
        field: 'recordedAt',
      ),
      'entryId': requireOpaqueId(
        requireJsonValue(json, 'entryId', field: 'operation'),
        field: 'entryId',
      ),
      'text': requireJournalText(
        requireJsonValue(json, 'text', field: 'operation'),
      ),
    };
    switch (kind) {
      case JournalOperationKind.create:
        return JournalCreateEntry(
          notebookId: header['notebookId']! as String,
          epochId: header['epochId']! as String,
          actorId: header['actorId']! as String,
          sequence: header['sequence']! as int,
          operationId: header['operationId']! as String,
          recordedAt: header['recordedAt']! as DateTime,
          entryId: header['entryId']! as String,
          text: header['text']! as String,
          createdOn: CivilDate.parse(
            requireJsonValue(json, 'createdOn', field: 'operation'),
          ),
        );
      case JournalOperationKind.revise:
        return JournalReviseEntry(
          notebookId: header['notebookId']! as String,
          epochId: header['epochId']! as String,
          actorId: header['actorId']! as String,
          sequence: header['sequence']! as int,
          operationId: header['operationId']! as String,
          recordedAt: header['recordedAt']! as DateTime,
          entryId: header['entryId']! as String,
          text: header['text']! as String,
        );
    }
  }
}

const Set<String> _sharedKeys = {
  'schemaVersion',
  'kind',
  'notebookId',
  'epochId',
  'actorId',
  'sequence',
  'operationId',
  'recordedAt',
  'entryId',
  'text',
};

/// Creates an entry.
///
/// [createdOn] is the civil date the writer attributes the entry to. It is
/// stored separately from [recordedAt] because no time zone is assumed.
class JournalCreateEntry extends JournalOperation {
  JournalCreateEntry({
    required super.notebookId,
    required super.epochId,
    required super.actorId,
    required super.sequence,
    required super.operationId,
    required super.recordedAt,
    required super.entryId,
    required super.text,
    required this.createdOn,
  }) {
    _checkHeader(
      notebookId: notebookId,
      epochId: epochId,
      actorId: actorId,
      sequence: sequence,
      operationId: operationId,
      recordedAt: recordedAt,
      entryId: entryId,
      text: text,
    );
  }

  final CivilDate createdOn;

  @override
  JournalOperationKind get kind => JournalOperationKind.create;

  @override
  Map<String, Object?> payloadFields() => {'createdOn': createdOn.text};
}

/// Replaces the text of an existing entry.
///
/// A revision carries no civil date: it records a change to existing text, not
/// a new diary day, and the notebook model has no revision day.
class JournalReviseEntry extends JournalOperation {
  JournalReviseEntry({
    required super.notebookId,
    required super.epochId,
    required super.actorId,
    required super.sequence,
    required super.operationId,
    required super.recordedAt,
    required super.entryId,
    required super.text,
  }) {
    _checkHeader(
      notebookId: notebookId,
      epochId: epochId,
      actorId: actorId,
      sequence: sequence,
      operationId: operationId,
      recordedAt: recordedAt,
      entryId: entryId,
      text: text,
    );
  }

  @override
  JournalOperationKind get kind => JournalOperationKind.revise;

  @override
  Map<String, Object?> payloadFields() => const {};
}

void _checkHeader({
  required String notebookId,
  required String epochId,
  required String actorId,
  required int sequence,
  required String operationId,
  required DateTime recordedAt,
  required String entryId,
  required String text,
}) {
  requireOpaqueId(notebookId, field: 'notebookId');
  requireOpaqueId(epochId, field: 'epochId');
  requireOpaqueId(actorId, field: 'actorId');
  requireOpaqueId(operationId, field: 'operationId');
  requireOpaqueId(entryId, field: 'entryId');
  requireJournalText(text);
  if (sequence < 1) {
    throw const JournalFormatException(
      'sequence must be at least 1',
      field: 'operation.sequence',
    );
  }
  if (!recordedAt.isUtc) {
    throw const JournalFormatException(
      'recordedAt must be UTC',
      field: 'operation.recordedAt',
    );
  }
}
