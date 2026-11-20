/// Historical-epoch check in front of the version 1 backup/restore/wipe policy.
///
/// `planJournalBarrier` decides whether a restore or wipe may proceed, but it
/// deliberately checks only the journal it is handed: it cannot know whether a
/// proposed fresh epoch was issued years ago, because a pure helper sees no
/// durable record. This module supplies exactly that missing check, using an
/// [EpochHistory] ledger, and otherwise defers to the version 1 policy
/// unchanged. It is a seam, not a replacement: it never reads or writes
/// storage, never mutates the journal or the ledger, and never touches entry
/// text.
///
/// Order of evaluation, fixed so identical inputs give identical decisions:
///
/// 1. [planJournalBarrier], for notebook validity, notebook scope, pending
///    operations, and fresh-epoch validity. A blocked decision is returned as
///    is, so the version 1 policy keeps its authority.
/// 2. The ledger's notebook must equal the requested notebook.
/// 3. The ledger must prove the journal's current epoch: its newest epoch must
///    be the journal epoch, and every earlier epoch must precede it.
/// 4. The fresh epoch must not appear anywhere in the ledger.
///
/// Steps 1 and 2 are ordered this way because a pending operation or an
/// invalid identifier is a stronger refusal than a ledger mismatch, and
/// because the version 1 policy is the existing contract. Steps 3 and 4 only
/// run for restore or wipe: export never adopts an epoch, so it needs no
/// historical check.
///
/// Nothing here persists the plan. A caller that adopts an allowed plan must
/// record the fresh epoch in the ledger and write the restored notebook, the
/// fresh journal, and the extended ledger in one durable step; that step is a
/// later milestone and is not implemented here.
library;

import 'epoch_history.dart';
import 'journal.dart';
import 'journal_barrier.dart';

/// Why a [HistoricalBarrierDecision] was allowed or refused.
enum HistoricalBarrierStatus {
  /// The action may proceed; [HistoricalBarrierDecision.plan] is present for a
  /// restore or wipe, absent for export.
  allowed,

  /// The version 1 policy blocked the action. Nothing was considered further.
  barrierBlocked,

  /// The ledger records a different notebook than the requested one.
  historyNotebookMismatch,

  /// The ledger cannot prove the journal's current epoch, so it cannot be used
  /// to judge historical uniqueness for this journal.
  historyDoesNotReachJournal,

  /// The fresh epoch already appears in the ledger.
  freshEpochReused,
}

/// One historical-barrier check.
///
/// The constructor is private so a caller cannot build an inconsistent value,
/// such as an allowed decision without a plan, in any build mode.
final class HistoricalBarrierDecision {
  const HistoricalBarrierDecision._({
    required this.action,
    required this.status,
    required this.barrier,
    this.plan,
  });

  final JournalBarrierAction action;
  final HistoricalBarrierStatus status;

  /// The underlying version 1 decision, always present.
  final JournalBarrierDecision barrier;

  /// Present only for an allowed restore or wipe.
  final JournalBarrierPlan? plan;

  bool get allowed => status == HistoricalBarrierStatus.allowed;

  /// Stable, content-free code suitable for diagnostics.
  String get diagnosticCode =>
      'journal.historyBarrier.${action.name}.${status.name}';

  @override
  bool operator ==(Object other) =>
      other is HistoricalBarrierDecision &&
      other.action == action &&
      other.status == status &&
      other.barrier == barrier &&
      other.plan == plan;

  @override
  int get hashCode => Object.hash(action, status, barrier, plan);

  @override
  String toString() => 'HistoricalBarrierDecision($diagnosticCode)';
}

/// Evaluates [action] against [journal], the requested [notebookId], the durable
/// [history], and, for restore or wipe, an explicit [freshEpochId].
///
/// Neither the journal nor the ledger is modified. See the library comment for
/// the fixed order of evaluation.
HistoricalBarrierDecision planHistoricalBarrier({
  required JournalBarrierAction action,
  required Journal journal,
  required String notebookId,
  required EpochHistory history,
  String? freshEpochId,
}) {
  final barrier = planJournalBarrier(
    action: action,
    journal: journal,
    notebookId: notebookId,
    freshEpochId: freshEpochId,
  );
  if (!barrier.allowed) {
    return HistoricalBarrierDecision._(
      action: action,
      status: HistoricalBarrierStatus.barrierBlocked,
      barrier: barrier,
    );
  }
  if (action == JournalBarrierAction.export) {
    return HistoricalBarrierDecision._(
      action: action,
      status: HistoricalBarrierStatus.allowed,
      barrier: barrier,
    );
  }
  if (history.notebookId != notebookId) {
    return HistoricalBarrierDecision._(
      action: action,
      status: HistoricalBarrierStatus.historyNotebookMismatch,
      barrier: barrier,
    );
  }
  // The version 1 policy already validated the fresh epoch and compared it with
  // the journal epoch, so a non-null, well-formed value is guaranteed here.
  final fresh = freshEpochId!;
  if (history.latest != journal.epochId) {
    return HistoricalBarrierDecision._(
      action: action,
      status: HistoricalBarrierStatus.historyDoesNotReachJournal,
      barrier: barrier,
    );
  }
  if (history.contains(fresh)) {
    return HistoricalBarrierDecision._(
      action: action,
      status: HistoricalBarrierStatus.freshEpochReused,
      barrier: barrier,
    );
  }
  return HistoricalBarrierDecision._(
    action: action,
    status: HistoricalBarrierStatus.allowed,
    barrier: barrier,
    plan: JournalBarrierPlan(notebookId: notebookId, epochId: fresh),
  );
}
