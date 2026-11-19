import '../notebook.dart';

/// Read side of the application boundary.
///
/// Filtering, sorting, and archive freezing stay in [Notebook]; this class
/// only names the reusable read operations for presentation clients.
class NotebookQueries {
  const NotebookQueries(this.notebook);

  final Notebook notebook;

  List<JournalEntry> currentEntries({
    required NotebookFilter filter,
    required DateTime now,
  }) => notebook.viewEntries(filter: filter, now: now);

  List<JournalEntry> archivedEntries({
    required int volume,
    NotebookFilter filter = NotebookFilter.all,
  }) => notebook.viewEntries(filter: filter, archivedVolume: volume);

  NotebookArchive? archive(int volume) {
    for (final archive in notebook.archives) {
      if (archive.volume == volume) return archive;
    }
    return null;
  }

  bool expired(DateTime now) => notebook.expired(now);
}
