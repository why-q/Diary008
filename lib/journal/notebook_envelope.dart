/// A versioned document that carries one notebook snapshot and one journal.
///
/// The envelope exists so that a notebook change and the operation describing
/// it can be replaced on disk as a single file. This library is pure Dart: no
/// `dart:io`, no Flutter, and no clock. Reading and replacing the file is the
/// job of `atomic_notebook_store.dart`.
///
/// What the envelope does not model:
///
/// * It carries no digest, signature, or other proof that the notebook snapshot
///   corresponds to the journal's `notebookId`/`epochId`. The notebook model
///   has no such identifiers, so the pairing is asserted by the writer and
///   never verified here. Production hookup is therefore gated until replay
///   (M3.3) defines the relationship.
/// * It is not a backup format. `notebook.json` and its backup schema stay
///   unchanged, and an envelope is never read by the app's notebook storage.
library;

import 'dart:convert';

import '../notebook.dart';
import 'journal.dart';
import 'journal_values.dart';

/// Protocol revision of the envelope document understood by this build.
const int envelopeSchemaVersion = 1;

/// Document discriminator, so an envelope is never mistaken for a notebook.
const String envelopeFormatName = 'diary008.notebook-envelope';

/// Raised when a stored or proposed envelope is malformed or unsupported.
class EnvelopeFormatException implements Exception {
  const EnvelopeFormatException(this.message, {this.field});

  final String message;
  final String? field;

  @override
  String toString() => field == null
      ? 'EnvelopeFormatException: $message'
      : 'EnvelopeFormatException($field): $message';
}

/// The notebook and epoch a store is bound to.
///
/// The journal carries the identifiers; the notebook snapshot does not, so the
/// scope is supplied explicitly and checked against every decoded journal.
class JournalScope {
  JournalScope({required this.notebookId, required this.epochId}) {
    try {
      requireOpaqueId(notebookId, field: 'notebookId');
      requireOpaqueId(epochId, field: 'epochId');
    } on JournalFormatException catch (error) {
      throw EnvelopeFormatException(error.message, field: error.field);
    }
  }

  final String notebookId;
  final String epochId;

  bool covers(Journal journal) =>
      journal.notebookId == notebookId && journal.epochId == epochId;

  @override
  bool operator ==(Object other) =>
      other is JournalScope &&
      other.notebookId == notebookId &&
      other.epochId == epochId;

  @override
  int get hashCode => Object.hash(notebookId, epochId);

  @override
  String toString() => 'JournalScope($notebookId, $epochId)';
}

/// One immutable notebook snapshot plus its journal, at [revision].
///
/// [revision] starts at 1 and increases by exactly one per committed
/// replacement. It is the stale-write token: a writer must name the revision it
/// observed, and a replacement is refused when the stored revision differs.
class NotebookEnvelope {
  NotebookEnvelope({
    required this.revision,
    required this.notebook,
    required this.journal,
  }) {
    if (revision < 1) {
      throw const EnvelopeFormatException(
        'revision must be at least 1',
        field: 'envelope.revision',
      );
    }
    _requireValidSnapshot(notebook);
  }

  final int revision;
  final Notebook notebook;
  final Journal journal;

  JournalScope get scope =>
      JournalScope(notebookId: journal.notebookId, epochId: journal.epochId);

  Map<String, Object?> toJson() => {
    'schemaVersion': envelopeSchemaVersion,
    'format': envelopeFormatName,
    'revision': revision,
    'notebook': notebook.toJson(),
    'journal': journal.toJson(),
  };

  /// Stable encoding. Key order is fixed, so equal content encodes equally.
  String encode() => jsonEncode(toJson());

  bool hasSameContentAs(NotebookEnvelope other) => encode() == other.encode();

  /// Parses and fully validates a stored envelope.
  static NotebookEnvelope decode(String text) {
    final Object? raw;
    try {
      raw = jsonDecode(text);
    } on FormatException {
      throw const EnvelopeFormatException('envelope is not valid JSON');
    }
    return fromJson(raw);
  }

  /// Parses and fully validates a decoded envelope value.
  static NotebookEnvelope fromJson(Object? value) {
    try {
      return _decode(value);
    } on EnvelopeFormatException {
      rethrow;
    } on JournalFormatException catch (error) {
      throw EnvelopeFormatException(error.message, field: error.field);
    } on FormatException {
      throw const EnvelopeFormatException('envelope is malformed');
    } catch (_) {
      // Never surface stored content in an error; messages name fields only.
      throw const EnvelopeFormatException('envelope is malformed');
    }
  }

