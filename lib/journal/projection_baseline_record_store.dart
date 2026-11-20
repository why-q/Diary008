/// Create-only file adapter for experimental pre-journal baseline records.
///
/// Experimental and unshipped. No production code imports this file, nothing in
/// the app reads or writes it, and it is not a notebook format. The app's
/// `notebook.json`, its writer, the envelope store, and the epoch-ledger store
/// are untouched, and this adapter is not a second mutable notebook: it stores
/// one record and offers no update, replace, or delete operation at all.
///
/// Why create-only
/// ---------------
/// A baseline is only evidence if it predates the first journal operation. A
/// replacement API would let a caller overwrite a baseline after the journal
/// grew, which is exactly the fact the baseline is supposed to establish. So
/// the only write is [ProjectionBaselineRecordStore.create], and it refuses to
/// touch an occupied destination.
///
/// Two paths, and they must differ
/// -------------------------------
/// The store is given both the record path and the intended envelope path. The
/// record must not be the envelope: a baseline is not an envelope, and letting
/// the two coincide would mean the first envelope commit replaced the baseline.
/// Lexically equal paths, including `.`/`..` spellings, are refused at
/// construction.
///
/// Backfill is refused
/// -------------------
/// If *any* filesystem entity already occupies the envelope path, `create`
/// refuses with [ProjectionBaselineWriteStatus.envelopeOccupied] and writes
/// nothing. That is the guard against inventing a "pre-journal" baseline after
/// an envelope already exists: the adapter cannot verify that an existing
/// envelope's history began from this snapshot, so it does not pretend to.
/// Directories, regular files, and symlinks all count, because the check does
/// not follow links.
///
/// Fail closed
/// -----------
/// A reserved destination (`notebook.json` in any ASCII case) is refused at
/// construction. A destination that already holds bytes which are not a valid
/// record is reported as [ProjectionBaselineWriteStatus.corruptDestination] and
/// is left byte-identical. [read] throws on a malformed, non-UTF-8, or
/// out-of-scope record instead of repairing it. Nothing is migrated or
/// upgraded.
///
/// What is not claimed
/// -------------------
/// * Ownership is the envelope store's: one writer at a time per lexically
///   normalized absolute path inside one isolate. Two stores whose paths
///   normalize to the same key are serialized, and the loser sees
///   [ProjectionBaselineWriteStatus.alreadyExists] rather than overwriting. A
///   second isolate, a second process, and path aliases a lexical normalization
///   cannot see (symlinks, hard links, case-insensitive file systems, bind
///   mounts) are not coordinated.
/// * Durability is `writeAsBytes(flush: true)` plus a same-directory `rename`.
///   That survives a process crash; it is not a tested power-loss guarantee,
///   and the directory is not fsynced.
/// * Nothing here detects an external writer that swaps in a different but
///   internally coherent record, or a rollback to an earlier coherent pair. The
///   record is not signed, chained, or anchored, and no tamper resistance is
///   claimed.
library;

import 'dart:convert';
import 'dart:io';

import 'journal_values.dart';
import 'notebook_envelope.dart';
import 'projection_baseline_record.dart';

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

/// Outcome of [ProjectionBaselineRecordStore.create].
enum ProjectionBaselineWriteStatus {
  /// The record file was created. The only status that claims a durable change.
  created,

  /// A record already occupies the destination. Nothing was written. Compare
  /// [ProjectionBaselineWriteResult.matchesOffered] to tell a retry of the same
  /// baseline from a different baseline that was recorded earlier.
  alreadyExists,

  /// The destination holds bytes that are not a valid record, or is not a
  /// readable regular file. Nothing was written and the bytes are unchanged.
  corruptDestination,

  /// Something already occupies the intended envelope path, so a pre-journal
  /// baseline can no longer be established. Nothing was written.
  envelopeOccupied,

  /// The offered record belongs to another notebook or epoch. Nothing was
  /// written.
  scopeMismatch,

  /// Writing, validating, or renaming failed. The stored bytes were left
  /// untouched. Never reported as [created].
  failed,
}

class ProjectionBaselineWriteResult {
  const ProjectionBaselineWriteResult(
    this.status, {
    this.record,
    this.reason,
    this.matchesOffered,
  });

  final ProjectionBaselineWriteStatus status;

  /// The stored record when [ProjectionBaselineWriteStatus.created] or
  /// [ProjectionBaselineWriteStatus.alreadyExists], otherwise `null`.
  final ProjectionBaselineRecord? record;

  /// Short machine-readable explanation. Never contains diary text.
  final String? reason;

  /// Whether an already stored record has the same content as the offered one.
  /// Only meaningful for [ProjectionBaselineWriteStatus.alreadyExists].
  final bool? matchesOffered;

  bool get isCreated => status == ProjectionBaselineWriteStatus.created;
}

/// The stored record belongs to a different notebook or epoch than the store.
class ProjectionBaselineScopeMismatch implements Exception {
  const ProjectionBaselineScopeMismatch(this.expected, this.actual);

