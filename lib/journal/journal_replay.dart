/// Pure, deterministic replay of an accepted journal onto a notebook.
///
/// Experimental and unshipped: no production code calls this, it reads no
/// clock, and it performs no I/O. The same base notebook and journal always
/// produce the same notebook.
///
/// Rules, all conservative:
///
/// * Operations apply in one canonical order: `recordedAt` UTC microseconds,
///   then `actorId`, then `sequence`, then `operationId`. The order decides
///   display order and supplement placement only. It never decides whose text
///   survives, because every accepted operation is kept.
/// * A create becomes a due-less [EntryStatus.explanation] entry in the current
///   volume. It keeps the exact `entryId`, the verbatim text (no trimming),
///   `createdAt` equal to the recorded instant, and `createdOn` equal to the
///   operation's explicit civil date.
/// * A revision mirrors [Notebook.revise] as a supplement, not a replacement:
///   the base entry is marked [EntryStatus.revised] and a due-less explanation
///   supplement is placed directly after it. The supplement's civil date is
///   the UTC calendar date of the recorded instant. A v1 revision carries no
///   civil date, and the recording device's local calendar cannot be
///   reconstructed, so this projection documents that limitation instead of
///   guessing.
/// * Existing entries, their order, and every notebook metadata field are
///   preserved. Nothing is migrated, merged, or rewritten.
///
/// Identity is exact. An operation is never matched to an entry by text,
/// creation time, or volume position. Anything that cannot be applied exactly
/// is reported as a typed [JournalReplayConflict] that keeps the original
/// operation, so no payload is lost.
library;

import '../notebook.dart';
import 'journal.dart';
import 'journal_operation.dart';
import 'journal_values.dart';

/// Why one accepted operation could not be projected exactly.
enum JournalReplayConflictKind {
  /// A create reuses an entry id that already exists in the current volume,
  /// in an archived volume, or on an earlier projected entry.
  entryIdCollision,

  /// A revision targets an id that is not in the base current volume.
  missingTarget,

  /// A revision targets an id that exists only in an archived volume.
  archivedTarget,

  /// A revision targets an id that is duplicated, so the target is ambiguous.
  ambiguousTarget,

  /// A revision targets a base entry that is not pending.
  ineligibleTarget,

  /// A revision targets a pending base entry that has no due date, so the
  /// supplement shape [Notebook.revise] produces cannot be mirrored.
  dueLessTarget,

  /// A revision targets an entry created by this same journal. v1 revisions
  /// carry no due information, so the created entry's eligibility cannot be
  /// established without inventing data.
  createThenRevise,

  /// A projected supplement id would overwrite an existing id.
  generatedIdCollision,

  /// Two or more actors revised the same base entry. All revisions are kept;
  /// no last-writer winner is chosen.
  competingActors,
}

/// One operation that replay refused to apply, with its exact payload.
///
/// [operation] is the original immutable operation, so its text stays
/// reachable. Diagnostic strings never include diary text.
class JournalReplayConflict {
  const JournalReplayConflict(
    this.kind, {
    required this.operation,
    this.target,
    this.related = const [],
  });

  final JournalReplayConflictKind kind;

  /// The exact operation that could not be applied.
  final JournalOperation operation;

  /// The existing entry the operation addressed, when one exists.
  final JournalEntry? target;

  /// Further operations belonging to the same conflict. Used by
  /// [JournalReplayConflictKind.competingActors] for the other actors'
  /// revisions.
  final List<JournalOperation> related;

  @override
  String toString() =>
      'JournalReplayConflict(${kind.name}, '
      'operation: ${operation.operationId}'
      '${target == null ? '' : ', target: ${target!.id}'})';
}

/// Deterministic projection plus everything it could not apply.
class JournalReplayResult {
  JournalReplayResult._({
    required this.notebook,
    required this.appliedOperations,
    required this.conflicts,
    required this.appliedRevisionsByEntry,
  });

  /// The projected notebook. The base notebook is never mutated.
  final Notebook notebook;

  /// Operations that were applied, in canonical order.
  final List<JournalOperation> appliedOperations;

  /// Operations that were refused, plus competing-actor flags.
  final List<JournalReplayConflict> conflicts;

  /// Applied revisions per base entry id, in canonical order.
  final Map<String, List<JournalOperation>> appliedRevisionsByEntry;

  bool get hasConflicts => conflicts.isNotEmpty;

  /// Every journal operation this result accounts for, either applied or kept
  /// in a conflict. Sorted by operation id so the list is stable.
  List<JournalOperation> get accountedOperations {
    final byId = <String, JournalOperation>{};
    for (final operation in appliedOperations) {
      byId[operation.operationId] = operation;
    }
    for (final conflict in conflicts) {
      byId[conflict.operation.operationId] = conflict.operation;
      for (final operation in conflict.related) {
        byId[operation.operationId] = operation;
      }
    }
    final ids = byId.keys.toList()..sort();
    return List.unmodifiable([for (final id in ids) byId[id]!]);
  }
}

