/// Derivation of one version 2 reset document, and the outcome a reset returns.
///
/// Experimental and unshipped: no production code imports this library, and the
/// only writer that persists what it produces is
/// `epoch_history_store.dart`. This library is pure Dart: no `dart:io`, no
/// Flutter, no clock, and no random source. It never reads or writes storage
/// and never mutates the stored document it is given.
///
/// What a reset is
/// ---------------
/// A reset replaces a notebook's data and moves the journal to a fresh epoch.
/// The version 1 policy in `journal_barrier.dart` allows a restore or wipe only
/// when no retained operation remains, and the ledger check in
/// `epoch_history_barrier.dart` adds historical uniqueness on top of it. This
/// library turns an allowed decision into the one document a caller may then
/// store, and nothing else.
///
/// What the caller may and may not state
/// -------------------------------------
/// The caller supplies only:
///
/// * the notebook the store is bound to, checked against the store binding;
/// * the revision and journal epoch it observed, which must be the stored
///   ones, so a stale request is refused instead of overwriting a newer
///   document;
/// * a validated opaque fresh epoch;
/// * the *payload* of the action: a backup snapshot to restore, or nothing at
///   all for a wipe.
///
/// The caller never supplies the next document, the next revision, the next
/// ledger, or the next journal. All four are derived here, so a reset cannot
/// mint two epochs, drop a recorded epoch, keep an earlier epoch's operations,
/// or claim a revision that does not follow the stored one. An earlier
/// experimental adapter accepted a whole replacement document and could be
/// used to persist a fresh epoch together with an emptied notebook and no
/// policy check anywhere; that shape is deliberately not expressible here.
///
/// Fixed order of evaluation
/// -------------------------
/// Identical inputs always produce an identical outcome, and the order is
/// chosen so a destructive action is never authorized on evidence the caller
/// controls:
///
/// 1. scope — the requested notebook must be the store's notebook;
/// 2. staleness — the observed revision and journal epoch must be the stored
///    ones;
/// 3. policy — `planHistoricalBarrier` decides from the stored document;
/// 4. payload — only now is the caller's snapshot canonicalized.
///
/// The payload is last on purpose. A malformed backup must not be parsed until
/// the destructive action has been authorized, and a policy refusal must not
/// be masked by a payload refusal. Nothing here inspects payload content on a
/// refusal path.
///
/// What is not claimed
/// -------------------
/// * The ledger records epochs that a committed reset adopted. It does not
///   prove that an epoch was never used by some other notebook, and it does not
///   record identity or intent. Two calls that name the same fresh epoch are
///   indistinguishable here, which is why a repeated request is refused as
///   stale rather than reported as a duplicate of the caller's own work.
/// * Only empty journals can be reset, because the version 1 policy keeps
///   authority. Closing that needs an acknowledgement or tombstone protocol.
/// * No digest, signature, revocation, or power-loss guarantee is added.
library;

import '../notebook.dart';
import 'epoch_history_barrier.dart';
import 'epoch_history_envelope.dart';
import 'journal.dart';
import 'journal_barrier.dart';
import 'journal_values.dart';
import 'notebook_envelope.dart';

/// A caller-proposed epoch identifier that another part of the protocol issued.
///
/// The value is validated with the journal's own identifier rule at
/// construction, so an empty string, a numeric-only token, a wall-clock string,
/// a volume ordinal, and diary text are all refused before a reset is planned.
///
/// This type does not generate identifiers and does not certify that one was
/// ever issued. It only carries a token the caller already holds. A token is
/// adopted by the ledger only when a reset carrying it is committed.
final class JournalResetEpoch {
  JournalResetEpoch(this.id) {
    requireOpaqueId(id, field: 'epochId');
  }

  final String id;

  @override
  bool operator ==(Object other) =>
      other is JournalResetEpoch && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'JournalResetEpoch($id)';
}

/// The stored document state a reset request was built from.
///
/// [notebookId] is compared with the store binding, so a request aimed at
/// another notebook cannot be reported as a plain stale write. [revision] and
/// [epochId] are the stale-write token: both must be the stored ones.
final class EpochResetExpectation {
  EpochResetExpectation({
    required this.notebookId,
    required this.epochId,
    required this.revision,
  }) {
    requireOpaqueId(notebookId, field: 'notebookId');
    requireOpaqueId(epochId, field: 'epochId');
    if (revision < 1) {
      throw const JournalFormatException(
        'revision must be at least 1',
        field: 'revision',
      );
    }
  }

