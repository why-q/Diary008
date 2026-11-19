/// Pure backup, restore, and wipe policy for the offline entry journal.
///
/// This module decides only whether an existing backup export, a restore, or a
/// wipe may proceed against a given [Journal]. It never reads or writes
/// storage, never inspects entry text, and never mutates the journal it is
/// given. Every decision is expressed with typed values so a caller can record
/// diagnostics without leaking diary content.
///
/// Policy for schema version 1:
///
/// * Version 1 journals have no acknowledgement or tombstone protocol, so this
///   policy cannot distinguish shipped operations from unshipped ones. Every
///   retained operation is therefore treated as pending.
/// * The existing export format omits the journal, so an export would silently
///   drop pending operations. Export is blocked while any operation remains.
/// * Restore and wipe replace or destroy notebook data. They are blocked while
///   any operation remains, because there is no defined policy for discarding
///   unsynced diary text.
/// * Restore or wipe of an empty journal requires an explicit fresh epoch for
///   the same notebook. The result is an empty [JournalBarrierPlan] under that
///   epoch, not a write.
///
/// Epoch identifiers must never be reused. A pure helper cannot verify global
/// historical uniqueness: it only sees the journal in front of it. The caller
/// must enforce uniqueness against a durable record of every epoch ever issued
/// for the notebook before committing a plan.
///
/// A future caller that adopts this policy would, in one durable step, write
/// the restored or emptied notebook data together with the fresh epoch, then
/// release the existing reminder barrier (`ReminderService.beginDestruction`
/// and `endDestruction`) so reminders are recalculated against the new scope.
/// No production code calls this module yet; persisted behavior is unchanged.
library;

import 'journal.dart';
import 'journal_values.dart';

/// The operations a backup policy checkpoint governs.
enum JournalBarrierAction {
  /// Writing the current notebook to an external backup file.
  export,

  /// Replacing notebook data with the contents of a backup file.
  restore,

  /// Destroying notebook data on this device.
  wipe,
}

/// Why a [JournalBarrierAction] was allowed or blocked.
enum JournalBarrierReason {
  /// The action may proceed.
  allowed,

  /// The journal retains operations that version 1 cannot prove are shipped.
  pendingOperations,

  /// The requested notebook identifier is not a valid opaque identifier.
  notebookInvalid,

  /// The journal belongs to a different notebook than the requested one.
  notebookMismatch,

  /// Restore or wipe of an empty journal needs an explicit fresh epoch.
  freshEpochRequired,

  /// The supplied fresh epoch is not a valid opaque identifier.
  freshEpochInvalid,

  /// The supplied fresh epoch equals the journal's current epoch.
  freshEpochReused,
}

/// The empty journal scope a restore or wipe would adopt on success.
///
/// This is a plan only. Creating it does not write, persist, or publish
/// anything. [emptyJournal] yields a fresh in-memory journal whose scope can
/// admit only operations carrying [notebookId] and [epochId]; operations from
/// the previous epoch are rejected on admission.
final class JournalBarrierPlan {
  const JournalBarrierPlan({required this.notebookId, required this.epochId});

  final String notebookId;
  final String epochId;

  Journal emptyJournal() => Journal(notebookId: notebookId, epochId: epochId);

  @override
  bool operator ==(Object other) =>
      other is JournalBarrierPlan &&
      other.notebookId == notebookId &&
      other.epochId == epochId;

  @override
  int get hashCode => Object.hash(notebookId, epochId);

  @override
  String toString() => 'JournalBarrierPlan($notebookId, $epochId)';
}

/// The outcome of one policy checkpoint.
final class JournalBarrierDecision {
  const JournalBarrierDecision({
    required this.action,
    required this.reason,
    this.plan,
  }) : assert(
         reason == JournalBarrierReason.allowed
             ? (action == JournalBarrierAction.export
                   ? plan == null
                   : plan != null)
             : plan == null,
         'only an allowed restore or wipe carries a plan',
       );

  final JournalBarrierAction action;
  final JournalBarrierReason reason;

  /// Present only for an allowed restore or wipe. Export never carries one.
  final JournalBarrierPlan? plan;

  bool get allowed => reason == JournalBarrierReason.allowed;

  /// Stable, content-free code suitable for diagnostics.
  String get diagnosticCode => 'journal.barrier.${action.name}.${reason.name}';

  @override
  bool operator ==(Object other) =>
      other is JournalBarrierDecision &&
      other.action == action &&
      other.reason == reason &&
      other.plan == plan;

  @override
  int get hashCode => Object.hash(action, reason, plan);

  @override
  String toString() => 'JournalBarrierDecision($diagnosticCode)';
}

/// Evaluates [action] against [journal] for the notebook [notebookId].
///
/// [freshEpochId] is required for restore or wipe of an empty journal and is
/// ignored for export. The journal is never modified.
///
/// Checks run in a fixed order so identical inputs always produce identical
/// decisions: target notebook validity, notebook scope, pending operations,
/// then fresh-epoch validation.
JournalBarrierDecision planJournalBarrier({
  required JournalBarrierAction action,
  required Journal journal,
  required String notebookId,
  String? freshEpochId,
}) {
  if (!_isOpaqueId(notebookId)) {
    return JournalBarrierDecision(
      action: action,
      reason: JournalBarrierReason.notebookInvalid,
    );
  }
  if (journal.notebookId != notebookId) {
    return JournalBarrierDecision(
      action: action,
      reason: JournalBarrierReason.notebookMismatch,
    );
  }
  if (!journal.isEmpty) {
    return JournalBarrierDecision(
      action: action,
      reason: JournalBarrierReason.pendingOperations,
    );
  }
  if (action == JournalBarrierAction.export) {
    return JournalBarrierDecision(
      action: action,
      reason: JournalBarrierReason.allowed,
    );
  }
  if (freshEpochId == null) {
    return JournalBarrierDecision(
      action: action,
      reason: JournalBarrierReason.freshEpochRequired,
    );
  }
  if (!_isOpaqueId(freshEpochId)) {
    return JournalBarrierDecision(
      action: action,
      reason: JournalBarrierReason.freshEpochInvalid,
    );
  }
  if (freshEpochId == journal.epochId) {
    return JournalBarrierDecision(
      action: action,
      reason: JournalBarrierReason.freshEpochReused,
    );
  }
  return JournalBarrierDecision(
    action: action,
    reason: JournalBarrierReason.allowed,
    plan: JournalBarrierPlan(notebookId: notebookId, epochId: freshEpochId),
  );
}

bool _isOpaqueId(String value) {
  try {
    requireOpaqueId(value, field: 'identifier');
    return true;
  } on JournalFormatException {
    return false;
  }
}
