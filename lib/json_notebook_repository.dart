import 'dart:io';

import 'notebook.dart';
import 'notebook_repository.dart';
import 'notebook_storage.dart';

/// [NotebookRepository] backed by a single JSON file.
///
/// Delegates to [readNotebook] and [writeNotebook] so the file format,
/// atomic replacement, migration, and diagnostics stay unchanged.
class JsonNotebookRepository implements NotebookRepository {
  const JsonNotebookRepository(this.file);

  final File file;

  @override
  Future<Notebook> load({bool migrate = true}) =>
      readNotebook(file, migrate: migrate);

  @override
  Future<void> save(Notebook notebook) => writeNotebook(file, notebook);
}
