/// One designated single writer for one envelope file, reached only through a
/// capability.
///
/// Why this exists
/// ---------------
/// `AtomicNotebookStore` serializes commits per normalized path inside one
/// isolate. That lock is a library-level map, so it cannot reach a second
/// isolate: two isolates pointed at one file can still read the same revision
/// and overwrite each other. `fcntl` locks are not the fix on Dart 3.13.5. They
/// are per-process, so they do not serialize two isolates or two
/// `FlutterEngine`s in one process, and a sibling lock file does not cover
/// aliases such as symlinks, hard links, or case-insensitive paths.
///
/// This module is the smaller alternative. One owner object is the only thing
/// that ever touches the file, and callers reach it through a
/// [NotebookWriterCapability] that carries nothing but the owner's request
/// port. Every request is decoded, validated, and completed before the next one
/// starts, so two clients cannot interleave a read-check-write even though they
/// run in different isolates.
///
/// What is claimed, exactly
/// ------------------------
/// * A capability names exactly one owner. Its constructor is library-private,
///   so a caller cannot mint a capability that points at a different writer.
/// * A request sent through a capability is serialized against every other
///   request to that same owner, in arrival order.
/// * A client cannot supply a notebook snapshot. It supplies one operation and
///   the revision it observed. The owner derives the snapshot by replaying its
///   own journal onto its own baseline, and the store re-verifies that
///   derivation before it writes.
/// * A client cannot reach storage. The request type set is closed and storage
///   objects never leave the owner, so the boundary cannot be used to write
///   arbitrary bytes or a second file.
///
/// What is not claimed
/// -------------------
/// * Uniqueness across independently constructed owners. [NotebookWriterOwner.open]
///   is not exclusive: two owners opened on one file are two writers. Two
///   owners inside one isolate are still serialized by the store's path lock.
///   Two owners in different isolates are not, and can still lose an update.
///   This module narrows *who* a capability can reach, not how many owners can
///   exist.
/// * Liveness. A client that outlives its owner gets no shutdown signal; it
///   learns the owner is gone only when its request times out.
/// * Durability beyond the store's `flush` plus same-directory rename.
///
/// This is an experiment. Nothing in production imports it, it is not wired
/// into the app, it never reads or writes `notebook.json`, and it has no
/// bootstrap, reset, or migration path. A missing target is reported as
/// [NotebookWriterOutcome.missing] rather than created.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../notebook.dart';
import 'atomic_notebook_store.dart';
import 'journal.dart';
import 'journal_operation.dart';
import 'journal_projection_gate.dart';
import 'journal_replay.dart';
import 'journal_values.dart';
import 'notebook_envelope.dart';

/// Outcome of one commit submitted through a [NotebookWriterCapability].
///
/// The names mirror [EnvelopeCommitStatus] one for one, plus
/// [missing] for an absent target, which the store would report as `stale`.
enum NotebookWriterOutcome {
  /// The owner replaced the stored envelope. The only outcome that claims a
  /// durable change.
  committed,

  /// The caller's base revision is not the stored revision. Nothing was
  /// written, and the reply carries the revision to retry on.
  stale,

  /// No stored envelope exists. Nothing was written, and the owner does not
  /// bootstrap one.
  missing,

  /// Admission refused the operation. Nothing was written.
  conflict,

  /// The operation was already stored and the notebook already reflects it.
  duplicate,

  /// The operation was already stored and nothing changed.
  noChange,

  /// The operation was admitted but the derived snapshot would not differ from
  /// the stored one. Nothing was written.
  inconsistent,

  /// The operation or document belongs to another notebook or epoch. Nothing
  /// was written.
  scopeMismatch,

  /// The derived snapshot is not the journal's projection. Nothing was
  /// written.
  projectionMismatch,

  /// The journal cannot be projected without an unresolved conflict. Nothing
  /// was written.
  projectionConflict,

  /// Reading or replacing the file failed. The stored bytes were left
  /// untouched.
  failed,
}

/// One commit reply: the outcome plus the revision the client should retry on.
///
/// Replies never carry entry text. [revision] and [journalLength] are enough to
/// rebase, and they keep diary content out of the message boundary and out of
/// any diagnostics derived from it.
final class NotebookWriterReply {
  const NotebookWriterReply({
    required this.outcome,
    required this.revision,
    required this.journalLength,
  });

  final NotebookWriterOutcome outcome;

  /// The stored revision after the call, or 0 when nothing is stored.
  final int revision;

  /// The stored journal length after the call, or 0 when nothing is stored.
  final int journalLength;

