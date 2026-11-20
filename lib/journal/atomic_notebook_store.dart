/// Single-file storage for [NotebookEnvelope] documents.
///
/// Scope and ownership
/// -------------------
/// One envelope file has one writer at a time inside this isolate. Commits are
/// serialized per normalized target path, so two [AtomicNotebookStore]
/// instances in the same isolate that name the same file cannot interleave a
/// read-check-write, and only one of them can report a durable change.
///
/// Limits that remain, and are not claimed to be solved here:
///
/// * Nothing here coordinates a second isolate or a second process. Two
///   isolates or processes pointed at the same file can still both read the
///   same revision and then overwrite each other.
/// * The path lock is keyed by a normalized absolute path. Symlinks, hard
///   links, case-insensitive file systems, bind mounts, and different
///   `Directory` spellings that resolve to the same inode are still distinct
///   keys, so they are not coordinated.
/// * Durability is limited to `writeAsBytes(flush: true)` followed by
///   `rename` in the same directory. That ordering survives a process crash,
///   but it is not a tested power-loss guarantee, and no `fsync` of the
///   directory is performed. A sudden power loss can leave the rename
///   undurable even after it was reported as committed.
///
/// Every commit writes a uniquely named temporary file in the target
/// directory, so a stale temp file from a crashed writer is never reused and
/// never overwrites another writer's bytes.
///
/// Projection-backed validation (opt in)
/// -------------------------------------
/// By default a commit still trusts the caller's snapshot/operation pairing,
/// and the caller's own object is validated and persisted as before.
/// [AtomicNotebookStore.projectionValidated] turns on the stronger mode: the
/// caller supplies an explicit, immutable pre-journal baseline, and every
/// commit replays the journal onto that baseline and compares both the
/// persisted snapshot and the offered next snapshot with the result. A
/// conflict or any mismatch is refused before a temporary file is written.
/// In that mode the caller's object is never consulted: only its canonical,
/// decoded form is compared or persisted.
///
/// This adapter is experimental and is not wired into the app. `notebook.json`
/// keeps its own format and its own writer, and is refused as a target.
library;

import 'dart:convert';
import 'dart:io';

import '../notebook.dart';
import 'journal.dart';
import 'journal_operation.dart';
import 'journal_projection_gate.dart';
import 'notebook_envelope.dart';

/// File name reserved for the app's notebook document.
const String _reservedNotebookFileName = 'notebook.json';

/// Lowercases ASCII letters only, so the reserved name is refused identically
/// on case-sensitive and case-insensitive file systems.
String _asciiLowerCase(String value) {
  final units = value.codeUnits;
  var changed = false;
  final lowered = List<int>.generate(units.length, (index) {
    final unit = units[index];
    if (unit >= 0x41 && unit <= 0x5A) {
      changed = true;
      return unit + 0x20;
    }
    return unit;
  });
  return changed ? String.fromCharCodes(lowered) : value;
}

/// True when [file] names the app notebook document, ignoring ASCII case and
/// trailing separators or `.` segments.
bool _targetsReservedNotebook(File file) {
  final segments = file.uri.pathSegments;
  for (var index = segments.length - 1; index >= 0; index--) {
    final segment = segments[index];
    if (segment.isEmpty || segment == '.') continue;
    return _asciiLowerCase(segment) == _reservedNotebookFileName;
  }
  return false;
}

/// Outcome of [AtomicNotebookStore.commit].
enum EnvelopeCommitStatus {
  /// The new revision replaced the stored file. This is the only status that
  /// claims a durable change.
  committed,

  /// The journal already held this operation and the notebook is unchanged.
  noChange,

  /// The operation was already stored, but a different notebook snapshot was
  /// offered. Nothing was written.
  duplicate,

  /// Admission refused the operation. Nothing was written.
  conflict,

  /// The caller's base revision is not the stored revision, or the base
  /// content does not match the stored content. Nothing was written.
  stale,

  /// The operation was admitted, but the offered notebook snapshot does not
  /// differ from the stored one. Persisting it would store an operation whose
  /// effect is absent from the snapshot, so nothing was written.
  inconsistent,

