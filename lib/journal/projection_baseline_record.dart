/// Versioned record of the notebook snapshot a journal was projected onto.
///
/// Experimental and unshipped: no production code imports this file, nothing in
/// the app reads or writes it, and it is not a notebook format. It exists
/// because projection-backed commits need a seed that is *recorded* rather than
/// supplied afresh on every call, and because a seed is only meaningful if it
/// names the notebook and epoch it belongs to.
///
/// What the record is
/// ------------------
/// One immutable value: a [JournalScope] (`notebookId` and `epochId`), the
/// canonical notebook snapshot taken before the journal accepted any operation,
/// and the two facts that make it a *pre-journal* baseline rather than a
/// current snapshot:
///
/// * `initialRevision` is exactly `1`, the first envelope revision.
/// * `initialJournalOperationCount` is exactly `0`, so the journal bound to
///   this baseline was empty when the baseline was recorded.
///
/// Both are stored, not inferred. A document that claims a later revision or a
/// non-empty journal at binding time is refused instead of being reinterpreted,
/// and a revision 1 envelope whose journal is no longer empty no longer matches
/// this binding.
///
/// What the record is not
/// ----------------------
/// * It is not a second notebook. It is never edited, never re-projected, and
///   never written by a commit; it carries one snapshot that must stay fixed
///   for the lifetime of the envelope it seeds.
/// * It is not a proof of provenance. [verifyEnvelope] re-derives the
///   projection from the record, so it catches a snapshot that does not match
///   the journal *and* the record together. It cannot detect an external writer
///   that replaces the record with a different but internally coherent record,
///   nor a rollback to an earlier coherent pair. Nothing here is signed,
///   chained, or anchored, and no claim of tamper resistance is made.
/// * It is not a backup format, and it does not change any existing schema.
///
/// Strictness
/// ----------
/// Decoding accepts only the exact key set, the exact schema version, the exact
/// format discriminator, a valid scope, and a notebook snapshot that is
/// canonical for its own schema version. A malformed document throws
/// [EnvelopeFormatException] naming fields only, so no diary text is echoed
/// from stored content. Nothing is migrated, repaired, or upgraded.
library;

import 'dart:convert';

import '../notebook.dart';
import 'journal_replay.dart';
import 'journal_snapshot_equivalence.dart';
import 'journal_values.dart';
import 'notebook_envelope.dart';

/// Protocol revision of the baseline record understood by this build.
const int projectionBaselineRecordSchemaVersion = 1;

/// Document discriminator, so a record is never mistaken for a notebook, an
/// envelope, or an epoch ledger.
const String projectionBaselineRecordFormatName =
    'diary008.projection-baseline';

/// The only envelope revision a baseline may be bound to.
const int _boundInitialRevision = 1;

/// The only journal length a baseline may be bound to.
const int _boundInitialJournalOperationCount = 0;

/// Outcome of comparing a stored envelope with a recorded baseline.
enum ProjectionBaselineVerification {
  /// The envelope belongs to the record's scope and its snapshot is exactly
  /// what this record's baseline and the envelope's journal produce.
  valid,

  /// The envelope names another notebook or epoch.
  scopeMismatch,

  /// The envelope is at revision 1 but its journal already holds operations, so
  /// it is not the empty-journal document this record binds.
  initialJournalNotEmpty,

  /// The envelope's snapshot is not the baseline at revision 1, or is not the
  /// projection of its journal onto the baseline at a later revision.
  snapshotMismatch,

  /// A later revision's journal cannot be projected onto the baseline without
  /// an unresolved conflict, so no snapshot can be shown to match it.
  projectionConflict;

  bool get isValid => this == ProjectionBaselineVerification.valid;

  /// Stable, content-free code suitable for diagnostics.
  String get diagnosticCode => 'journal.baseline.$name';
}

/// One recorded pre-journal baseline for one notebook epoch.
///
/// Construction canonicalizes and validates [notebook], so a baseline whose
/// getters and encoding disagree is refused at construction and the value this
/// object reports cannot drift afterwards. Non-empty baselines are supported:
/// a journal is seeded from whatever snapshot the notebook already had.
final class ProjectionBaselineRecord {
  ProjectionBaselineRecord._({required this.scope, required this.notebook});