  bool get isCommitted => outcome == NotebookWriterOutcome.committed;

  @override
  String toString() =>
      'NotebookWriterReply(${outcome.name}, revision: $revision, '
      'journalLength: $journalLength)';
}

/// One read reply: the current revision and journal length, and no content.
final class NotebookWriterSnapshot {
  const NotebookWriterSnapshot({
    required this.revision,
    required this.journalLength,
  });

  final int revision;
  final int journalLength;

  bool get isEmpty => revision == 0;

  @override
  String toString() =>
      'NotebookWriterSnapshot(revision: $revision, '
      'journalLength: $journalLength)';
}

/// A handle to exactly one writer owner.
///
/// The constructor is library-private, so only [NotebookWriterOwner] can issue
/// a capability. Holding one lets a caller submit operations and read the
/// revision; it does not expose storage, and it cannot be pointed at another
/// owner.
final class NotebookWriterCapability {
  NotebookWriterCapability._(this._requests, this.ownerId);

  final SendPort _requests;

  /// Stable identifier of the owner that issued this capability. Diagnostics
  /// only; it carries no authority.
  final String ownerId;

  @override
  String toString() => 'NotebookWriterCapability($ownerId)';
}

/// A caller-side handle that speaks the owner's message protocol.
///
/// One instance may be used from one isolate. Several clients, in the same or
/// in different isolates, may share one capability; the owner serializes them.
final class NotebookWriterClient {
  NotebookWriterClient(
    this.capability, {
    this.requestTimeout = const Duration(seconds: 30),
  });

  final NotebookWriterCapability capability;

  /// How long to wait for a reply before reporting the owner as unreachable.
  /// A disposed owner has no shutdown signal, so this is the only way a client
  /// learns that its writer is gone.
  final Duration requestTimeout;

  /// Reads the current revision without writing anything.
  Future<NotebookWriterSnapshot> read() async {
    final message = await _exchange(const {'type': 'read'});
    if (message['type'] != 'snapshot') {
      throw const NotebookWriterProtocolException('unexpected read reply');
    }
    return NotebookWriterSnapshot(
      revision: _requireInt(message, 'revision'),
      journalLength: _requireInt(message, 'journalLength'),
    );
  }

  /// Submits [operation] as the next revision of [baseRevision].
  ///
  /// Only the operation and the observed revision cross the boundary. The owner
  /// derives the notebook snapshot itself, so a caller cannot describe an
  /// effect the journal does not contain.
  Future<NotebookWriterReply> commit({
    required int baseRevision,
    required JournalOperation operation,
  }) async {
    if (baseRevision < 1) {
      throw ArgumentError.value(
        baseRevision,
        'baseRevision',
        'must be the revision that was read, at least 1',
      );
    }
    final message = await _exchange({
      'type': 'commit',
      'baseRevision': baseRevision,
      'operation': operation.toJson(),
    });
    if (message['type'] != 'reply') {
      throw const NotebookWriterProtocolException('unexpected commit reply');
    }
    final name = message['outcome'];
    if (name is! String) {
      throw const NotebookWriterProtocolException('missing commit outcome');
    }
    final outcome = _outcomes[name];
    if (outcome == null) {
      throw const NotebookWriterProtocolException('unknown commit outcome');
    }
    return NotebookWriterReply(
      outcome: outcome,
      revision: _requireInt(message, 'revision'),
      journalLength: _requireInt(message, 'journalLength'),
    );
  }

  /// Sends [frame] unchanged, adding only the reply port, and returns the raw
  /// reply map.
  ///
  /// Exists so tests can drive the owner's request validation with frames the
  /// typed client would never build, and can inspect the exact reply shape. It
  /// is not a bypass: the frame enters the same serialized queue and is
  /// validated exactly like any other request, so a malformed frame is refused
  /// and the owner stays usable.
  Future<Map<Object?, Object?>> debugRequest(Map<String, Object?> frame) =>
      _exchange(frame, raw: true);

  Future<Map<Object?, Object?>> _exchange(
    Map<String, Object?> frame, {
    bool raw = false,
  }) async {
    final port = ReceivePort();
    try {
      capability._requests.send({...frame, 'reply': port.sendPort});
      final Object? message;
      try {
        message = await port.first.timeout(requestTimeout);
      } on TimeoutException {
        throw NotebookWriterUnavailableException(
          'no reply from ${capability.ownerId} within $requestTimeout',
        );
      }
      if (message is! Map) {
        throw const NotebookWriterProtocolException('reply is not a map');
      }
      if (message['type'] == 'error' && !raw) {
        final code = message['code'];
        if (code is! String) {
          throw const NotebookWriterProtocolException(
            'error reply has no code',
          );
        }
        if (code == _codeDisposed) {
          throw NotebookWriterUnavailableException(
            '${capability.ownerId} is disposed',
          );
        }
        throw NotebookWriterRefusedException(code);
      }
      return message;
    } finally {
      port.close();
    }
  }

