/// Single-file storage for experimental version 2 documents.
///
/// This adapter stores [EpochHistoryEnvelope] documents and nothing else. The
/// default version 1 path, `notebook.json`, the backup format, and the app are
/// untouched: no production code imports this file, and a store refuses
/// `notebook.json` as a target exactly as the version 1 store does.
///
/// Two writes, each with a closed input
/// ------------------------------------
/// An earlier revision of this adapter exposed a generic
/// `commit({base, next})`. That entry point accepted any replacement document,
/// so a fresh epoch, an extended ledger, and an emptied notebook could be
/// persisted in one call with no barrier check anywhere. Scope replacement was
/// therefore callable, not merely planned, and an ordinary write could drop
/// journal and notebook content under the same epoch. That entry point is gone,
/// and no replacement API takes its place. Neither write below takes a
/// document, a revision, a journal, or a ledger from the caller.
///
/// [create] builds the one permitted initial document for an absent target. It
/// requires revision 1, an empty notebook, an empty journal, and a ledger
/// holding exactly the epoch that journal runs under. It cannot express a
/// different notebook, a different epoch, or an extra ledger entry, so it
/// cannot mint, drop, or switch an epoch, and it cannot overwrite anything.
///
/// [reset] executes one restore or wipe. It takes the state the caller observed
/// and a validated fresh epoch, and it derives the replacement itself. Inside
/// the same per-path queue it reads the stored document, checks the notebook
/// binding, the observed revision, and the observed journal epoch, runs the
/// historical barrier policy on the stored document alone, and only then reads
/// the caller's backup snapshot. The replacement shares this file's single
/// atomic replace: one flushed temporary file, validated by decoding those
/// exact bytes, then one same-directory rename. The journal of the replacement
/// is always empty and always runs under the fresh epoch, and the ledger always
/// grows by exactly one entry, so a reset cannot mint two epochs, drop a
/// recorded epoch, keep an earlier epoch's operations, or reuse a revision.
///
/// A reset never creates a document. An absent target is reported as missing
/// and a legacy version 1 target as [EpochHistoryMissingException], so a reset
/// cannot bootstrap, upgrade, repair, or fabricate one.
///
/// External changes are never overwritten
/// --------------------------------------
/// Between the read and the rename another writer can change the target file.
/// Inside one isolate the path queue prevents that, but the queue is lexical
/// and cannot see a second isolate, a second process, or a path alias. So
/// before the rename the adapter re-reads the target and compares it with the
/// document it planned from; if anything changed, the temporary file is
/// discarded and the reset reports `stale` with the stored bytes untouched.
/// This narrows the lost-update window to the interval between that check and
/// the rename. It does not make the adapter exclusive, and it does not exclude
/// a second isolate, a second process, or a path alias.
///
/// Fail closed. A stored version 1 envelope is reported as
/// [EpochHistoryMissingException] rather than being upgraded or bootstrapped,
/// and a malformed, non-UTF-8, or history-inconsistent document is reported as
/// damage. In every failure case the stored bytes are left byte-identical.
///
/// Ownership limits are the version 1 store's: one writer at a time per
/// normalized path inside one isolate, no cross-process or cross-isolate
/// coordination, and a `flush` plus same-directory `rename` that survives a
/// process crash but is not a tested power-loss guarantee.
library;

import 'dart:convert';
import 'dart:io';

import 'epoch_history_envelope.dart';
import 'epoch_history_reset.dart';
import 'journal_values.dart';
import 'notebook_envelope.dart';

/// File name reserved for the app's notebook document.
const String _reservedNotebookFileName = 'notebook.json';

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

bool _targetsReservedNotebook(File file) {
  final segments = file.uri.pathSegments;
  for (var index = segments.length - 1; index >= 0; index--) {
    final segment = segments[index];
    if (segment.isEmpty || segment == '.') continue;
    return _asciiLowerCase(segment) == _reservedNotebookFileName;
  }
  return false;
}

/// Outcome of [EpochHistoryStore.create].
enum EpochHistoryWriteStatus {
  /// The target file was created. The only status that claims a durable change.
  committed,

  /// The target already exists. An existing document is never bootstrapped or
  /// replaced, so nothing was written.
  alreadyExists,

  /// The offered document is not a valid initial document. Nothing was
  /// written.
  notInitializable,

  /// The offered document belongs to another notebook. Nothing was written.
  scopeMismatch,

  /// Creating or reading the file failed. The stored bytes were left
  /// untouched, and this is never reported as [committed].
  failed,
}

class EpochHistoryWriteResult {
  const EpochHistoryWriteResult(this.status, {this.document, this.reason});