  /// The envelope or operation belongs to another notebook or epoch. Nothing
  /// was written.
  scopeMismatch,

  /// Projection validation is on and a snapshot is not the journal's
  /// projection onto the baseline: either the persisted snapshot already
  /// drifted from its journal, or the offered snapshot does not match the
  /// projection. Nothing was written.
  projectionMismatch,

  /// Projection validation is on and the offered journal cannot be projected
  /// onto the baseline without an unresolved conflict, so no snapshot can
  /// represent it. Nothing was written.
  projectionConflict,

  /// Validation or the file replacement failed. The stored bytes were left
  /// untouched. Never reported as [committed].
  ///
  /// Also reported when the proposed snapshot is one the store would refuse to
  /// load again: an envelope that cannot carry the snapshot is not written, so
  /// the caller gets a typed result instead of an exception.
  failed,
}

class EnvelopeCommitResult {
  const EnvelopeCommitResult(
    this.status, {
    this.envelope,
    this.admission,
    this.conflict,
    this.reason,
  });

  final EnvelopeCommitStatus status;

  /// The stored envelope after the call: the new revision when
  /// [EnvelopeCommitStatus.committed], otherwise the previously stored one.
  final NotebookEnvelope? envelope;

  /// Journal admission for the offered operation, when admission ran.
  final JournalAdmissionResult? admission;

  /// Why admission refused the operation, for
  /// [EnvelopeCommitStatus.conflict] and [EnvelopeCommitStatus.scopeMismatch].
  final JournalConflict? conflict;

  /// Short machine-readable explanation. Never contains diary text.
  final String? reason;

  bool get isCommitted => status == EnvelopeCommitStatus.committed;
}

/// The stored envelope belongs to a different notebook or epoch.
class EnvelopeScopeMismatch implements Exception {
  const EnvelopeScopeMismatch(this.expected, this.actual);

  final JournalScope expected;
  final JournalScope actual;

  @override
  String toString() =>
      'EnvelopeScopeMismatch: expected $expected, stored $actual';
}

/// Normalized path -> tail of the commit chain for that target.
final Map<String, Future<void>> _pathTails = {};

/// Serializes commits that name the same normalized envelope path.
///
/// The key is the absolute path of [file] with `.` and `..` segments and
/// duplicate separators resolved lexically. Spellings that differ only in those
/// ways share one chain. Symlinks, hard links, and case-insensitive aliases do
/// not.
String _lockKey(File file) => _normalizePath(file.absolute.path);

String _normalizePath(String path) {
  final separator = Platform.pathSeparator;
  final isAbsolute = path.startsWith(separator);
  final segments = <String>[];
  for (final segment in path.split(separator)) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (segments.isNotEmpty && segments.last != '..') {
        segments.removeLast();
      } else if (!isAbsolute) {
        segments.add('..');
      }
      continue;
    }
    segments.add(segment);
  }
  return '${isAbsolute ? separator : ''}${segments.join(separator)}';
}

class AtomicNotebookStore {
  AtomicNotebookStore(this.file, {required this.scope, this.beforeReplace})
    : projectionBaseline = null {
    _refuseReservedTarget(file);
  }

  /// Same store with projection-backed validation turned on.
  ///
  /// [baseline] is required, so this mode cannot be entered without one. It
  /// must name the same scope as [scope] and must be the snapshot taken before
  /// this envelope accepted any operation; a baseline from another scope is
  /// refused at construction, before any read or write.
  AtomicNotebookStore.projectionValidated(
    this.file, {
    required this.scope,
    required JournalProjectionBaseline baseline,
    this.beforeReplace,
  }) : projectionBaseline = _requireMatchingBaseline(scope, baseline) {
    _refuseReservedTarget(file);
  }

  static JournalProjectionBaseline _requireMatchingBaseline(
    JournalScope scope,
    JournalProjectionBaseline baseline,
  ) {
    if (baseline.scope != scope) {
      throw ArgumentError.value(
        baseline,
        'baseline',
        'projection baseline belongs to another notebook or epoch',
      );
    }
    return baseline;
  }