  final JournalScope expected;
  final JournalScope actual;

  @override
  String toString() =>
      'ProjectionBaselineScopeMismatch: expected $expected, stored $actual';
}

/// Normalized path -> tail of the write chain for that destination.
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

class ProjectionBaselineRecordStore {
  /// [notebookId] and [epochId] are required: a store is pinned to exactly one
  /// notebook epoch, so it can neither read nor create a baseline for another.
  ///
  /// [envelopeFile] is the envelope this baseline is meant to seed. It is
  /// required, and it must differ from the record path. Both paths must be
  /// usable, and neither may name the app notebook document.
  ProjectionBaselineRecordStore(
    this.file, {
    required this.notebookId,
    required this.epochId,
    required this.envelopeFile,
    this.beforeReplace,
  }) {
    requireOpaqueId(notebookId, field: 'notebookId');
    requireOpaqueId(epochId, field: 'epochId');
    if (file.uri.pathSegments.isEmpty) {
      throw ArgumentError.value(
        file.path,
        'file',
        'refuses an empty baseline record path',
      );
    }
    if (envelopeFile.uri.pathSegments.isEmpty) {
      throw ArgumentError.value(
        envelopeFile.path,
        'envelopeFile',
        'refuses an empty envelope path',
      );
    }
    if (_lockKey(file) == _lockKey(envelopeFile)) {
      // A baseline must not be the envelope: the first envelope commit would
      // otherwise replace the baseline it was validated against.
      throw ArgumentError.value(
        envelopeFile.path,
        'envelopeFile',
        'the baseline record path and the envelope path must differ',
      );
    }
    if (_targetsReservedNotebook(file) ||
        _targetsReservedNotebook(envelopeFile)) {
      // The app's notebook document is never a baseline record and never an
      // envelope, on every platform, whatever the ASCII case of the name.
      throw ArgumentError.value(
        file.path,
        'file',
        'refuses the app notebook document',
      );
    }
  }

  /// Baseline record file. Its directory must already exist.
  final File file;

  /// The one notebook this store accepts.
  final String notebookId;

  /// The one epoch this store accepts.
  final String epochId;

  /// The envelope this baseline seeds. It is only inspected, never written,
  /// and never created by this adapter.
  final File envelopeFile;

  /// Test seam that runs after the temporary file is written and validated but
  /// before it replaces [file]. Production callers leave it null.
  final Future<void> Function()? beforeReplace;

  /// The scope this store is pinned to.
  JournalScope get scope =>
      JournalScope(notebookId: notebookId, epochId: epochId);

  int _tempCounter = 0;