  final EpochHistoryWriteStatus status;

  /// The stored document after the call: the new document when
  /// [EpochHistoryWriteStatus.committed], otherwise `null` because nothing was
  /// stored.
  final EpochHistoryEnvelope? document;

  /// Short machine-readable explanation. Never contains diary text.
  final String? reason;

  bool get isCommitted => status == EpochHistoryWriteStatus.committed;
}

/// The stored document belongs to a different notebook than the store accepts.
class EpochHistoryScopeMismatch implements Exception {
  const EpochHistoryScopeMismatch(
    this.expectedNotebookId,
    this.actualNotebookId,
  );

  final String expectedNotebookId;
  final String actualNotebookId;

  @override
  String toString() =>
      'EpochHistoryScopeMismatch: expected $expectedNotebookId, '
      'stored $actualNotebookId';
}

/// The stored document is not a version 2 document, so it carries no provable
/// epoch history.
class EpochHistoryMissingException implements Exception {
  const EpochHistoryMissingException();

  @override
  String toString() =>
      'EpochHistoryMissingException: the stored document has no epoch history';
}

/// Normalized path -> tail of the write chain for that target.
final Map<String, Future<void>> _pathTails = {};

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

class EpochHistoryStore {
  /// [notebookId] is required: an unbound store could read or write a document
  /// belonging to another notebook, so every store is pinned to one notebook.
  EpochHistoryStore(this.file, {required this.notebookId, this.beforeReplace}) {
    requireOpaqueId(notebookId, field: 'notebookId');
    if (file.uri.pathSegments.isEmpty || _targetsReservedNotebook(file)) {
      // The app's notebook document is never a V2 target, on every platform
      // and whatever the ASCII case of the name.
      throw ArgumentError.value(
        file.path,
        'file',
        'refuses the app notebook document as an envelope target',
      );
    }
  }

  /// V2 document file. Its directory must already exist.
  final File file;

  /// The one notebook this store accepts.
  final String notebookId;

  /// Test seam that runs after the temporary file is written and validated but
  /// before it replaces [file]. Production callers leave it null.
  final Future<void> Function()? beforeReplace;

  int _tempCounter = 0;

