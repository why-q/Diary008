import 'dart:convert';

import 'package:diary008/notebook.dart';
import 'package:diary008/notebook_backup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 22, 10);
  Notebook sample() {
    final original = Notebook.empty()
        .withVolumeName('旧卷')
        .add('原断言', DateTime(2026, 11, 1), now);
    return original
        .revise(original.entries.single.id, '解释', null, now)
        .startNewVolume('新卷', now)
        .add('当前断言', DateTime(2026, 12, 1), now)
        .withSortOrder(NotebookSortOrder.deadline);
  }

  test('backup retains archives, revisions, names and sorting', () {
    final book = sample();
    final restored = decodeNotebookBackup(jsonEncode(book.toJson()));
    expect(restored.toJson(), book.toJson());
  });

  test('rejects future versions rather than silently discarding fields', () {
    final data = sample().toJson()..['schemaVersion'] = 999;
    expect(() => decodeNotebookBackup(jsonEncode(data)), throwsFormatException);
  });

  test('missing modern history is rejected instead of restored as empty', () {
    final data = sample().toJson()..remove('archives');
    expect(() => decodeNotebookBackup(jsonEncode(data)), throwsFormatException);
  });

  test(
    'rejects broken links, duplicate volumes and missing pending deadlines',
    () {
      for (final mutation in <void Function(Map<String, dynamic>)>[
        (data) => (data['entries'] as List).first['parentId'] = 'missing',
        (data) =>
            (data['archives'] as List).add((data['archives'] as List).first),
        (data) => (data['entries'] as List).first['due'] = null,
        (data) =>
            (data['entries'] as List).add((data['entries'] as List).first),
      ]) {
        final data = sample().toJson();
        mutation(data);
        expect(
          () => decodeNotebookBackup(jsonEncode(data)),
          throwsFormatException,
        );
      }
    },
  );

  test('legacy backups migrate without inventing missing history', () {
    final restored = decodeNotebookBackup(
      jsonEncode({
        'volume': 4,
        'entries': [
          {
            'id': 'old',
            'text': '旧笔记',
            'createdAt': '2026-10-20T10:00:00+08:00',
            'due': '2026-11-01T00:00:00.000',
            'status': 'pending',
          },
        ],
      }),
    );
    expect(restored.volume, 4);
    expect(restored.entries.single.createdAt, DateTime.utc(2026, 10, 20, 2));
    expect(restored.entries.single.due, DateTime.utc(2026, 11, 1));
    expect(restored.archives, isEmpty);
  });

  test('rejects unrelated JSON and truncated backups', () {
    for (final text in ['{}', '[]', '{', '{"volume":1,"entries":null}']) {
      expect(() => decodeNotebookBackup(text), throwsFormatException);
    }
  });
}