/// Projects an accepted journal onto a base notebook.
///
/// [notebookId] and [epochId] state the scope the caller expects. A journal
/// recorded for another notebook or epoch is rejected before any work, so no
/// partial projection can be observed.
abstract final class JournalReplay {
  /// Applies [journal] to [base] under the explicit [notebookId]/[epochId]
  /// scope.
  ///
  /// Throws [JournalFormatException] when the scope does not match or the
  /// scope identifiers are invalid.
  static JournalReplayResult project({
    required String notebookId,
    required String epochId,
    required Notebook base,
    required Journal journal,
  }) {
    requireOpaqueId(notebookId, field: 'notebookId');
    requireOpaqueId(epochId, field: 'epochId');
    if (journal.notebookId != notebookId) {
      throw const JournalFormatException(
        'journal belongs to another notebook',
        field: 'notebookId',
      );
    }
    if (journal.epochId != epochId) {
      throw const JournalFormatException(
        'journal belongs to another notebook epoch',
        field: 'epochId',
      );
    }

    final current = <String, JournalEntry>{};
    final currentDuplicated = <String>{};
    for (final entry in base.entries) {
      if (current.containsKey(entry.id)) {
        currentDuplicated.add(entry.id);
      } else {
        current[entry.id] = entry;
      }
    }

    final archived = <String, JournalEntry>{};
    final archivedDuplicated = <String>{};
    for (final archive in base.archives) {
      for (final entry in archive.entries) {
        if (archived.containsKey(entry.id)) {
          archivedDuplicated.add(entry.id);
        } else {
          archived[entry.id] = entry;
        }
      }
    }

    final ordered = journal.operations.toList()..sort(_compareOperations);

    // Creates claim explicit entry ids, so they are decided first. Because a
    // journal admits at most one create per entry id, each decision depends
    // only on the base notebook, never on processing order.
    final usedIds = <String>{...current.keys, ...archived.keys};
    final journalCreateTargetIds = <String>{
      for (final operation in ordered)
        if (operation is JournalCreateEntry) operation.entryId,
    };
    final createConflicts = <String, JournalReplayConflict>{};
    final projectedCreateById = <String, JournalEntry>{};
    for (final operation in ordered) {
      if (operation is! JournalCreateEntry) continue;
      if (usedIds.contains(operation.entryId)) {
        final conflict = JournalReplayConflict(
          JournalReplayConflictKind.entryIdCollision,
          operation: operation,
          target: current[operation.entryId] ?? archived[operation.entryId],
        );
        createConflicts[operation.operationId] = conflict;
        continue;
      }
      usedIds.add(operation.entryId);
      projectedCreateById[operation.entryId] = JournalEntry(
        id: operation.entryId,
        text: operation.text,
        createdAt: operation.recordedAt,
        createdOn: _civilDateOf(operation.createdOn),
        status: EntryStatus.explanation,
      );
    }

    final applied = <JournalOperation>[];
    final conflicts = <JournalReplayConflict>[];
    final supplements = <String, List<JournalEntry>>{};
    final revisions = <String, List<JournalOperation>>{};
    final revisedBaseIds = <String>{};
    final projectedCreates = <JournalEntry>[];

    for (final operation in ordered) {
      switch (operation) {
        case JournalCreateEntry():
          final conflict = createConflicts[operation.operationId];
          if (conflict != null) {
            conflicts.add(conflict);
            continue;
          }
          projectedCreates.add(projectedCreateById[operation.entryId]!);
          applied.add(operation);
        case JournalReviseEntry():
          final conflict = _checkRevisionTarget(
            operation,
            current: current,
            currentDuplicated: currentDuplicated,
            archived: archived,
            archivedDuplicated: archivedDuplicated,
            journalCreateTargetIds: journalCreateTargetIds,
            projectedCreateById: projectedCreateById,
          );
          if (conflict != null) {
            conflicts.add(conflict);
            continue;
          }
          final supplementId = _supplementId(base.volume, operation);
          if (usedIds.contains(supplementId)) {
            conflicts.add(
              JournalReplayConflict(
                JournalReplayConflictKind.generatedIdCollision,
                operation: operation,
                target: current[operation.entryId],
              ),
            );
            continue;
          }
          usedIds.add(supplementId);
          revisedBaseIds.add(operation.entryId);
          (supplements[operation.entryId] ??= []).add(
            JournalEntry(
              id: supplementId,
              parentId: operation.entryId,
              text: operation.text,
              createdAt: operation.recordedAt,
              createdOn: _utcCalendarDate(operation.recordedAt),
              status: EntryStatus.explanation,
            ),
          );
          (revisions[operation.entryId] ??= []).add(operation);
          applied.add(operation);
      }
    }

    final revisionIds = revisions.keys.toList()..sort();
    for (final entryId in revisionIds) {
      final entryRevisions = revisions[entryId]!;
      final actors = {for (final operation in entryRevisions) operation.actorId};
      if (actors.length > 1) {
        conflicts.add(
          JournalReplayConflict(
            JournalReplayConflictKind.competingActors,
            operation: entryRevisions.first,
            target: current[entryId],
            related: List.unmodifiable(entryRevisions.skip(1)),
          ),
        );
      }
    }

    final entries = <JournalEntry>[];
    for (final entry in base.entries) {
      entries.add(
        revisedBaseIds.contains(entry.id)
            ? entry.withStatus(EntryStatus.revised)
            : entry,
      );
      final extra = supplements[entry.id];
      if (extra != null) entries.addAll(extra);
    }
    entries.addAll(projectedCreates);

    return JournalReplayResult._(
      notebook: Notebook(
        volume: base.volume,
        volumeName: base.volumeName,
        entries: entries,
        sortOrder: base.sortOrder,
        archives: base.archives,
      ),
      appliedOperations: List.unmodifiable(applied),
      conflicts: List.unmodifiable(conflicts),
      appliedRevisionsByEntry: Map.unmodifiable({
        for (final entryId in revisionIds)
          entryId: List.unmodifiable(revisions[entryId]!),
      }),
    );
  }