  static final Map<String, NotebookWriterOutcome> _outcomes = {
    for (final outcome in NotebookWriterOutcome.values) outcome.name: outcome,
  };

  static int _requireInt(Map<Object?, Object?> message, String key) {
    final value = message[key];
    if (value is! int) {
      throw NotebookWriterProtocolException('reply field "$key" is not an int');
    }
    return value;
  }
}

/// The owner refused the request. Nothing was written.
///
/// [code] is stable and machine-readable. The current set is
/// `invalidRequest`, `scopeMismatch`, and `failed`.
class NotebookWriterRefusedException implements Exception {
  const NotebookWriterRefusedException(this.code);

  final String code;

  @override
  String toString() => 'NotebookWriterRefusedException($code)';
}

/// The owner could not be reached, or it is disposed.
class NotebookWriterUnavailableException implements Exception {
  const NotebookWriterUnavailableException(this.message);

  final String message;

  @override
  String toString() => 'NotebookWriterUnavailableException: $message';
}

/// The reply did not match the protocol this build understands.
class NotebookWriterProtocolException implements Exception {
  const NotebookWriterProtocolException(this.message);

  final String message;

  @override
  String toString() => 'NotebookWriterProtocolException: $message';
}

const String _codeDisposed = 'disposed';
const String _codeInvalidRequest = 'invalidRequest';

int _ownerCounter = 0;

/// The one writer for one envelope file.
///
/// The owner holds the only [AtomicNotebookStore] for its target. It runs in
/// whichever isolate opened it and answers requests one at a time, so no two
/// callers can be inside a read-check-write at once.
final class NotebookWriterOwner {
  NotebookWriterOwner._(
    this._requests, {
    required this.ownerId,
    required this._store,
    required this._baseline,
    this.beforeHandle,
  }) {
    capability = NotebookWriterCapability._(_requests.sendPort, ownerId);
    _subscription = _requests.listen(_enqueue);
  }

  late final StreamSubscription<Object?> _subscription;

  /// Opens an owner for [file].
  ///
  /// [baseline] is the pre-journal snapshot the envelope was seeded with, the
  /// same explicit seed `AtomicNotebookStore.projectionValidated` requires. The
  /// owner replays its journal onto that baseline and never onto a snapshot a
  /// caller supplied.
  ///
  /// Construction is deliberately not exclusive; see the library comment.
  static NotebookWriterOwner open({
    required File file,
    required JournalScope scope,
    required Notebook baseline,
    String? ownerId,
    Future<void> Function()? beforeHandle,
  }) {
    final baselineValue = JournalProjectionBaseline(
      notebook: baseline,
      scope: scope,
    );
    final id = ownerId ?? 'owner-${++_ownerCounter}';
    requireOpaqueId(id, field: 'ownerId');
    return NotebookWriterOwner._(
      ReceivePort(),
      ownerId: id,
      store: AtomicNotebookStore.projectionValidated(
        file,
        scope: scope,
        baseline: baselineValue,
      ),
      baseline: baselineValue,
      beforeHandle: beforeHandle,
    );
  }

  /// Identifier of this owner. It is copied into every capability it issues.
  final String ownerId;

  /// Test seam awaited inside every handler, after the frame is accepted and
  /// before any read. Production callers leave it null. It makes the
  /// serialization property observable: if handlers could overlap, this hook
  /// would run twice at once and [maxObservedConcurrency] would exceed one.
  final Future<void> Function()? beforeHandle;

  /// The only handle callers get. It is sendable, so it can be handed to
  /// another isolate, and it still names this owner alone.
  late final NotebookWriterCapability capability;

  final ReceivePort _requests;
  final AtomicNotebookStore _store;
  final JournalProjectionBaseline _baseline;

  Future<void> _tail = Future<void>.value();
  bool _closed = false;
  int _accepted = 0;

  /// Number of requests this owner has accepted into its queue. Diagnostics
  /// only, so a test can tell that a frame was accepted before closing.
  int get acceptedRequestCount => _accepted;

