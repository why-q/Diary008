/// Narrow, pure equivalence check between a stored notebook snapshot and the
/// deterministic journal projection.
///
/// Isolated and unshipped on purpose: nothing in production calls it, and it
/// must not be wired into a read or write path until the M3 production gates
/// (atomic notebook+journal, backup/restore/wipe barriers) are met.
///
/// The check fails closed. A projection with any unresolved conflict is never
/// equivalent, because the snapshot cannot be shown to match the journal.
library;

import '../notebook.dart';
import 'journal_replay.dart';

/// True only when [snapshot] is structurally identical to [projection]'s
/// notebook and [projection] has no unresolved conflicts.
bool isSnapshotEquivalentToProjection(
  Notebook snapshot,
  JournalReplayResult projection,
) {
  if (projection.hasConflicts) return false;
  return _notebooksMatch(snapshot, projection.notebook);
}

bool _notebooksMatch(Notebook a, Notebook b) {
  if (a.volume != b.volume ||
      a.volumeName != b.volumeName ||
      a.sortOrder != b.sortOrder ||
      a.entries.length != b.entries.length ||
      a.archives.length != b.archives.length) {
    return false;
  }
  for (var i = 0; i < a.entries.length; i++) {
    if (!_entriesMatch(a.entries[i], b.entries[i])) return false;
  }
  for (var i = 0; i < a.archives.length; i++) {
    if (!_archivesMatch(a.archives[i], b.archives[i])) return false;
  }
  return true;
}

bool _archivesMatch(NotebookArchive a, NotebookArchive b) {
  if (a.volume != b.volume ||
      a.volumeName != b.volumeName ||
      a.invalidatedAt != b.invalidatedAt ||
      a.archivedAt != b.archivedAt ||
      a.reason != b.reason ||
      a.entries.length != b.entries.length ||
      a.failedEntryIds.length != b.failedEntryIds.length ||
      !a.failedEntryIds.containsAll(b.failedEntryIds)) {
    return false;
  }
  for (var i = 0; i < a.entries.length; i++) {
    if (!_entriesMatch(a.entries[i], b.entries[i])) return false;
  }
  return true;
}

bool _entriesMatch(JournalEntry a, JournalEntry b) =>
    a.id == b.id &&
    a.text == b.text &&
    a.createdAt == b.createdAt &&
    a.createdOn == b.createdOn &&
    a.due == b.due &&
    a.parentId == b.parentId &&
    a.status == b.status;