  final String notebookId;
  final String epochId;
  final int revision;

  @override
  String toString() =>
      'EpochResetExpectation($notebookId, $epochId, revision $revision)';
}

/// What a reset would write, as far as the caller may state it.
///
/// The payload is held, not read, until every other check has passed. A sealed
/// hierarchy means the action a reset performs is the payload's type, so a
/// caller cannot describe one action and supply another's data.
sealed class JournalResetPayload {
  const JournalResetPayload();
}

/// A restore adopts [backup] as the notebook data of the reset document.
///
/// The snapshot is canonicalized and validated before it is persisted, so a
/// subclass whose getters and encoding disagree cannot be validated with one
/// shape and stored with another. [backup] is only inspected after the scope,
/// staleness, and policy checks pass.
///
/// The backup carries no notebook identifier, so it cannot claim one: the
/// notebook the document belongs to is the store binding in
/// [EpochResetExpectation.notebookId] and the stored ledger, never the payload.
final class JournalRestorePayload extends JournalResetPayload {
  const JournalRestorePayload(this.backup);

  final Notebook backup;
}

/// A wipe discards every entry and archive, keeping the notebook identifier.
///
/// It carries no data, so there is nothing for a caller to widen.
final class JournalWipePayload extends JournalResetPayload {
  const JournalWipePayload();
}

/// The action a payload describes.
JournalBarrierAction epochResetActionFor(JournalResetPayload payload) =>
    switch (payload) {
      JournalRestorePayload() => JournalBarrierAction.restore,
      JournalWipePayload() => JournalBarrierAction.wipe,
    };

/// Why a reset was allowed, committed, or refused.
enum EpochResetStatus {
  /// The plan is consistent and the barriers allow it. This is a decision, not
  /// a write: nothing durable is claimed, and only a store can commit.
  allowed,

  /// The reset document replaced the stored one. Only a store reports this,
  /// and it is the only status that claims a durable change.
  committed,

  /// No stored document exists. A reset never creates one.
  missing,

  /// The observed revision or journal epoch is not the stored one, or the
  /// document changed after it was judged. Nothing was written.
  stale,

  /// The stored document, or the request, names another notebook. Nothing was
  /// written.
  scopeMismatch,

  /// The stored document is a version 1 envelope with no epoch history. It is
  /// never upgraded or bootstrapped. Nothing was written.
  legacyDocument,

  /// The restore payload has no canonically decodable, valid snapshot form.
  /// Nothing was written.
  payloadInvalid,

  /// A barrier refused the action, or no plan was produced. Nothing was
  /// written.
  policyRefused,

  /// The derived document was refused by the codec or by a construction
  /// invariant. Defensive: no public input is expected to reach it. Nothing was
  /// written.
  notDerivable,

  /// Reading, writing, validating, or replacing the file failed. The stored
  /// bytes were left untouched, and this is never reported as [committed].
  failed,
}

/// One reset decision or result.
///
/// Refusals carry only identifiers and counters: [revision], [epochId],
/// [barrier], and a static [reason]. No notebook text, entry text, stored
/// bytes, or file path is carried, so an outcome can be logged as it stands.
/// The derived document is present only for an allowed or a committed
/// transition, because it is the only thing a caller can act on and the only
/// thing that ever holds a snapshot.
///
/// The constructor is private, so only the two named builders can produce a
/// value. [applied] requires a document whose own metadata matches, and
/// [notApplied] refuses a transition status. A caller outside this library
/// therefore cannot fabricate a durable claim, and a refusal cannot smuggle a
/// snapshot.
final class EpochResetOutcome {
  const EpochResetOutcome._({
    required this.action,
    required this.status,
    this.revision,
    this.epochId,
    this.barrier,
    this.document,
    this.reason,
  });

