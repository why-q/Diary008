import '../notebook.dart';
import '../notebook_repository.dart';

enum NotebookCommandOutcome { applied, unchanged, rejected, saveFailed }

enum NotebookCommandRejection { invalidArgument, invalidState }

/// Result of a command issued through [NotebookApplication].
///
/// [notebook] is the state the application holds after the attempt. It only
/// differs from the previous state when [applied] is true.
class NotebookCommandResult {
  const NotebookCommandResult._(
    this.outcome,
    this.notebook, {
    this.rejection,
    this.error,
    this.stackTrace,
  });

  factory NotebookCommandResult.applied(Notebook notebook) =>
      NotebookCommandResult._(NotebookCommandOutcome.applied, notebook);

  factory NotebookCommandResult.unchanged(Notebook notebook) =>
      NotebookCommandResult._(NotebookCommandOutcome.unchanged, notebook);

  factory NotebookCommandResult.rejected(
    NotebookCommandRejection rejection,
    Object error,
    StackTrace stackTrace,
    Notebook notebook,
  ) => NotebookCommandResult._(
    NotebookCommandOutcome.rejected,
    notebook,
    rejection: rejection,
    error: error,
    stackTrace: stackTrace,
  );

  factory NotebookCommandResult.saveFailed(
    Object error,
    StackTrace stackTrace,
    Notebook notebook,
  ) => NotebookCommandResult._(
    NotebookCommandOutcome.saveFailed,
    notebook,
    error: error,
    stackTrace: stackTrace,
  );

  final NotebookCommandOutcome outcome;
  final Notebook notebook;
  final NotebookCommandRejection? rejection;
  final Object? error;
  final StackTrace? stackTrace;

  bool get applied => outcome == NotebookCommandOutcome.applied;
  bool get unchanged => outcome == NotebookCommandOutcome.unchanged;
  bool get rejected => outcome == NotebookCommandOutcome.rejected;
  bool get saveFailed => outcome == NotebookCommandOutcome.saveFailed;
  bool get succeeded => applied || unchanged;
}

/// Application boundary for notebook mutations.
///
/// Every command delegates its rules to [Notebook] and persists only a
/// notebook that the domain accepted. The in-memory notebook advances after a
/// successful save, so a failed write leaves the previous state intact.
class NotebookApplication {
  NotebookApplication(this._repository, this._notebook);

  final NotebookRepository _repository;
  Notebook _notebook;

  Notebook get notebook => _notebook;

  /// Stores [notebook] as-is and adopts it, for whole-notebook replacements
  /// such as a backup restore or a full reset that bypass command rules.
  Future<void> replacePersisted(Notebook notebook) async {
    await _repository.save(notebook);
    _notebook = notebook;
  }

  Future<NotebookCommandResult> addEntry({
    required String text,
    required DateTime due,
    required DateTime now,
  }) => _run((book) => book.add(text, due, now));

  Future<NotebookCommandResult> reviseEntry({
    required String entryId,
    required String text,
    DateTime? due,
    required DateTime now,
  }) => _run((book) => book.revise(entryId, text, due, now));

  Future<NotebookCommandResult> fulfillEntry({
    required String entryId,
    required DateTime now,
  }) => _run((book) => book.fulfill(entryId, now));

  Future<NotebookCommandResult> reconcileExpiration({
    required DateTime now,
  }) async {
    if (!_notebook.expired(now)) {
      return NotebookCommandResult.unchanged(_notebook);
    }
    return _run((book) => book.reconcile(now));
  }

  Future<NotebookCommandResult> changeSortOrder(NotebookSortOrder order) {
    if (_notebook.sortOrder == order) {
      return Future.value(NotebookCommandResult.unchanged(_notebook));
    }
    return _run((book) => book.withSortOrder(order));
  }

  Future<NotebookCommandResult> renameVolume(String name) =>
      _run((book) => book.withVolumeName(name));

  Future<NotebookCommandResult> startNewVolume({
    required String name,
    required DateTime now,
  }) => _run((book) => book.startNewVolume(name, now));

  Future<NotebookCommandResult> deleteArchivedVolume(int volume) =>
      _run((book) => book.deleteArchivedVolume(volume));

  Future<NotebookCommandResult> _run(
    Notebook Function(Notebook book) mutate,
  ) async {
    final Notebook next;
    try {
      next = mutate(_notebook);
    } on ArgumentError catch (error, stack) {
      return NotebookCommandResult.rejected(
        NotebookCommandRejection.invalidArgument,
        error,
        stack,
        _notebook,
      );
    } on StateError catch (error, stack) {
      return NotebookCommandResult.rejected(
        NotebookCommandRejection.invalidState,
        error,
        stack,
        _notebook,
      );
    }
    try {
      await _repository.save(next);
    } catch (error, stack) {
      return NotebookCommandResult.saveFailed(error, stack, _notebook);
    }
    _notebook = next;
    return NotebookCommandResult.applied(next);
  }
}