  /// Reads the stored record, or `null` when the destination is absent.
  ///
  /// A malformed or non-UTF-8 destination throws [EnvelopeFormatException], a
  /// destination that cannot be read throws [FileSystemException], and a valid
  /// record for another notebook or epoch throws
  /// [ProjectionBaselineScopeMismatch]. None is repaired, migrated, or
  /// overwritten.
  Future<ProjectionBaselineRecord?> read() async {
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const EnvelopeFormatException('baseline record is not valid UTF-8');
    }
    final record = ProjectionBaselineRecord.decode(text);
    if (record.scope != scope) {
      throw ProjectionBaselineScopeMismatch(scope, record.scope);
    }
    return record;
  }

  /// Creates the baseline record for an absent destination.
  ///
  /// Refused, with nothing written, when the intended envelope path is occupied
  /// by any filesystem entity, when the destination is already occupied, and
  /// when [record] belongs to another notebook or epoch.
  Future<ProjectionBaselineWriteResult> create(
    ProjectionBaselineRecord record,
  ) {
    final key = _lockKey(file);
    final tail = _pathTails[key] ?? Future<void>.value();
    final result = tail.then((_) => _create(record));
    final chain = result.then((_) {}, onError: (_) {});
    _pathTails[key] = chain;
    chain.whenComplete(() {
      if (identical(_pathTails[key], chain)) _pathTails.remove(key);
    });
    return result;
  }

  Future<ProjectionBaselineWriteResult> _create(
    ProjectionBaselineRecord record,
  ) async {
    if (record.scope != scope) {
      return const ProjectionBaselineWriteResult(
        ProjectionBaselineWriteStatus.scopeMismatch,
        reason: 'record belongs to another notebook or epoch',
      );
    }

    ProjectionBaselineWriteResult? refusal;
    try {
      refusal = await _refusalForExistingEntities(record);
    } on FileSystemException catch (error) {
      return ProjectionBaselineWriteResult(
        ProjectionBaselineWriteStatus.failed,
        reason: 'destination could not be inspected: ${error.runtimeType}',
      );
    }
    if (refusal != null) return refusal;

    return _replace(record);
  }

  /// Checks the envelope path first, then the destination, without writing.
  Future<ProjectionBaselineWriteResult?> _refusalForExistingEntities(
    ProjectionBaselineRecord record,
  ) async {
    // `followLinks: false` so a dangling symlink still counts as an occupant.
    final envelopeType = await FileSystemEntity.type(
      envelopeFile.path,
      followLinks: false,
    );
    if (envelopeType != FileSystemEntityType.notFound) {
      // A baseline recorded now cannot predate an envelope that already exists,
      // and this adapter cannot verify an existing envelope's history.
      return const ProjectionBaselineWriteResult(
        ProjectionBaselineWriteStatus.envelopeOccupied,
        reason: 'an entity already occupies the intended envelope path',
      );
    }

    final destinationType = await FileSystemEntity.type(
      file.path,
      followLinks: false,
    );
    if (destinationType == FileSystemEntityType.notFound) return null;
    if (destinationType != FileSystemEntityType.file) {
      return const ProjectionBaselineWriteResult(
        ProjectionBaselineWriteStatus.corruptDestination,
        reason: 'the destination is not a regular file',
      );
    }
    return _existingDestinationResult(record);
  }

  /// Reads an existing destination and reports it as a retry or a refusal.
  Future<ProjectionBaselineWriteResult> _existingDestinationResult(
    ProjectionBaselineRecord record,
  ) async {
    ProjectionBaselineRecord? stored;
    try {
      stored = await read();
    } on EnvelopeFormatException {
      // Damage is reported, never repaired or replaced.
      return const ProjectionBaselineWriteResult(
        ProjectionBaselineWriteStatus.corruptDestination,
        reason: 'the destination does not hold a valid baseline record',
      );
    } on ProjectionBaselineScopeMismatch {
      return const ProjectionBaselineWriteResult(
        ProjectionBaselineWriteStatus.scopeMismatch,
        reason: 'the stored record belongs to another notebook or epoch',
      );
    }
    if (stored == null) {
      // Deleted between the type probe and the read; treat as a failed attempt
      // rather than silently writing over a destination that changed.
      return const ProjectionBaselineWriteResult(
        ProjectionBaselineWriteStatus.failed,
        reason: 'the destination changed while it was inspected',
      );
    }
    return ProjectionBaselineWriteResult(
      ProjectionBaselineWriteStatus.alreadyExists,
      record: stored,
      reason: 'an existing baseline record is never replaced',
      matchesOffered: stored.hasSameContentAs(record),
    );
  }

  Future<ProjectionBaselineWriteResult> _replace(
    ProjectionBaselineRecord record,
  ) async {
    final bytes = utf8.encode(record.encode());
    // A unique name per attempt: a crashed attempt's temp file is never reused
    // and two attempts never share one temporary file.
    final temp = File(
      '${file.path}.$pid-${_tempCounter++}-'
      '${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      // The exact bytes about to be renamed must decode back to the intended
      // record before the destination is touched.
      final verified = ProjectionBaselineRecord.decode(utf8.decode(bytes));
      if (!verified.hasSameContentAs(record) || verified.scope != scope) {
        return const ProjectionBaselineWriteResult(
          ProjectionBaselineWriteStatus.failed,
          reason: 'encoded record did not round trip',
        );
      }
      await temp.writeAsBytes(bytes, flush: true);
      final hook = beforeReplace;
      if (hook != null) await hook();
      // A rename would replace a destination that appeared after the checks
      // above, so the destination is re-probed immediately before the rename.
      // An interrupted attempt or a late contender is refused instead of
      // overwritten. Nothing here makes the rename conditional, so a same-inode
      // alias a lexical path cannot see is still out of scope.
      final destinationType = await FileSystemEntity.type(
        file.path,
        followLinks: false,
      );
      if (destinationType != FileSystemEntityType.notFound) {
        final existing = destinationType == FileSystemEntityType.file
            ? await _existingDestinationResult(record)
            : const ProjectionBaselineWriteResult(
                ProjectionBaselineWriteStatus.corruptDestination,
                reason: 'the destination is not a regular file',
              );
        await _discardTemp(temp);
        return existing;
      }
      await temp.rename(file.path);
    } on EnvelopeFormatException {
      await _discardTemp(temp);
      return const ProjectionBaselineWriteResult(
        ProjectionBaselineWriteStatus.failed,
        reason: 'encoded record did not round trip',
      );
    } on FileSystemException catch (error) {
      await _discardTemp(temp);
      return ProjectionBaselineWriteResult(
        ProjectionBaselineWriteStatus.failed,
        reason: 'creation failed with ${error.runtimeType}',
      );
    } catch (_) {
      // A non-storage error, such as a failing beforeReplace hook, keeps
      // propagating, but the temp file written above must still be removed.
      await _discardTemp(temp);
      rethrow;
    }
    return ProjectionBaselineWriteResult(
      ProjectionBaselineWriteStatus.created,
      record: record,
    );
  }

  Future<void> _discardTemp(File temp) async {
    try {
      if (await temp.exists()) await temp.delete();
    } catch (_) {
      // The destination is already untouched; a stale temp file is harmless.
      // Cleanup must never turn a typed result or an original error into its
      // own failure.
    }
  }
}
