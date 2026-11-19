import 'dart:convert';
import 'dart:io';

import 'package:diary008/json_notebook_repository.dart';
import 'package:diary008/notebook.dart';
import 'package:diary008/notebook_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late File file;
  late NotebookRepository repository;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('diary-repository-');
    file = File('${dir.path}/notebook.json');
    repository = JsonNotebookRepository(file);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('missing file loads an empty notebook without creating one', () async {
    final book = await repository.load();

    expect(book.volume, 1);
    expect(book.entries, isEmpty);
    expect(await file.exists(), isFalse);
  });

  test('save then load round trips the notebook through the file', () async {
    final now = DateTime(2026, 10, 21, 12);
    final book = Notebook.empty().add('我会考完雅思。', DateTime(2026, 11, 21), now);

    await repository.save(book);
    final loaded = await repository.load();

    expect(await file.exists(), isTrue);
    expect(loaded.toJson(), book.toJson());
    expect(loaded.entries.single.text, '我会考完雅思。');
  });

  test('legacy file migrates once and persists the current schema', () async {
    final created = DateTime(2026, 10, 21, 17, 30);
    await file.writeAsString(
      jsonEncode({
        'schemaVersion': 2,
        'volume': 7,
        'sortOrder': 'deadline',
        'archives': [],
        'entries': [
          {
            'id': 'legacy',
            'text': '原有笔记',
            'createdAt': created.toIso8601String(),
            'due': '2026-11-21T00:00:00.000',
            'parentId': null,
            'status': 'pending',
          },
        ],
      }),
    );

    final book = await repository.load();
    final saved = jsonDecode(await file.readAsString()) as Map<String, dynamic>;

    expect(book.volume, 7);
    expect(book.sortOrder, NotebookSortOrder.deadline);
    expect(saved['schemaVersion'], Notebook.storageVersion);
    expect(saved['entries'][0]['due'], '2026-11-21');
    expect(saved['entries'][0]['createdOn'], '2026-10-21');
    expect(
      DateTime.parse(saved['entries'][0]['createdAt'] as String).isUtc,
      isTrue,
    );
  });

  test('non-migrating load leaves legacy bytes untouched', () async {
    final legacy = jsonEncode({
      'schemaVersion': 2,
      'volume': 4,
      'entries': <Object>[],
    });
    await file.writeAsString(legacy);

    final book = await repository.load(migrate: false);

    expect(book.volume, 4);
    expect(await file.readAsString(), legacy);
  });

  test('corrupt JSON throws and leaves the file unchanged', () async {
    const corrupt = '{"volume": 3, "entries": [';
    await file.writeAsString(corrupt);

    await expectLater(repository.load(), throwsFormatException);

    expect(await file.readAsString(), corrupt);
  });
}