  /// Reads the stored document, or `null` when the file does not exist.
  ///
  /// A version 1 document throws [EpochHistoryMissingException], a malformed
  /// document throws [EnvelopeFormatException], and a document for another
  /// notebook throws [EpochHistoryScopeMismatch]. None is repaired, migrated,
  /// upgraded, or overwritten.
  Future<EpochHistoryEnvelope?> read() async {
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const EnvelopeFormatException('envelope is not valid UTF-8');
    }
    final EpochHistoryEnvelope document;
    try {
      document = EpochHistoryEnvelope.decode(text);
    } on EnvelopeFormatException {
      // Fail closed, but report an existing V1 notebook as "no provable
      // history" rather than as damage. It is still never bootstrapped.
      if (_isLegacyEnvelope(text)) {
        throw const EpochHistoryMissingException();
      }
      rethrow;
    }
    if (document.history.notebookId != notebookId) {
      throw EpochHistoryScopeMismatch(notebookId, document.history.notebookId);
    }
    return document;
  }

  static bool _isLegacyEnvelope(String text) {
    try {
      NotebookEnvelope.decode(text);
      return true;
    } on EnvelopeFormatException {
      return false;
    }
  }

  /// Creates the first document for an absent target.
  ///
  /// [document] must be an initial document: revision 1, an empty notebook, an
  /// empty journal, and a ledger holding exactly the one epoch that journal
  /// runs under. Anything else is refused as
  /// [EpochHistoryWriteStatus.notInitializable], and an existing target is
  /// refused as [EpochHistoryWriteStatus.alreadyExists]. Neither case writes.
  Future<EpochHistoryWriteResult> create(EpochHistoryEnvelope document) {
    final key = _lockKey(file);
    final tail = _pathTails[key] ?? Future<void>.value();
    final result = tail.then((_) => _create(document));
    final chain = result.then((_) {}, onError: (_) {});
    _pathTails[key] = chain;
    chain.whenComplete(() {
      if (identical(_pathTails[key], chain)) _pathTails.remove(key);
    });
    return result;
  }

  Future<EpochHistoryWriteResult> _create(EpochHistoryEnvelope document) async {
    if (await file.exists()) {
      return const EpochHistoryWriteResult(
        EpochHistoryWriteStatus.alreadyExists,
        reason: 'an existing document is never bootstrapped or replaced',
      );
    }
    if (document.history.notebookId != notebookId) {
      return const EpochHistoryWriteResult(
        EpochHistoryWriteStatus.scopeMismatch,
        reason: 'document belongs to another notebook',
      );
    }
    if (!_isInitialDocument(document)) {
      return const EpochHistoryWriteResult(
        EpochHistoryWriteStatus.notInitializable,
        reason: 'only an initial document can create a stored document',
      );
    }
    return _replace(document);
  }

  static bool _isInitialDocument(EpochHistoryEnvelope document) =>
      document.envelope.revision == 1 &&
      document.envelope.journal.isEmpty &&
      document.history.length == 1 &&
      document.envelope.journal.epochId == document.history.latest &&
      document.envelope.notebook.entries.isEmpty &&
      document.envelope.notebook.archives.isEmpty;

  /// Executes one restore or wipe against the stored document.
  ///
  /// The queue is the same per-path queue [create] uses, so a create and a
  /// reset cannot interleave a read-check-write on one target. Inside it, and
  /// before the caller's backup snapshot is read at all, this method re-reads
  /// the stored document, checks the notebook binding, the observed revision,
  /// and the observed journal epoch, and runs the historical barrier policy on
  /// the stored document alone. The payload is canonicalized only after every
  /// other check has passed; see `planEpochReset`.
  ///
  /// An absent target is [EpochResetStatus.missing] and a version 1 target is
  /// [EpochResetStatus.legacyDocument]. Neither is created, upgraded, or
  /// repaired.
  Future<EpochResetOutcome> reset({
    required EpochResetExpectation expected,
    required JournalResetEpoch epoch,
    required JournalResetPayload payload,
  }) {
    final key = _lockKey(file);
    final tail = _pathTails[key] ?? Future<void>.value();
    final result = tail.then(
      (_) => _reset(expected: expected, epoch: epoch, payload: payload),
    );
    final chain = result.then((_) {}, onError: (_) {});
    _pathTails[key] = chain;
    chain.whenComplete(() {
      if (identical(_pathTails[key], chain)) _pathTails.remove(key);
    });
    return result;
  }

  Future<EpochResetOutcome> _reset({
    required EpochResetExpectation expected,
    required JournalResetEpoch epoch,
    required JournalResetPayload payload,
  }) async {
    final action = epochResetActionFor(payload);

    EpochHistoryEnvelope? stored;
    try {
      stored = await read();
    } on EpochHistoryMissingException {
      return EpochResetOutcome.notApplied(
        action: action,
        status: EpochResetStatus.legacyDocument,
        reason: 'the stored document has no epoch history',
      );
    } on EnvelopeFormatException {
      return EpochResetOutcome.notApplied(
        action: action,
        status: EpochResetStatus.failed,
        reason: 'stored document cannot be read',
      );
    } on EpochHistoryScopeMismatch {
      return EpochResetOutcome.notApplied(
        action: action,
        status: EpochResetStatus.scopeMismatch,
        reason: 'stored document belongs to another notebook',
      );
    } on FileSystemException {
      return EpochResetOutcome.notApplied(
        action: action,
        status: EpochResetStatus.failed,
        reason: 'stored document cannot be read',
      );
    }
    if (stored == null) {
      return EpochResetOutcome.notApplied(
        action: action,
        status: EpochResetStatus.missing,
        reason: 'no stored document to reset',
      );
    }

    final plan = planEpochReset(
      notebookId: notebookId,
      stored: stored,
      expected: expected,
      epoch: epoch,
      payload: payload,
    );
    if (!plan.isAllowed) return plan;

    final next = plan.document!;
    final attempt = await _atomicReplace(next, expectedStored: stored);
    if (attempt.status == _ReplaceStatus.externalChange) {
      final observed = attempt.observed;
      return EpochResetOutcome.notApplied(
        action: action,
        status: EpochResetStatus.stale,
        revision: observed?.envelope.revision ?? stored.envelope.revision,
        epochId:
            observed?.envelope.journal.epochId ??
            stored.envelope.journal.epochId,
        reason: 'the stored document changed after it was observed',
      );
    }
    if (attempt.status != _ReplaceStatus.written) {
      return EpochResetOutcome.notApplied(
        action: action,
        status: EpochResetStatus.failed,
        revision: stored.envelope.revision,
        epochId: stored.envelope.journal.epochId,
        reason: attempt.status == _ReplaceStatus.storageFailed
            ? 'reset failed with ${attempt.errorType}'
            : attempt.reason,
      );
    }
    return EpochResetOutcome.applied(
      action: action,
      status: EpochResetStatus.committed,
      revision: next.envelope.revision,
      epochId: next.envelope.journal.epochId,
      document: next,
      barrier: plan.barrier,
    );
  }

  Future<EpochHistoryWriteResult> _replace(EpochHistoryEnvelope next) async {
    final attempt = await _atomicReplace(next);
    if (attempt.status == _ReplaceStatus.written) {
      return EpochHistoryWriteResult(
        EpochHistoryWriteStatus.committed,
        document: next,
      );
    }
    return EpochHistoryWriteResult(
      EpochHistoryWriteStatus.failed,
      reason: attempt.status == _ReplaceStatus.storageFailed
          ? 'creation failed with ${attempt.errorType}'
          : attempt.reason,
    );
  }

  /// The one atomic replace: encode, verify those exact bytes, write a unique
  /// flushed temporary file, run the test hook, optionally re-check the target,
  /// then rename.
  ///
  /// [expectedStored] is supplied only by [reset]. When it is present, the
  /// target is re-read after the hook and compared with the document the reset
  /// was planned from. A changed, removed, or unreadable target discards the
  /// temporary file and reports an external change, so a reset never overwrites
  /// a write it did not plan from. [create] passes null and keeps its published
  /// behaviour: no re-read, and the same statuses and reason strings as before.
  Future<_ReplaceAttempt> _atomicReplace(
    EpochHistoryEnvelope next, {
    EpochHistoryEnvelope? expectedStored,
  }) async {
    final bytes = utf8.encode(next.encode());
    final temp = File(
      '${file.path}.$pid-${_tempCounter++}-'
      '${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      // The exact bytes about to be renamed must decode back to the intended
      // document before the target is touched.
      final verified = EpochHistoryEnvelope.decode(utf8.decode(bytes));
      if (!verified.hasSameContentAs(next) ||
          verified.history.notebookId != notebookId) {
        return const _ReplaceAttempt(
          _ReplaceStatus.notRoundTripped,
          reason: 'encoded document did not round trip',
        );
      }
      await temp.writeAsBytes(bytes, flush: true);
      final hook = beforeReplace;
      if (hook != null) await hook();
      if (expectedStored != null) {
        final current = await _readForGuard();
        if (current == null || !current.hasSameContentAs(expectedStored)) {
          await _discardTemp(temp);
          return _ReplaceAttempt(
            _ReplaceStatus.externalChange,
            observed: current,
            reason: 'the stored document changed after it was observed',
          );
        }
      }
      await temp.rename(file.path);
    } on EnvelopeFormatException {
      await _discardTemp(temp);
      return const _ReplaceAttempt(
        _ReplaceStatus.notRoundTripped,
        reason: 'encoded document did not round trip',
      );
    } on FileSystemException catch (error) {
      await _discardTemp(temp);
      return _ReplaceAttempt(
        _ReplaceStatus.storageFailed,
        errorType: error.runtimeType.toString(),
      );
    } catch (_) {
      // A non-storage error, such as a failing beforeReplace hook, keeps
      // propagating, but the temp file written above must still be removed.
      await _discardTemp(temp);
      rethrow;
    }
    return const _ReplaceAttempt(_ReplaceStatus.written);
  }

  /// Reads the target for the pre-rename re-check, treating an unreadable or
  /// out-of-scope document as an external change rather than as damage.
  Future<EpochHistoryEnvelope?> _readForGuard() async {
    try {
      if (!await file.exists()) return null;
      return await read();
    } on EnvelopeFormatException {
      return null;
    } on EpochHistoryMissingException {
      return null;
    } on EpochHistoryScopeMismatch {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _discardTemp(File temp) async {
    try {
      if (await temp.exists()) await temp.delete();
    } catch (_) {
      // The target is already untouched; a stale temp file is harmless.
      // Cleanup must never turn a typed result or an original error into its
      // own failure.
    }
  }
}

/// Outcome of the shared atomic replace, before it is mapped to a public type.
enum _ReplaceStatus {
  /// The target now holds the new document.
  written,

  /// The exact bytes did not decode back to the intended document.
  notRoundTripped,

  /// Writing, validating, or renaming failed.
  storageFailed,

  /// The target changed between the read the caller planned from and the
  /// rename. Only a guarded replace reports this.
  externalChange,
}

final class _ReplaceAttempt {
  const _ReplaceAttempt(
    this.status, {
    this.reason,
    this.errorType,
    this.observed,
  });

  final _ReplaceStatus status;

  /// Short static explanation for a non-storage failure. Never contains diary
  /// text or file content.
  final String? reason;

  /// Runtime type name of the storage error, so each caller can keep its
  /// published wording.
  final String? errorType;

  /// The document the guard found instead of the expected one, when it could
  /// be read.
  final EpochHistoryEnvelope? observed;
}