  static void _refuseReservedTarget(File file) {
    if (file.uri.pathSegments.isEmpty || _targetsReservedNotebook(file)) {
      // The app's notebook document is never an envelope. Refuse the target at
      // construction so no write, temp file, or rename can touch it, on every
      // platform, whatever the ASCII case of the name.
      throw ArgumentError.value(
        file.path,
        'file',
        'refuses the app notebook document as an envelope target',
      );
    }
  }

  /// Envelope file. Its directory must already exist.
  final File file;

  /// Notebook and epoch this store accepts. Every read and commit is checked
  /// against it.
  final JournalScope scope;

  /// Test seam that runs after the temporary file is written and validated but
  /// before it replaces [file]. Production callers leave it null.
  final Future<void> Function()? beforeReplace;

  /// The pre-journal baseline when projection validation is on, otherwise
  /// null. See [AtomicNotebookStore.projectionValidated].
  final JournalProjectionBaseline? projectionBaseline;

  int _tempCounter = 0;

  /// Reads the stored envelope, or `null` when the file does not exist.
  ///
  /// A malformed, unsupported, or out-of-scope document throws instead of
  /// being repaired, migrated, or overwritten.
  Future<NotebookEnvelope?> read() async {
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    final String text;
    try {
      // Decode explicitly so malformed bytes fail closed with a message that
      // carries neither the bytes nor the file path.
      text = utf8.decode(bytes);
    } on FormatException {
      throw const EnvelopeFormatException('envelope is not valid UTF-8');
    }
    final envelope = NotebookEnvelope.decode(text);
    if (!scope.covers(envelope.journal)) {
      throw EnvelopeScopeMismatch(scope, envelope.scope);
    }
    return envelope;
  }

  /// Admits [operation] and persists [notebook] as the next revision, in one
  /// replacement of [file].
  ///
  /// [base] must be the envelope the caller read and [notebook] must be the
  /// snapshot that already includes the operation's effect. In the default
  /// mode that correspondence is asserted by the caller: the notebook model
  /// carries no notebook, epoch, or entry-operation identity, so it cannot be
  /// verified here, and the caller's own object is what gets persisted.
  /// [AtomicNotebookStore.projectionValidated] instead derives the
  /// correspondence by replay and persists only the canonical decoded form.
  /// Neither mode is wired into the app.
  Future<EnvelopeCommitResult> commit({
    required NotebookEnvelope base,
    required Notebook notebook,
    required JournalOperation operation,
  }) {
    final key = _lockKey(file);
    final tail = _pathTails[key] ?? Future<void>.value();
    final result = tail.then(
      (_) => _commit(base: base, notebook: notebook, operation: operation),
    );
    final chain = result.then((_) {}, onError: (_) {});
    _pathTails[key] = chain;
    chain.whenComplete(() {
      if (identical(_pathTails[key], chain)) _pathTails.remove(key);
    });
    return result;
  }