  /// Canonical replay order. A total order because operation ids are unique.
  static int _compareOperations(JournalOperation a, JournalOperation b) {
    final byInstant = a.recordedAt.microsecondsSinceEpoch.compareTo(
      b.recordedAt.microsecondsSinceEpoch,
    );
    if (byInstant != 0) return byInstant;
    final byActor = a.actorId.compareTo(b.actorId);
    if (byActor != 0) return byActor;
    final bySequence = a.sequence.compareTo(b.sequence);
    if (bySequence != 0) return bySequence;
    return a.operationId.compareTo(b.operationId);
  }

  static JournalReplayConflict? _checkRevisionTarget(
    JournalReviseEntry operation, {
    required Map<String, JournalEntry> current,
    required Set<String> currentDuplicated,
    required Map<String, JournalEntry> archived,
    required Set<String> archivedDuplicated,
    required Set<String> journalCreateTargetIds,
    required Map<String, JournalEntry> projectedCreateById,
  }) {
    // A journal that creates an entry id cannot also revise it: v1 revisions
    // carry no due date, so the created entry's eligibility is unknowable.
    // This holds even when the create itself collided, because attaching the
    // text to an unrelated base entry would be content inference.
    //
    // Eligibility is otherwise judged against the base notebook only, so one
    // applied revision cannot make a later revision ineligible.
    if (journalCreateTargetIds.contains(operation.entryId)) {
      return JournalReplayConflict(
        JournalReplayConflictKind.createThenRevise,
        operation: operation,
        target: projectedCreateById[operation.entryId],
      );
    }
    final inCurrent = current.containsKey(operation.entryId);
    final inArchived = archived.containsKey(operation.entryId);
    if (currentDuplicated.contains(operation.entryId) ||
        archivedDuplicated.contains(operation.entryId) ||
        (inCurrent && inArchived)) {
      return JournalReplayConflict(
        JournalReplayConflictKind.ambiguousTarget,
        operation: operation,
        target: current[operation.entryId] ?? archived[operation.entryId],
      );
    }
    if (!inCurrent) {
      final archivedEntry = archived[operation.entryId];
      return JournalReplayConflict(
        archivedEntry == null
            ? JournalReplayConflictKind.missingTarget
            : JournalReplayConflictKind.archivedTarget,
        operation: operation,
        target: archivedEntry,
      );
    }
    final target = current[operation.entryId]!;
    if (target.status != EntryStatus.pending) {
      return JournalReplayConflict(
        JournalReplayConflictKind.ineligibleTarget,
        operation: operation,
        target: target,
      );
    }
    if (target.due == null) {
      return JournalReplayConflict(
        JournalReplayConflictKind.dueLessTarget,
        operation: operation,
        target: target,
      );
    }
    return null;
  }

  /// Mirrors [Notebook.revise]'s `volume-micros-index` id shape, but uses the
  /// operation id instead of the insertion index so the id does not depend on
  /// unrelated projected entries.
  static String _supplementId(int volume, JournalReviseEntry operation) =>
      '$volume-${operation.recordedAt.microsecondsSinceEpoch}-'
      '${operation.operationId}';

  static DateTime _civilDateOf(CivilDate date) =>
      DateTime.utc(date.year, date.month, date.day);

  static DateTime _utcCalendarDate(DateTime instant) =>
      DateTime.utc(instant.year, instant.month, instant.day);
}