  int _active = 0;
  int _maxActive = 0;

  /// Highest number of handlers that were ever inside the queue at the same
  /// time. A correct owner never exceeds one, because requests are chained.
  int get maxObservedConcurrency => _maxActive;

  /// Stops accepting work, drains what was already accepted, and closes the
  /// request port.
  ///
  /// A request that arrives after this call is refused with
  /// [NotebookWriterUnavailableException] while the port is still open, and
  /// dropped once it is closed. Reopening an owner on the same file is the
  /// recovery path; there is no reset.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _tail;
    await _subscription.cancel();
    _requests.close();
  }

  void _enqueue(Object? frame) {
    _accepted++;
    if (_closed) {
      _sendError(_replyPortOf(frame), _codeDisposed);
      return;
    }
    _tail = _tail.then((_) async {
      try {
        await _handle(frame);
      } catch (_) {
        // The handler is expected to answer every accepted frame. If it still
        // throws, the chain must survive so later requests are not stranded.
        _sendError(_replyPortOf(frame), 'failed');
      }
    });
  }

  Future<void> _handle(Object? frame) async {
    _active++;
    if (_active > _maxActive) _maxActive = _active;
    try {
      await _dispatch(frame);
    } finally {
      _active--;
    }
  }

  Future<void> _dispatch(Object? frame) async {
    final hook = beforeHandle;
    if (hook != null) await hook();
    final request = _parse(frame);
    if (request == null) {
      _sendError(_replyPortOf(frame), _codeInvalidRequest);
      return;
    }
    final operation = request.operation;
    if (operation == null) {
      await _handleRead(request.reply);
      return;
    }
    await _handleCommit(request.reply, request.baseRevision!, operation);
  }

  Future<void> _handleRead(SendPort reply) async {
    final result = await _readStored();
    final code = result.errorCode;
    if (code != null) {
      _sendError(reply, code);
      return;
    }
    final stored = result.envelope;
    _send(reply, {
      'type': 'snapshot',
      'revision': stored?.revision ?? 0,
      'journalLength': stored?.journal.length ?? 0,
    });
  }

  Future<void> _handleCommit(
    SendPort reply,
    int baseRevision,
    Map<String, Object?> encoded,
  ) async {
    final JournalOperation operation;
    try {
      operation = JournalOperation.fromJson(encoded);
    } on JournalFormatException {
      _sendError(reply, _codeInvalidRequest);
      return;
    }
    final result = await _readStored();
    final code = result.errorCode;
    if (code != null) {
      // A document that cannot be read is a typed storage failure, not a
      // protocol error: nothing was written and the bytes are untouched.
      _sendReply(reply, NotebookWriterOutcome.failed, 0, 0);
      return;
    }
    final stored = result.envelope;
    if (stored == null) {
      _sendReply(reply, NotebookWriterOutcome.missing, 0, 0);
      return;
    }
    if (stored.revision != baseRevision) {
      _sendReply(
        reply,
        NotebookWriterOutcome.stale,
        stored.revision,
        stored.journal.length,
      );
      return;
    }

    final Journal journal;
    try {
      journal = Journal(
        notebookId: stored.journal.notebookId,
        epochId: stored.journal.epochId,
        operations: stored.journal.operations,
      );
    } on JournalFormatException {
      _sendError(reply, 'failed');
      return;
    }

    final admission = journal.admit(operation);
    switch (admission.admission) {
      case JournalAdmission.rejected:
        _sendError(reply, 'scopeMismatch');
        return;
      case JournalAdmission.collided:
        _sendReply(
          reply,
          NotebookWriterOutcome.conflict,
          stored.revision,
          stored.journal.length,
        );
        return;
      case JournalAdmission.replayed:
        _sendReply(
          reply,
          NotebookWriterOutcome.duplicate,
          stored.revision,
          stored.journal.length,
        );
        return;
      case JournalAdmission.appended:
        break;
    }

    final JournalReplayResult projection;
    try {
      projection = JournalReplay.project(
        notebookId: stored.journal.notebookId,
        epochId: stored.journal.epochId,
        base: _baseline.notebook,
        journal: Journal(
          notebookId: stored.journal.notebookId,
          epochId: stored.journal.epochId,
          operations: [...stored.journal.operations, operation],
        ),
      );
    } on JournalFormatException {
      _sendError(reply, 'failed');
      return;
    }
    // A projection with unresolved conflicts is still handed to the store:
    // the store's projection gate is the single authority for refusing it, so
    // the owner does not keep a second, drifting copy of that rule.

    final committed = await _store.commit(
      base: stored,
      notebook: projection.notebook,
      operation: operation,
    );
    final envelope = committed.envelope;
    _sendReply(
      reply,
      _outcomeFor(committed.status),
      envelope?.revision ?? stored.revision,
      envelope?.journal.length ?? stored.journal.length,
    );
  }

  Future<_StoredRead> _readStored() async {
    try {
      return _StoredRead(await _store.read());
    } on EnvelopeFormatException {
      return const _StoredRead.errorCode('failed');
    } on EnvelopeScopeMismatch {
      return const _StoredRead.errorCode('scopeMismatch');
    } on FileSystemException {
      return const _StoredRead.errorCode('failed');
    }
  }

  static void _sendReply(
    SendPort reply,
    NotebookWriterOutcome outcome,
    int revision,
    int journalLength,
  ) => _send(reply, {
    'type': 'reply',
    'outcome': outcome.name,
    'revision': revision,
    'journalLength': journalLength,
  });

  static void _sendError(SendPort? reply, String code) {
    if (reply == null) return;
    _send(reply, {'type': 'error', 'code': code});
  }

  static void _send(SendPort reply, Map<String, Object?> message) {
    try {
      reply.send(message);
    } on Object {
      // A caller that closed its reply port before the answer is no longer
      // listening. Dropping the answer must not disturb the queue.
    }
  }

  static SendPort? _replyPortOf(Object? frame) {
    if (frame is! Map) return null;
    final reply = frame['reply'];
    return reply is SendPort ? reply : null;
  }
}