  /// The outcome of a planned or committed transition.
  ///
  /// [status] must be an allowed or a committed transition, and [revision],
  /// [epochId], and [document] must agree with the document's own metadata.
  /// A transition always carries the document it is about, so it cannot be
  /// built as an empty claim.
  static EpochResetOutcome applied({
    required JournalBarrierAction action,
    required EpochResetStatus status,
    required int revision,
    required String epochId,
    required EpochHistoryEnvelope document,
    HistoricalBarrierDecision? barrier,
  }) {
    if (status != EpochResetStatus.allowed &&
        status != EpochResetStatus.committed) {
      throw ArgumentError.value(
        status,
        'status',
        'a transition must be allowed or committed',
      );
    }
    if (document.envelope.revision != revision ||
        document.envelope.journal.epochId != epochId) {
      throw ArgumentError.value(
        revision,
        'revision',
        'transition metadata must match the document it describes',
      );
    }
    return EpochResetOutcome._(
      action: action,
      status: status,
      revision: revision,
      epochId: epochId,
      barrier: barrier,
      document: document,
    );
  }

  /// A refusal or a pre-write failure.
  ///
  /// [revision] and [epochId] describe the stored document the outcome is
  /// about, when it could be read. [status] must not be
  /// [EpochResetStatus.allowed] or [EpochResetStatus.committed], so a refusal
  /// can never carry a document or claim a durable change.
  static EpochResetOutcome notApplied({
    required JournalBarrierAction action,
    required EpochResetStatus status,
    int? revision,
    String? epochId,
    HistoricalBarrierDecision? barrier,
    String? reason,
  }) {
    if (status == EpochResetStatus.allowed ||
        status == EpochResetStatus.committed) {
      throw ArgumentError.value(
        status,
        'status',
        'only a planned or committed transition carries allowed or committed',
      );
    }
    return EpochResetOutcome._(
      action: action,
      status: status,
      revision: revision,
      epochId: epochId,
      barrier: barrier,
      reason: reason,
    );
  }

  final JournalBarrierAction action;
  final EpochResetStatus status;

  /// The revision of the document this outcome describes: the stored revision
  /// on a refusal, or the newly committed revision once committed.
  final int? revision;

  /// The journal epoch of the document this outcome describes: the stored
  /// epoch on a refusal, or the adopted fresh epoch once committed.
  final String? epochId;

  /// The barrier decision that produced this outcome, when the policy ran.
  final HistoricalBarrierDecision? barrier;

  /// The document to store, or the one just stored. Present only for
  /// [EpochResetStatus.allowed] and [EpochResetStatus.committed].
  final EpochHistoryEnvelope? document;

  /// Short static explanation. Never contains diary text or file content.
  final String? reason;

  bool get isAllowed => status == EpochResetStatus.allowed;

  bool get isCommitted => status == EpochResetStatus.committed;

  /// Stable, content-free code suitable for diagnostics.
  String get diagnosticCode => 'journal.reset.${action.name}.${status.name}';

  @override
  bool operator ==(Object other) =>
      other is EpochResetOutcome &&
      other.action == action &&
      other.status == status &&
      other.revision == revision &&
      other.epochId == epochId &&
      other.barrier == barrier &&
      other.reason == reason &&
      _sameDocument(other.document, document);

  @override
  int get hashCode => Object.hash(
    action,
    status,
    revision,
    epochId,
    barrier,
    reason,
    document?.encode(),
  );

  @override
  String toString() => 'EpochResetOutcome($diagnosticCode)';
}

bool _sameDocument(EpochHistoryEnvelope? a, EpochHistoryEnvelope? b) {
  if (a == null || b == null) return a == null && b == null;
  return a.hasSameContentAs(b);
}

