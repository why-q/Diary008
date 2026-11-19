import 'notebook.dart';

/// Storage boundary for the [Notebook] domain model.
///
/// Implementations decide where and how the notebook is persisted. The
/// contract deliberately avoids `dart:io` and Flutter so that in-memory,
/// remote, or platform-specific stores can implement it.
abstract class NotebookRepository {
  /// Reads the stored notebook.
  ///
  /// With [migrate] set, an outdated stored schema may be upgraded in place.
  /// With it cleared, the read must not modify the stored data.
  Future<Notebook> load({bool migrate = true});

  /// Replaces the stored notebook with [notebook].
  Future<void> save(Notebook notebook);
}
