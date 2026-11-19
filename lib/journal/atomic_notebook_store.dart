/// Single-file storage for [NotebookEnvelope] documents.
///
/// Scope and ownership
/// -------------------
/// One [AtomicNotebookStore] instance owns one envelope file. Commits on the
/// same instance are serialized, so two overlapping calls cannot interleave a
/// read-check-write. This is an in-process, single-writer contract only:
///
/// * Nothing here coordinates a second process, a second isolate, or a second
///   instance pointed at the same path. Two writers can still lose updates.
/// * Durability is limited to `writeAsBytes(flush: true)` followed by
///   `rename` in the same directory. That ordering survives a process crash,
///   but it is not a tested power-loss guarantee, and no `fsync` of the
///   directory is performed.
///
/// This adapter is experimental and is not wired into the app. `notebook.json`
/// keeps its own format and its own writer.
library;

import 'dart:convert';
import 'dart:io';

import '../notebook.dart';
import 'journal.dart';
import 'journal_operation.dart';
import 'notebook_envelope.dart';

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

  /// Validation or the file replacement failed. The stored bytes were left
  /// untouched. Never reported as [committed].
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

class AtomicNotebookStore {
  AtomicNotebookStore(this.file, {required this.scope, this.beforeReplace});

  /// Envelope file. Its directory must already exist.
  final File file;

  /// Notebook and epoch this store accepts. Every read and commit is checked
  /// against it.
  final JournalScope scope;

  /// Test seam that runs after the temporary file is written and validated but
  /// before it replaces [file]. Production callers leave it null.
  final Future<void> Function()? beforeReplace;

  Future<void> _tail = Future.value();

  /// Reads the stored envelope, or `null` when the file does not exist.
  ///
  /// A malformed, unsupported, or out-of-scope document throws instead of
  /// being repaired, migrated, or overwritten.
  Future<NotebookEnvelope?> read() async {
    if (!await file.exists()) return null;
    final text = await file.readAsString();
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
  /// snapshot that already includes the operation's effect. This adapter does
  /// not and cannot verify that correspondence: the notebook model carries no
  /// notebook, epoch, or entry-operation identity, so the pairing is asserted
  /// by the caller. That gap must be closed by replay (M3.3) before this is
  /// hooked up to the app.
  Future<EnvelopeCommitResult> commit({
    required NotebookEnvelope base,
    required Notebook notebook,
    required JournalOperation operation,
  }) {
    final result = _tail.then(
      (_) => _commit(base: base, notebook: notebook, operation: operation),
    );
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<EnvelopeCommitResult> _commit({
    required NotebookEnvelope base,
    required Notebook notebook,
    required JournalOperation operation,
  }) async {
    final stored = await read();
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
          _sameNotebook(stored.notebook, notebook)
              ? EnvelopeCommitStatus.noChange
              : EnvelopeCommitStatus.duplicate,
          envelope: stored,
          admission: admission,
          reason: 'operation is already stored',
        );
      case JournalAdmission.appended:
        break;
    }

    if (_sameNotebook(stored.notebook, notebook)) {
      // The journal changed but the snapshot did not. Persisting that would
      // record an operation whose effect is not in the notebook, so refuse.
      return EnvelopeCommitResult(
        EnvelopeCommitStatus.inconsistent,
        envelope: stored,
        admission: admission,
        reason: 'notebook snapshot does not reflect the appended operation',
      );
    }

    final next = NotebookEnvelope(
      revision: base.revision + 1,
      notebook: notebook,
      journal: journal,
    );
    return _replace(stored, next, admission);
  }

  Future<EnvelopeCommitResult> _replace(
    NotebookEnvelope stored,
    NotebookEnvelope next,
    JournalAdmissionResult admission,
  ) async {
    final bytes = utf8.encode(next.encode());
    final temp = File('${file.path}.tmp');
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
    } catch (error) {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        // The stored file is already untouched; a stale temp file is harmless.
      }
      return EnvelopeCommitResult(
        EnvelopeCommitStatus.failed,
        envelope: stored,
        admission: admission,
        reason: 'replacement failed with ${error.runtimeType}',
      );
    }
    return EnvelopeCommitResult(
      EnvelopeCommitStatus.committed,
      envelope: next,
      admission: admission,
    );
  }
}

bool _sameNotebook(Notebook a, Notebook b) =>
    jsonEncode(a.toJson()) == jsonEncode(b.toJson());
