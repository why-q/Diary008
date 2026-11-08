import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:diary008/notebook.dart';

void main() {
  final now = DateTime(2026, 10, 21, 12);
  Notebook fresh() =>
      Notebook.empty().add('我会考完雅思。', DateTime(2026, 10, 21), now);
  test(
    'deadline includes entire selected day and expiry clears whole volume',
    () {
      final book = fresh().add('另一段预言', DateTime(2026, 12, 1), now);
      expect(book.expired(DateTime(2026, 10, 21, 23, 59, 59)), isFalse);
      final reset = book.reconcile(DateTime(2026, 10, 22));
      expect(reset.entries, isEmpty);
      expect(reset.volume, 2);
      expect(reset.reconcile(DateTime(2026, 10, 23)).volume, 2);
    },
  );
  test('fulfilled and explained assertions do not expire', () {
    final book = fresh();
    expect(
      book.fulfill(book.entries.first.id, now).expired(DateTime(2030)),
      isFalse,
    );
    final explained = book.revise(book.entries.first.id, '我调整了计划。', null, now);
    expect(explained.entries.first.status, EntryStatus.revised);
    expect(explained.entries.last.status, EntryStatus.explanation);
    expect(explained.expired(DateTime(2030)), isFalse);
  });
  test('fulfillment commits once and cannot be repeated', () {
    final book = fresh();
    final id = book.entries.single.id;
    final completed = book.fulfill(id, now);
    expect(completed.entries.single.status, EntryStatus.fulfilled);
    expect(
      completed.viewEntries(filter: NotebookFilter.pending, now: now),
      isEmpty,
    );
    expect(() => completed.fulfill(id, now), throwsStateError);
  });
  test('replacement retains original and has its own expiry', () {
    final book = fresh();
    final revised = book.revise(
      book.entries.first.id,
      '我会重新备考。',
      DateTime(2026, 11, 21),
      now,
    );
    expect(book.entries.first.status, EntryStatus.pending);
    expect(revised.entries.last.parentId, book.entries.first.id);
    expect(revised.expired(DateTime(2026, 10, 22)), isFalse);
    expect(revised.expired(DateTime(2026, 11, 22)), isTrue);
    final copy = Notebook.fromJson(
      jsonDecode(jsonEncode(revised.toJson())) as Map<String, dynamic>,
    );
    expect(copy.toJson(), revised.toJson());
  });
  test('expired assertions cannot be fulfilled or revised', () {
    final book = fresh();
    expect(
      () => book.fulfill(book.entries.first.id, DateTime(2026, 10, 22)),
      throwsStateError,
    );
    expect(
      () => book.revise(
        book.entries.first.id,
        '解释',
        null,
        DateTime(2026, 10, 22),
      ),
      throwsStateError,
    );
  });
  test('calendar shortcuts clamp month and leap year dates', () {
    expect(
      calendarOffset(DateTime(2026, 1, 31), months: 1),
      DateTime(2026, 2, 28),
    );
    expect(
      calendarOffset(DateTime(2028, 2, 29), years: 1),
      DateTime(2029, 2, 28),
    );
    expect(
      calendarOffset(DateTime(2026, 12, 21), months: 1),
      DateTime(2027, 1, 21),
    );
  });
  test('deadline sorting moves whole revision chains without changing writing order', () {
    var book = Notebook.empty()
        .add('原断言', DateTime(2026, 11, 1), now)
        .add('较近的独立断言', DateTime(2026, 11, 2), now)
        .add('同日的独立断言', DateTime(2026, 11, 2), now);
    final root = book.entries.first.id;
    book = book.revise(root, '替代断言', DateTime(2026, 12, 1), now);
    final replacement = book.entries.firstWhere((e) => e.parentId == root).id;
    book = book.revise(replacement, '再次替代', DateTime(2026, 11, 3), now);
    final writingOrder = book.entries.map((e) => e.text).toList();
    expect(writingOrder, ['原断言', '替代断言', '再次替代', '较近的独立断言', '同日的独立断言']);
    final sorted = book.withSortOrder(NotebookSortOrder.deadline);
    expect(sorted.displayEntries.map((e) => e.text), [
      '较近的独立断言',
      '同日的独立断言',
      '原断言',
      '替代断言',
      '再次替代',
    ]);
    expect(sorted.entries.map((e) => e.text), writingOrder);
    expect(
      sorted
          .withSortOrder(NotebookSortOrder.writing)
          .displayEntries
          .map((e) => e.text),
      writingOrder,
    );
  });
  test('fulfilled and explained groups follow pending groups in original group order', () {
    var book = Notebook.empty()
        .add('已履行', DateTime(2026, 11, 5), now)
        .add('待解释', DateTime(2026, 11, 1), now)
        .add('待履行', DateTime(2026, 11, 9), now);
    final explainedId = book.entries[1].id;
    book = book
        .fulfill(book.entries.first.id, now)
        .revise(explainedId, '这是原因', null, now)
        .withSortOrder(NotebookSortOrder.deadline);
    expect(book.displayEntries.map((e) => e.text), [
      '待履行',
      '已履行',
      '待解释',
      '这是原因',
    ]);
  });
  test(
    'sort preference survives serialization, mutations, and volume reset',
    () {
      var book = fresh().withSortOrder(NotebookSortOrder.deadline);
      book = Notebook.fromJson(
        jsonDecode(jsonEncode(book.toJson())) as Map<String, dynamic>,
      );
      expect(book.sortOrder, NotebookSortOrder.deadline);
      expect(
        book.add('新增', DateTime(2026, 12, 1), now).sortOrder,
        NotebookSortOrder.deadline,
      );
      expect(
        book.fulfill(book.entries.first.id, now).sortOrder,
        NotebookSortOrder.deadline,
      );
      expect(
        book.revise(book.entries.first.id, '解释', null, now).sortOrder,
        NotebookSortOrder.deadline,
      );
      final reset = book.reconcile(DateTime(2026, 10, 22));
      expect(reset.entries, isEmpty);
      expect(reset.sortOrder, NotebookSortOrder.deadline);
    },
  );
  test(
    'existing notebook JSON defaults to writing order without changing entries',
    () {
      final legacy = fresh().toJson()..remove('sortOrder');
      final restored = Notebook.fromJson(legacy);
      expect(restored.sortOrder, NotebookSortOrder.writing);
      expect(restored.displayEntries.single.text, '我会考完雅思。');
    },
  );
}
