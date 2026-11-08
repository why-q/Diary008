import 'dart:convert';

import 'package:diary008/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 21, 12);
  test(
    'legacy notebook migrates without renumbering or losing revision links',
    () {
      var book = Notebook(
        volume: 7,
        entries: [],
      ).add('原文', DateTime(2026, 11, 1), now);
      book = book.revise(
        book.entries.first.id,
        '补充',
        DateTime(2026, 12, 1),
        now,
      );
      final legacy = book.toJson()
        ..remove('archives')
        ..remove('schemaVersion')
        ..remove('sortOrder');
      final restored = Notebook.fromJson(legacy);
      expect(restored.volume, 7);
      expect(restored.archives, isEmpty);
      expect(restored.sortOrder, NotebookSortOrder.writing);
      expect(
        restored.entries.map((e) => e.toJson()),
        book.entries.map((e) => e.toJson()),
      );
    },
  );
  test('offline expiry archives complete history and attributes only earliest failures', () {
    var book = Notebook.empty()
        .add('到期一', DateTime(2026, 10, 21), now)
        .add('到期二', DateTime(2026, 10, 21), now)
        .add('后来才到期', DateTime(2026, 10, 24), now)
        .add('已履行', DateTime(2026, 10, 21), now);
    book = book
        .fulfill(book.entries.last.id, now)
        .withSortOrder(NotebookSortOrder.deadline);
    final detected = DateTime(2026, 11, 20);
    final next = book.reconcile(detected);
    expect(next.volume, 2);
    expect(next.entries, isEmpty);
    expect(next.sortOrder, NotebookSortOrder.deadline);
    final archive = next.archives.single;
    expect(archive.volume, 1);
    expect(archive.invalidatedAt, DateTime(2026, 10, 22));
    expect(archive.archivedAt, detected);
    expect(archive.reason, ArchiveReason.missedDeadline);
    expect(archive.failedEntryIds, {book.entries[0].id, book.entries[1].id});
    expect(
      archive.entries.map((e) => e.toJson()),
      book.entries.map((e) => e.toJson()),
    );
    expect(next.reconcile(detected).archives.length, 1);
    expect(() => archive.entries.clear(), throwsUnsupportedError);
    expect(() => archive.failedEntryIds.clear(), throwsUnsupportedError);
    expect(
      () => next.fulfill(archive.entries.first.id, detected),
      throwsStateError,
    );
    final restored = Notebook.fromJson(
      jsonDecode(jsonEncode(next.toJson())) as Map<String, dynamic>,
    );
    expect(restored.toJson(), next.toJson());
    final third = next
        .add('第二卷的断言', DateTime(2026, 11, 21), detected)
        .reconcile(DateTime(2026, 11, 22));
    expect(third.volume, 3);
    expect(third.archives.map((a) => a.volume), [1, 2]);
    expect(third.archives.first.toJson(), archive.toJson());
  });
  test('filter matches whole chains across pending, fulfilled and revised membership', () {
    var book = Notebook.empty()
        .add('原断言', DateTime(2026, 11, 1), now)
        .add('独立待履行', DateTime(2026, 10, 25), now)
        .add('履行记录', DateTime(2026, 11, 1), now)
        .add('解释原文', DateTime(2026, 11, 1), now);
    final root = book.entries.first.id;
    final fulfilled = book.entries[2].id;
    final explained = book.entries.last.id;
    book = book.revise(root, '新断言', DateTime(2026, 11, 20), now);
    final replacement = book.entries.firstWhere((e) => e.parentId == root).id;
    book = book
        .revise(replacement, '再写断言', DateTime(2026, 11, 5), now)
        .fulfill(fulfilled, now)
        .revise(explained, '解释原因', null, now);
    List<String> texts(NotebookFilter filter, Notebook b) =>
        b.viewEntries(filter: filter, now: now).map((e) => e.text).toList();
    expect(texts(NotebookFilter.pending, book), [
      '原断言',
      '新断言',
      '再写断言',
      '独立待履行',
    ]);
    expect(texts(NotebookFilter.unfulfilled, book), [
      '原断言',
      '新断言',
      '再写断言',
      '解释原文',
      '解释原因',
    ]);
    expect(texts(NotebookFilter.fulfilled, book), ['履行记录']);
    final sorted = book.withSortOrder(NotebookSortOrder.deadline);
    expect(texts(NotebookFilter.pending, sorted), [
      '独立待履行',
      '原断言',
      '新断言',
      '再写断言',
    ]);
    final tailId = book.entries.firstWhere((e) => e.text == '再写断言').id;
    final completed = book.fulfill(tailId, now);
    expect(texts(NotebookFilter.fulfilled, completed), [
      '原断言',
      '新断言',
      '再写断言',
      '履行记录',
    ]);
    expect(texts(NotebookFilter.pending, completed), ['独立待履行']);
    expect(book.entries.first.status, EntryStatus.revised);
  });
  test(
    'historical filters freeze at invalidation rather than current device time',
    () {
      final book = Notebook.empty()
          .add('失败', DateTime(2026, 10, 21), now)
          .add('随卷封存', DateTime(2026, 10, 25), now)
          .reconcile(DateTime(2026, 12, 1));
      final future = DateTime(2030);
      expect(
        book
            .viewEntries(
              archivedVolume: 1,
              filter: NotebookFilter.pending,
              now: future,
            )
            .map((e) => e.text),
        ['随卷封存'],
      );
      expect(
        book
            .viewEntries(
              archivedVolume: 1,
              filter: NotebookFilter.unfulfilled,
              now: future,
            )
            .map((e) => e.text),
        ['失败'],
      );
      expect(
        book.viewEntries(filter: NotebookFilter.all, now: future),
        isEmpty,
      );
      expect(book.archives.single.entries.last.status, EntryStatus.pending);
    },
  );
}