  /// Records [notebook] as the pre-journal baseline for [scope].
  ///
  /// Throws [EnvelopeFormatException] when the snapshot is not canonically
  /// decodable or violates the notebook invariants the app already enforces.
  factory ProjectionBaselineRecord({
    required JournalScope scope,
    required Notebook notebook,
  }) {
    final canonical = CanonicalSnapshot.tryCanonicalize(notebook);
    if (canonical == null) {
      throw const EnvelopeFormatException(
        'baseline snapshot is not a canonically decodable notebook',
        field: 'baseline.notebook',
      );
    }
    return ProjectionBaselineRecord._(
      scope: scope,
      notebook: canonical.notebook,
    );
  }

  /// The notebook and epoch this baseline belongs to.
  final JournalScope scope;

  /// The plain snapshot taken before any operation was accepted. It is not the
  /// caller's object, so later changes to that object cannot affect this value.
  final Notebook notebook;

  Map<String, Object?> toJson() => {
    'schemaVersion': projectionBaselineRecordSchemaVersion,
    'format': projectionBaselineRecordFormatName,
    'scope': {'notebookId': scope.notebookId, 'epochId': scope.epochId},
    'initialRevision': _boundInitialRevision,
    'initialJournalOperationCount': _boundInitialJournalOperationCount,
    'notebook': notebook.toJson(),
  };

  /// Stable encoding. Key order is fixed, so equal content encodes equally.
  String encode() => jsonEncode(toJson());

  bool hasSameContentAs(ProjectionBaselineRecord other) =>
      encode() == other.encode();

  /// Parses and fully validates a stored record.
  static ProjectionBaselineRecord decode(String text) {
    final Object? raw;
    try {
      raw = jsonDecode(text);
    } on FormatException {
      throw const EnvelopeFormatException('baseline record is not valid JSON');
    }
    return fromJson(raw);
  }

  /// Parses and fully validates a decoded record value.
  static ProjectionBaselineRecord fromJson(Object? value) {
    try {
      return _decode(value);
    } on EnvelopeFormatException {
      rethrow;
    } on JournalFormatException catch (error) {
      throw EnvelopeFormatException(error.message, field: error.field);
    } on FormatException {
      throw const EnvelopeFormatException('baseline record is malformed');
    } catch (_) {
      // Never surface stored content in an error; messages name fields only.
      throw const EnvelopeFormatException('baseline record is malformed');
    }
  }