  Future<EnvelopeCommitResult> _commit({
    required NotebookEnvelope base,
    required Notebook notebook,
    required JournalOperation operation,
  }) async {
    final NotebookEnvelope? stored;
    try {
      stored = await read();
    } on EnvelopeFormatException catch (error) {
      // Stored bytes are malformed, unsupported, or not UTF-8. Fail closed:
      // nothing is written and the raw document is left for recovery.
      return EnvelopeCommitResult(
        EnvelopeCommitStatus.failed,
        reason: 'stored envelope cannot be read: ${error.message}',
      );
    } on EnvelopeScopeMismatch {
      return EnvelopeCommitResult(
        EnvelopeCommitStatus.scopeMismatch,
        reason: 'stored envelope belongs to another scope',
      );
    } on FileSystemException {
      return EnvelopeCommitResult(
        EnvelopeCommitStatus.failed,
        reason: 'stored envelope cannot be read',
      );
    }
    if (stored == null) {
      return EnvelopeCommitResult(
        EnvelopeCommitStatus.stale,
        reason: 'no stored envelope to update',
      );
    }
    if (stored.revision != base.revision || !stored.hasSameContentAs(base)) {
      return EnvelopeCommitResult(
        EnvelopeCommitStatus.stale,
        envelope: stored,
        reason: stored.revision == base.revision
            ? 'base envelope does not match stored content'
            : 'base revision ${base.revision} is not stored revision '
                  '${stored.revision}',
      );
    }
    if (!scope.covers(base.journal)) {
      return EnvelopeCommitResult(
        EnvelopeCommitStatus.scopeMismatch,
        envelope: stored,
        reason: 'base envelope belongs to another scope',
      );
    }

    final baseline = projectionBaseline;

    // Canonicalization is exclusive to projection mode. The default mode keeps
    // the published storage path: the caller's own object is compared,
    // validated, and encoded, so a caller object that cannot be encoded, or
    // whose own getters are broken, surfaces its error exactly as before
    // instead of being converted into a typed refusal.
    CanonicalSnapshot? offered;
    if (baseline != null) {
      // The persisted snapshot must already be the journal's projection.
      // Checked before admission so an already drifted or corrupt projection
      // is refused even for an operation that would otherwise be a no-op. It
      // runs on the decoded stored envelope, never on the caller's object.
      final storedCheck = checkStoredProjection(
        baseline: baseline,
        stored: stored,
      );
      if (!storedCheck.isValid) {
        return EnvelopeCommitResult(
          _statusForProjection(storedCheck),
          envelope: stored,
          reason: storedCheck.diagnosticCode,
        );
      }
      // Canonicalize the offered snapshot exactly once, here, inside the lock.
      // The decoded value is the only snapshot this mode will ever encode,
      // compare, or return: the caller's object is not consulted, so a
      // snapshot whose getters and encoding disagree cannot be validated with
      // one shape and persisted with another.
      offered = CanonicalSnapshot.tryCanonicalize(notebook);
      if (offered == null) {
        // The offered snapshot has no canonically decodable form, so nothing
        // about it can be trusted enough to persist.
        return EnvelopeCommitResult(
          EnvelopeCommitStatus.projectionMismatch,
          envelope: stored,
          reason: projectionDiagnosticCode(
            JournalProjectionStatus.projectionMismatch,
          ),
        );
      }
    }
    final offeredNotebook = offered?.notebook ?? notebook;

    final journal = Journal(
      notebookId: base.journal.notebookId,
      epochId: base.journal.epochId,
      operations: base.journal.operations,
    );
    final admission = journal.admit(operation);
    switch (admission.admission) {
      case JournalAdmission.rejected:
        return EnvelopeCommitResult(
          EnvelopeCommitStatus.scopeMismatch,
          envelope: stored,
          admission: admission,
          conflict: admission.conflict,
          reason: 'operation does not belong to this journal',
        );
      case JournalAdmission.collided:
        return EnvelopeCommitResult(
          EnvelopeCommitStatus.conflict,
          envelope: stored,
          admission: admission,
          conflict: admission.conflict,
          reason: 'operation contradicts accepted content',
        );
      case JournalAdmission.replayed:
        return EnvelopeCommitResult(
          _sameNotebook(stored.notebook, offeredNotebook)
              ? EnvelopeCommitStatus.noChange
              : EnvelopeCommitStatus.duplicate,
          envelope: stored,
          admission: admission,
          reason: 'operation is already stored',
        );
      case JournalAdmission.appended:
        break;
    }

    if (baseline != null) {
      // The offered snapshot must be the projection of the journal that is
      // about to be stored, not merely different from the stored one.
      final offeredCheck = checkOfferedProjection(
        baseline: baseline,
        journal: journal,
        notebook: offered,
      );
      if (!offeredCheck.isValid) {
        return EnvelopeCommitResult(
          _statusForProjection(offeredCheck),
          envelope: stored,
          admission: admission,
          reason: offeredCheck.diagnosticCode,
        );
      }
    }

    if (_sameNotebook(stored.notebook, offeredNotebook)) {
      // The journal changed but the snapshot did not. Persisting that would
      // record an operation whose effect is not in the notebook, so refuse.
      return EnvelopeCommitResult(
        EnvelopeCommitStatus.inconsistent,
        envelope: stored,
        admission: admission,
        reason: 'notebook snapshot does not reflect the appended operation',
      );
    }

    // Build the replacement envelope first, so a proposed snapshot the store
    // would refuse to load again is reported as `failed` instead of being
    // written. Only the typed format rejection is converted; any other error
    // from the snapshot is a programmer error and keeps propagating.
    final NotebookEnvelope next;
    try {
      next = NotebookEnvelope(
        revision: base.revision + 1,
        notebook: offeredNotebook,
        journal: journal,
      );
    } on EnvelopeFormatException {
      return EnvelopeCommitResult(
        EnvelopeCommitStatus.failed,
        envelope: stored,
        admission: admission,
        reason: 'proposed notebook snapshot is not a valid stored snapshot',
      );
    }

    return _replace(stored, next, admission);
  }

