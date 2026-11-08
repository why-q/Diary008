import 'dart:convert';
import 'dart:io';

import 'package:diary008/notebook.dart';
import 'package:diary008/notebook_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late File file;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('diary-storage-');
    file = File('${dir.path}/notebook.json');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  test('legacy local timestamps migrate once to instants and calendar-only due dates', () async {
    final created = DateTime(2026, 10, 21, 17, 30);
    final legacy = {
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
    };
    await file.writeAsString(jsonEncode(legacy));
    final book = await readNotebook(file);
    final saved = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final timestamp = DateTime.parse(
      saved['entries'][0]['createdAt'] as String,
    );
    expect(timestamp.isUtc, isTrue);
    expect(timestamp.isAtSameMomentAs(created), isTrue);
    expect(saved['entries'][0]['due'], '2026-11-21');
    expect(saved['entries'][0]['createdOn'], '2026-10-21');
    expect(book.volume, 7);
    expect(book.sortOrder, NotebookSortOrder.deadline);
    final restored = await readNotebook(file);
    expect(restored.toJson(), book.toJson());
  });
  test('explicit offsets retain instants and legacy date fields retain selected civil day', () {
    final entry = JournalEntry.fromJson({
      'id': 'offset',
      'text': '跨区',
      'createdAt': '2026-10-21T23:30:00+08:00',
      'createdOn': '2026-10-21',
      'due': '2026-11-21T00:00:00.000+08:00',
      'status': 'pending',
      'parentId': null,
    });
    final json = entry.toJson();
    expect(
      DateTime.parse(json['createdAt'] as String),
      DateTime.utc(2026, 10, 21, 15, 30),
    );
    expect(json['createdOn'], '2026-10-21');
    expect(json['due'], '2026-11-21');
    expect(entry.due!.year, 2026);
    expect(entry.due!.month, 11);
    expect(entry.due!.day, 21);
  });
  test('read-only background reads never rewrite the notebook', () async {
    final legacy = jsonEncode({'volume': 4, 'entries': []});
    await file.writeAsString(legacy);
    final book = await readNotebook(file, migrate: false);
    expect(book.volume, 4);
    expect(await file.readAsString(), legacy);
  });
}