/// Derives the reset document for [stored], or refuses it.
///
/// [notebookId] is the store binding and is authoritative. [stored] is the
/// document the caller actually read; [expected] is the state it believes it
/// read; [epoch] is a caller-proposed identifier; [payload] describes the
/// action.
///
/// See the library comment for the fixed order of evaluation. Neither [stored]
/// nor [payload] is modified, no clock is read, and nothing is written.
EpochResetOutcome planEpochReset({
  required String notebookId,
  required EpochHistoryEnvelope stored,
  required EpochResetExpectation expected,
  required JournalResetEpoch epoch,
  required JournalResetPayload payload,
}) {
  final action = epochResetActionFor(payload);
  final storedRevision = stored.envelope.revision;
  final storedEpochId = stored.envelope.journal.epochId;

  // 1. Scope. A request for another notebook is never reported as staleness,
  // because a caller could otherwise retry a destructive action against the
  // wrong notebook.
  if (expected.notebookId != notebookId) {
    return EpochResetOutcome.notApplied(
      action: action,
      status: EpochResetStatus.scopeMismatch,
      revision: storedRevision,
      epochId: storedEpochId,
      reason: 'request names another notebook',
    );
  }

  // 2. Staleness. Both tokens must be the stored ones.
  if (expected.revision != storedRevision) {
    return EpochResetOutcome.notApplied(
      action: action,
      status: EpochResetStatus.stale,
      revision: storedRevision,
      epochId: storedEpochId,
      reason: 'observed revision is not the stored revision',
    );
  }
  if (expected.epochId != storedEpochId) {
    return EpochResetOutcome.notApplied(
      action: action,
      status: EpochResetStatus.stale,
      revision: storedRevision,
      epochId: storedEpochId,
      reason: 'observed journal epoch is not the stored journal epoch',
    );
  }

  // 3. Policy, judged on the stored document alone. The version 1 decision is
  // returned unchanged, and the ledger adds historical uniqueness.
  final barrier = planHistoricalBarrier(
    action: action,
    journal: stored.envelope.journal,
    notebookId: notebookId,
    history: stored.history,
    freshEpochId: epoch.id,
  );
  if (!barrier.allowed) {
    return EpochResetOutcome.notApplied(
      action: action,
      status: EpochResetStatus.policyRefused,
      revision: storedRevision,
      epochId: storedEpochId,
      barrier: barrier,
      reason: barrier.diagnosticCode,
    );
  }
  final plan = barrier.plan;
  if (plan == null || plan.epochId != epoch.id) {
    // Defensive: an allowed restore or wipe always carries the plan for the
    // requested epoch, so this cannot be produced by the code above.
    return EpochResetOutcome.notApplied(
      action: action,
      status: EpochResetStatus.notDerivable,
      revision: storedRevision,
      epochId: storedEpochId,
      barrier: barrier,
      reason: 'the barrier plan does not match the requested epoch',
    );
  }

  // 4. Payload, only now. The decoded plain snapshot is the only value that is
  // ever compared, persisted, or returned.
  final Notebook source = switch (payload) {
    JournalRestorePayload(:final backup) => backup,
    JournalWipePayload() => Notebook.empty(),
  };
  final canonical = CanonicalSnapshot.tryCanonicalize(source);
  if (canonical == null) {
    return EpochResetOutcome.notApplied(
      action: action,
      status: payload is JournalRestorePayload
          ? EpochResetStatus.payloadInvalid
          : EpochResetStatus.notDerivable,
      revision: storedRevision,
      epochId: storedEpochId,
      barrier: barrier,
      reason: 'the reset snapshot has no canonical form',
    );
  }

  final EpochHistoryEnvelope next;
  try {
    // The journal is empty and runs under the fresh epoch; the ledger grows by
    // exactly one entry. `advance` re-checks that the ledger is an append-only
    // extension, and the envelope constructor re-checks that the journal epoch
    // is the newest recorded epoch. Neither rule is duplicated here.
    next = stored.advance(
      revision: storedRevision + 1,
      notebook: canonical.notebook,
      journal: Journal(notebookId: notebookId, epochId: epoch.id),
      history: stored.history.append(epoch.id),
    );
  } on EnvelopeFormatException {
    return EpochResetOutcome.notApplied(
      action: action,
      status: EpochResetStatus.notDerivable,
      revision: storedRevision,
      epochId: storedEpochId,
      barrier: barrier,
      reason: 'the derived document is not a valid stored document',
    );
  } on JournalFormatException {
    // Defensive: the policy already refused a repeated or malformed epoch, so
    // a ledger append or the empty journal cannot refuse here in practice.
    return EpochResetOutcome.notApplied(
      action: action,
      status: EpochResetStatus.notDerivable,
      revision: storedRevision,
      epochId: storedEpochId,
      barrier: barrier,
      reason: 'the derived document is not a valid stored document',
    );
  }

  return EpochResetOutcome.applied(
    action: action,
    status: EpochResetStatus.allowed,
    revision: next.envelope.revision,
    epochId: epoch.id,
    document: next,
    barrier: barrier,
  );
}