/// One validated request frame.
final class _ParsedRequest {
  const _ParsedRequest.read(this.reply) : baseRevision = null, operation = null;

  const _ParsedRequest.commit(this.reply, this.baseRevision, this.operation);

  final SendPort reply;
  final int? baseRevision;
  final Map<String, Object?>? operation;
}

final class _StoredRead {
  const _StoredRead(this.envelope) : errorCode = null;

  const _StoredRead.errorCode(this.errorCode) : envelope = null;

  final NotebookEnvelope? envelope;
  final String? errorCode;
}

_ParsedRequest? _parse(Object? frame) {
  if (frame is! Map) return null;
  final reply = frame['reply'];
  if (reply is! SendPort) return null;
  final type = frame['type'];
  if (type == 'read') {
    if (!_hasExactKeys(frame, const {'type', 'reply'})) return null;
    return _ParsedRequest.read(reply);
  }
  if (type == 'commit') {
    if (!_hasExactKeys(frame, const {
      'type',
      'reply',
      'baseRevision',
      'operation',
    })) {
      return null;
    }
    final baseRevision = frame['baseRevision'];
    final operation = frame['operation'];
    if (baseRevision is! int || baseRevision < 1) return null;
    if (operation is! Map) return null;
    if (operation.keys.any((key) => key is! String)) return null;
    return _ParsedRequest.commit(
      reply,
      baseRevision,
      Map<String, Object?>.from(operation),
    );
  }
  return null;
}

/// Exact key match, so an unrecognised field is refused instead of ignored. A
/// caller therefore cannot smuggle a snapshot, a scope, or a second target
/// through an extra key.
bool _hasExactKeys(Map<Object?, Object?> frame, Set<String> expected) {
  if (frame.length != expected.length) return false;
  for (final key in frame.keys) {
    if (key is! String || !expected.contains(key)) return false;
  }
  return true;
}

NotebookWriterOutcome _outcomeFor(EnvelopeCommitStatus status) =>
    switch (status) {
      EnvelopeCommitStatus.committed => NotebookWriterOutcome.committed,
      EnvelopeCommitStatus.noChange => NotebookWriterOutcome.noChange,
      EnvelopeCommitStatus.duplicate => NotebookWriterOutcome.duplicate,
      EnvelopeCommitStatus.conflict => NotebookWriterOutcome.conflict,
      EnvelopeCommitStatus.stale => NotebookWriterOutcome.stale,
      EnvelopeCommitStatus.inconsistent => NotebookWriterOutcome.inconsistent,
      EnvelopeCommitStatus.scopeMismatch => NotebookWriterOutcome.scopeMismatch,
      EnvelopeCommitStatus.projectionMismatch =>
        NotebookWriterOutcome.projectionMismatch,
      EnvelopeCommitStatus.projectionConflict =>
        NotebookWriterOutcome.projectionConflict,
      EnvelopeCommitStatus.failed => NotebookWriterOutcome.failed,
    };