  static ProjectionBaselineRecord _decode(Object? value) {
    final json = requireJsonObject(value, field: 'baseline');
    requireExactKeys(json, const {
      'schemaVersion',
      'format',
      'scope',
      'initialRevision',
      'initialJournalOperationCount',
      'notebook',
    }, field: 'baseline');

    final version = json['schemaVersion'];
    if (version is! int) {
      throw const EnvelopeFormatException(
        'schemaVersion must be an integer',
        field: 'baseline.schemaVersion',
      );
    }
    if (version != projectionBaselineRecordSchemaVersion) {
      throw EnvelopeFormatException(
        'unsupported baseline record schema version $version',
        field: 'baseline.schemaVersion',
      );
    }
    if (json['format'] != projectionBaselineRecordFormatName) {
      throw const EnvelopeFormatException(
        'baseline record format discriminator is missing or wrong',
        field: 'baseline.format',
      );
    }

    final initialRevision = json['initialRevision'];
    if (initialRevision is! int || initialRevision != _boundInitialRevision) {
      // A baseline is only meaningful for the first envelope revision. Any
      // other value is refused rather than reinterpreted.
      throw const EnvelopeFormatException(
        'a baseline can only be bound to the initial envelope revision',
        field: 'baseline.initialRevision',
      );
    }
    final initialJournalCount = json['initialJournalOperationCount'];
    if (initialJournalCount is! int ||
        initialJournalCount != _boundInitialJournalOperationCount) {
      throw const EnvelopeFormatException(
        'a baseline must be bound to an empty journal',
        field: 'baseline.initialJournalOperationCount',
      );
    }

    final storedScope = requireJsonObject(
      json['scope'],
      field: 'baseline.scope',
    );
    requireExactKeys(storedScope, const {
      'notebookId',
      'epochId',
    }, field: 'baseline.scope');
    final scope = JournalScope(
      notebookId: requireOpaqueId(
        storedScope['notebookId'],
        field: 'scope.notebookId',
      ),
      epochId: requireOpaqueId(storedScope['epochId'], field: 'scope.epochId'),
    );

    final storedNotebook = requireJsonObject(
      json['notebook'],
      field: 'baseline.notebook',
    );
    requireExactKeys(storedNotebook, const {
      'schemaVersion',
      'archives',
      'volume',
      'volumeName',
      'sortOrder',
      'entries',
    }, field: 'baseline.notebook');
    final notebookVersion = storedNotebook['schemaVersion'];
    if (notebookVersion is! int) {
      throw const EnvelopeFormatException(
        'notebook schemaVersion must be an integer',
        field: 'baseline.notebook.schemaVersion',
      );
    }
    if (notebookVersion != Notebook.storageVersion) {
      throw EnvelopeFormatException(
        'unsupported notebook schema version $notebookVersion in baseline',
        field: 'baseline.notebook.schemaVersion',
      );
    }
    final notebook = Notebook.fromJson(
      Map<String, dynamic>.from(storedNotebook),
    );
    // A record must never carry a snapshot the notebook storage would refuse
    // to load, so the same invariants are enforced here as on construction.
    validateNotebookSnapshot(notebook);
    if (!_jsonEquals(notebook.toJson(), storedNotebook)) {
      throw const EnvelopeFormatException(
        'baseline snapshot is not canonical for its schema version',
        field: 'baseline.notebook',
      );
    }

    return ProjectionBaselineRecord(scope: scope, notebook: notebook);
  }

  /// Compares [envelope] with this recorded baseline.
  ///
  /// At revision 1 the envelope's journal must be empty and its snapshot must
  /// be this baseline exactly. At any later revision the envelope's journal is
  /// replayed onto this baseline and the result must be conflict-free and
  /// equal to the envelope's snapshot.
  ///
  /// This is a consistency check between one envelope and one record. It says
  /// nothing about whether either was produced by a legitimate writer: an
  /// externally supplied record and envelope that agree with each other are
  /// accepted, and a rollback to an earlier agreeing pair is accepted too.
  ProjectionBaselineVerification verifyEnvelope(NotebookEnvelope envelope) {
    if (envelope.scope != scope) {
      return ProjectionBaselineVerification.scopeMismatch;
    }
    final canonical = CanonicalSnapshot.tryCanonicalize(envelope.notebook);
    if (canonical == null) {
      return ProjectionBaselineVerification.snapshotMismatch;
    }
    if (envelope.revision == _boundInitialRevision) {
      if (!envelope.journal.isEmpty) {
        return ProjectionBaselineVerification.initialJournalNotEmpty;
      }
      return _sameSnapshot(canonical.notebook, notebook)
          ? ProjectionBaselineVerification.valid
          : ProjectionBaselineVerification.snapshotMismatch;
    }
    final JournalReplayResult projection;
    try {
      projection = JournalReplay.project(
        notebookId: scope.notebookId,
        epochId: scope.epochId,
        base: notebook,
        journal: envelope.journal,
      );
    } on JournalFormatException {
      // The scope was already compared, so this is defensive only.
      return ProjectionBaselineVerification.scopeMismatch;
    }
    if (projection.hasConflicts) {
      return ProjectionBaselineVerification.projectionConflict;
    }
    return isSnapshotEquivalentToProjection(canonical.notebook, projection)
        ? ProjectionBaselineVerification.valid
        : ProjectionBaselineVerification.snapshotMismatch;
  }

  @override
  String toString() => 'ProjectionBaselineRecord($scope)';
}

bool _sameSnapshot(Notebook a, Notebook b) =>
    jsonEncode(a.toJson()) == jsonEncode(b.toJson());

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