  static NotebookEnvelope _decode(Object? value) {
    final json = requireJsonObject(value, field: 'envelope');
    requireExactKeys(json, const {
      'schemaVersion',
      'format',
      'revision',
      'notebook',
      'journal',
    }, field: 'envelope');

    final version = json['schemaVersion'];
    if (version is! int) {
      throw const EnvelopeFormatException(
        'schemaVersion must be an integer',
        field: 'envelope.schemaVersion',
      );
    }
    if (version != envelopeSchemaVersion) {
      throw EnvelopeFormatException(
        'unsupported envelope schema version $version',
        field: 'envelope.schemaVersion',
      );
    }
    if (json['format'] != envelopeFormatName) {
      throw const EnvelopeFormatException(
        'envelope format discriminator is missing or wrong',
        field: 'envelope.format',
      );
    }
    final revision = json['revision'];
    if (revision is! int) {
      throw const EnvelopeFormatException(
        'revision must be an integer',
        field: 'envelope.revision',
      );
    }

    final storedNotebook = requireJsonObject(
      json['notebook'],
      field: 'envelope.notebook',
    );
    requireExactKeys(storedNotebook, const {
      'schemaVersion',
      'archives',
      'volume',
      'volumeName',
      'sortOrder',
      'entries',
    }, field: 'notebook');
    final notebookVersion = storedNotebook['schemaVersion'];
    if (notebookVersion is! int) {
      throw const EnvelopeFormatException(
        'notebook schemaVersion must be an integer',
        field: 'notebook.schemaVersion',
      );
    }
    if (notebookVersion != Notebook.storageVersion) {
      // Envelopes never migrate. A different notebook schema needs its own
      // envelope revision and an explicit upgrade path.
      throw EnvelopeFormatException(
        'unsupported notebook schema version $notebookVersion in envelope',
        field: 'notebook.schemaVersion',
      );
    }
    final notebook = Notebook.fromJson(
      Map<String, dynamic>.from(storedNotebook),
    );
    if (!_jsonEquals(notebook.toJson(), storedNotebook)) {
      throw const EnvelopeFormatException(
        'notebook snapshot is not canonical for its schema version',
        field: 'notebook',
      );
    }

    final journal = Journal.fromJson(json['journal']);
    return NotebookEnvelope(
      revision: revision,
      notebook: notebook,
      journal: journal,
    );
  }
}

/// Invariants the app already enforces when it imports a notebook.
///
/// They are repeated here because an envelope must never persist a snapshot
/// that the notebook storage would refuse to load.
void _requireValidSnapshot(Notebook notebook) {
  if (notebook.volume < 1) {
    throw const EnvelopeFormatException(
      'notebook volume must be at least 1',
      field: 'notebook.volume',
    );
  }
  final volumes = <int>{notebook.volume};
  _requireValidEntries(notebook.entries, field: 'notebook.entries');
  for (final archive in notebook.archives) {
    if (archive.volume < 1 ||
        archive.volume >= notebook.volume ||
        !volumes.add(archive.volume)) {
      throw const EnvelopeFormatException(
        'archived volumes must be distinct and lower than the current volume',
        field: 'notebook.archives',
      );
    }
    _requireValidEntries(archive.entries, field: 'notebook.archives.entries');
    final ids = archive.entries.map((entry) => entry.id).toSet();
    if (!ids.containsAll(archive.failedEntryIds)) {
      throw const EnvelopeFormatException(
        'failed entry ids must belong to the archived volume',
        field: 'notebook.archives.failedEntryIds',
      );
    }
  }
}

void _requireValidEntries(List<JournalEntry> entries, {required String field}) {
  final seen = <String>{};
  for (final entry in entries) {
    if (entry.id.isEmpty || !seen.add(entry.id)) {
      throw EnvelopeFormatException(
        'entry ids must be non-empty and unique',
        field: field,
      );
    }
    if (entry.text.trim().isEmpty) {
      throw EnvelopeFormatException(
        'entry text must not be empty',
        field: field,
      );
    }
    final hasDue = entry.due != null;
    if (hasDue == (entry.status == EntryStatus.explanation)) {
      throw EnvelopeFormatException(
        'only explanation entries omit a due date',
        field: field,
      );
    }
  }
}

bool _jsonEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!_jsonEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