  Future<EnvelopeCommitResult> _replace(
    NotebookEnvelope stored,
    NotebookEnvelope next,
    JournalAdmissionResult admission,
  ) async {
    // Encoding runs outside the storage `try`: a failure here is a programmer
    // error in the snapshot, not a storage failure, so it must propagate.
    final bytes = utf8.encode(next.encode());
    // A unique name per attempt: a crashed writer's stale temp file is never
    // reopened, and two instances can never share one temporary file.
    final temp = File(
      '${file.path}.$pid-${_tempCounter++}-'
      '${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      // Checked validation: the exact bytes about to be renamed must decode to
      // the intended envelope before the stored file is touched.
      final verified = NotebookEnvelope.decode(utf8.decode(bytes));
      if (!verified.hasSameContentAs(next)) {
        return EnvelopeCommitResult(
          EnvelopeCommitStatus.failed,
          envelope: stored,
          admission: admission,
          reason: 'encoded envelope did not round trip',
        );
      }
      if (!scope.covers(verified.journal)) {
        return EnvelopeCommitResult(
          EnvelopeCommitStatus.scopeMismatch,
          envelope: stored,
          admission: admission,
          reason: 'encoded envelope belongs to another scope',
        );
      }
      await temp.writeAsBytes(bytes, flush: true);
      final hook = beforeReplace;
      if (hook != null) await hook();
      await temp.rename(file.path);
    } on EnvelopeFormatException {
      await _discardTemp(temp);
      return EnvelopeCommitResult(
        EnvelopeCommitStatus.failed,
        envelope: stored,
        admission: admission,
        reason: 'encoded envelope did not round trip',
      );
    } on FileSystemException catch (error) {
      await _discardTemp(temp);
      return EnvelopeCommitResult(
        EnvelopeCommitStatus.failed,
        envelope: stored,
        admission: admission,
        reason: 'replacement failed with ${error.runtimeType}',
      );
    } catch (_) {
      // A non-storage error, such as a failing beforeReplace hook, keeps
      // propagating, but the temp file written above must still be removed.
      await _discardTemp(temp);
      rethrow;
    }
    return EnvelopeCommitResult(
      EnvelopeCommitStatus.committed,
      envelope: next,
      admission: admission,
    );
  }

  Future<void> _discardTemp(File temp) async {
    try {
      if (await temp.exists()) await temp.delete();
    } catch (_) {
      // The stored file is already untouched; a stale temp file is harmless.
      // Cleanup must never turn a typed result or an original error into its
      // own failure.
    }
  }
}

EnvelopeCommitStatus _statusForProjection(JournalProjectionCheck check) =>
    switch (check.status) {
      JournalProjectionStatus.projectionConflict =>
        EnvelopeCommitStatus.projectionConflict,
      JournalProjectionStatus.scopeMismatch =>
        EnvelopeCommitStatus.scopeMismatch,
      JournalProjectionStatus.valid ||
      JournalProjectionStatus.baselineInvalid ||
      JournalProjectionStatus.baselineMismatch ||
      JournalProjectionStatus.projectionMismatch =>
        EnvelopeCommitStatus.projectionMismatch,
    };

bool _sameNotebook(Notebook a, Notebook b) =>
    jsonEncode(a.toJson()) == jsonEncode(b.toJson());
