import 'dart:convert';

import 'package:diary008/notebook.dart';
import 'package:diary008/reminder_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  final now = DateTime(2026, 10, 21, 12);
  Notebook named() => Notebook.empty()
      .withVolumeName('  晨间计划  ')
      .add('原断言', DateTime(2026, 11, 1), now)
      .add('独立断言', DateTime(2026, 11, 2), now);
  Notebook restore(Notebook book) => Notebook.fromJson(
    jsonDecode(jsonEncode(book.toJson())) as Map<String, dynamic>,
  );

  test('manual closure preserves linked history without inventing a missed deadline', () {
    var book = named().withSortOrder(NotebookSortOrder.deadline);
    book = book.revise(
      book.entries.first.id,
      '替代断言',
      DateTime(2026, 11, 3),
      now,
    );
    final next = restore(book.startNewVolume('  阅读  ', now));
    expect(next.volume, 2);
    expect(next.volumeName, '阅读');
    expect(next.entries, isEmpty);
    expect(next.sortOrder, NotebookSortOrder.deadline);
    final old = next.archives.single;
    expect(old.volume, 1);
    expect(old.volumeName, '晨间计划');
    expect(old.reason, ArchiveReason.manualClosure);
    expect(old.invalidatedAt, isNull);
    expect(old.archivedAt.isAtSameMomentAs(now), isTrue);
    expect(old.failedEntryIds, isEmpty);
    expect(
      old.entries.map((e) => e.toJson()),
      book.entries.map((e) => e.toJson()),
    );
    expect(() => next.fulfill(old.entries.first.id, now), throwsStateError);
    expect(
      () => next.revise(old.entries.first.id, '不应改写', null, now),
      throwsStateError,
    );
    expect(
      next
          .viewEntries(
            archivedVolume: 1,
            filter: NotebookFilter.pending,
            now: DateTime(2030),
          )
          .map((e) => e.id)
          .toSet(),
      old.entries.map((e) => e.id).toSet(),
    );
    expect(
      next
          .viewEntries(archivedVolume: 1, filter: NotebookFilter.unfulfilled)
          .map((e) => e.text),
      ['原断言', '替代断言'],
    );
  });

  test('name survives ordinary mutations while rollover preserves historical names', () {
    var book = named();
    book = book.fulfill(book.entries.last.id, now);
    book = book.revise(
      book.entries.first.id,
      '下一条',
      DateTime(2026, 11, 4),
      now,
    );
    book = restore(book.withSortOrder(NotebookSortOrder.deadline));
    expect(book.volumeName, '晨间计划');
    final second = book.startNewVolume('第二个名字', now);
    final third = second.startNewVolume('', now);
    expect(third.volume, 3);
    expect(third.volumeName, isEmpty);
    expect(third.archives.map((a) => a.volumeName), ['晨间计划', '第二个名字']);
    final renamed = restore(third.withVolumeName('新页'));
    expect(
      renamed.archives.map((a) => a.toJson()),
      third.archives.map((a) => a.toJson()),
    );
    expect(renamed.withVolumeName('  ').volumeName, isEmpty);
  });

  test(
    'automatic expiry preserves old name but opens an unnamed writable volume',
    () {
      final book = named();
      final expired = DateTime(2026, 11, 2);
      expect(() => book.startNewVolume('不能绕过逾期', expired), throwsStateError);
      final next = restore(book.reconcile(expired));
      expect(next.volumeName, isEmpty);
      expect(next.archives.single.volumeName, '晨间计划');
      expect(next.archives.single.reason, ArchiveReason.missedDeadline);
      expect(next.archives.single.invalidatedAt, isNotNull);
      expect(next.archives.single.failedEntryIds, {book.entries.first.id});
      expect(next.archives.single.entries.map((e) => e.status), [
        EntryStatus.pending,
        EntryStatus.pending,
      ]);
    },
  );

  test(
    'unnamed legacy current and missed-deadline archives retain their records',
    () {
      final legacy = Notebook.empty()
          .add('旧断言', DateTime(2026, 10, 21), now)
          .reconcile(DateTime(2026, 10, 22))
          .toJson();
      legacy.remove('volumeName');
      legacy['schemaVersion'] = 3;
      for (final archive in legacy['archives'] as List) {
        (archive as Map<String, dynamic>).remove('volumeName');
      }
      final loaded = Notebook.fromJson(legacy);
      expect(loaded.volumeName, isEmpty);
      expect(loaded.archives.single.volumeName, isEmpty);
      expect(loaded.archives.single.entries.single.text, '旧断言');
      expect(loaded.archives.single.reason, ArchiveReason.missedDeadline);
      expect(loaded.archives.single.failedEntryIds, {
        loaded.archives.single.entries.single.id,
      });
      final renamed = restore(loaded.withVolumeName('继续'));
      expect(renamed.volume, 2);
      expect(
        renamed.archives.single.entries.single.id,
        loaded.archives.single.entries.single.id,
      );
    },
  );

  test('manual archives preserve deadline sorting and pending chains after original due dates', () {
    var book = named();
    book = book.revise(
      book.entries.first.id,
      '最晚的替代',
      DateTime(2026, 11, 10),
      now,
    );
    final next = restore(
      book.startNewVolume('', now).withSortOrder(NotebookSortOrder.deadline),
    );
    expect(
      next
          .viewEntries(
            archivedVolume: 1,
            filter: NotebookFilter.pending,
            now: DateTime(2030),
          )
          .map((e) => e.text),
      ['独立断言', '原断言', '最晚的替代'],
    );
    expect(
      next.viewEntries(archivedVolume: 1, filter: NotebookFilter.fulfilled),
      isEmpty,
    );
  });

  test(
    'manual closure and renaming never keep plans from an archived volume',
    () {
      tzdata.initializeTimeZones();
      final location = tz.getLocation('Asia/Shanghai');
      final book = named();
      final before = planReminders(book, now: now, location: location);
      final renamed = planReminders(
        book.withVolumeName('新卷名'),
        now: now,
        location: location,
      );
      expect(renamed.map((p) => p.id), before.map((p) => p.id));
      final next = book.startNewVolume('新卷', now);
      expect(planReminders(next, now: now, location: location), isEmpty);
      final added = next.add('仅提醒这一条', DateTime(2026, 11, 5), now);
      final plans = planReminders(added, now: now, location: location);
      expect(plans.map((p) => p.at), [
        tz.TZDateTime(location, 2026, 10, 22, 9),
        tz.TZDateTime(location, 2026, 10, 24, 9),
        tz.TZDateTime(location, 2026, 10, 28, 9),
        tz.TZDateTime(location, 2026, 11, 4, 9),
        tz.TZDateTime(location, 2026, 11, 5, 9),
      ]);
    },
  );

  test(
    'deleting volume 1 shifts later volumes without rewriting entry ids',
    () {
      final first = named()
          .startNewVolume('第二卷', now)
          .add('第二卷断言', DateTime(2026, 11, 8), now);
      final book = first
          .startNewVolume('正在写', now)
          .add('当前断言', DateTime(2026, 11, 9), now);
      final kept = book.archives.last;
      final next = restore(book.deleteArchivedVolume(1));
      expect(next.volume, 2);
      expect(next.volumeName, '正在写');
      expect(next.sortOrder, book.sortOrder);
      expect(next.entries.map((e) => e.toJson()), [
        book.entries.single.toJson(),
      ]);
      expect(next.entries.single.id, book.entries.single.id);
      expect(next.entries.single.id, startsWith('3-'));
      expect(next.archives, hasLength(1));
      final shifted = next.archives.single;
      expect(shifted.volume, 1);
      expect(shifted.volumeName, '第二卷');
      expect(shifted.reason, kept.reason);
      expect(shifted.invalidatedAt, kept.invalidatedAt);
      expect(shifted.archivedAt.isAtSameMomentAs(kept.archivedAt), isTrue);
      expect(shifted.failedEntryIds, kept.failedEntryIds);
      expect(shifted.entries.map((e) => e.toJson()), [
        kept.entries.single.toJson(),
      ]);
      expect(shifted.entries.single.id, startsWith('2-'));
      expect(shifted.entries.single.parentId, kept.entries.single.parentId);
      expect(next.viewEntries(archivedVolume: 1).map((e) => e.id), [
        kept.entries.single.id,
      ]);
    },
  );

  test('deleting a middle archive keeps earlier records and decrements the current volume', () {
    final laterNow = DateTime(2026, 11, 2, 12);
    final book = named()
        .reconcile(DateTime(2026, 11, 2))
        .withVolumeName('第二卷')
        .add('第二卷断言', DateTime(2026, 11, 8), laterNow)
        .startNewVolume('第三卷', laterNow)
        .add('第三卷断言', DateTime(2026, 11, 9), laterNow)
        .startNewVolume('正在写', laterNow)
        .add('当前断言', DateTime(2026, 11, 10), laterNow);
    final earlier = book.archives.first;
    final shiftedSource = book.archives.last;
    final next = restore(book.deleteArchivedVolume(2));
    expect(next.volume, 3);
    expect(next.volumeName, '正在写');
    expect(next.entries.single.id, book.entries.single.id);
    expect(next.entries.single.id, startsWith('4-'));
    expect(next.entries.single.parentId, book.entries.single.parentId);
    expect(next.archives.map((a) => a.volume), [1, 2]);
    final kept = next.archives.first;
    expect(kept.volumeName, earlier.volumeName);
    expect(kept.reason, ArchiveReason.missedDeadline);
    expect(
      kept.invalidatedAt!.isAtSameMomentAs(earlier.invalidatedAt!),
      isTrue,
    );
    expect(kept.archivedAt.isAtSameMomentAs(earlier.archivedAt), isTrue);
    expect(kept.failedEntryIds, earlier.failedEntryIds);
    expect(
      kept.entries.map((e) => e.toJson()),
      earlier.entries.map((e) => e.toJson()),
    );
    expect(
      kept.entries.map((e) => e.parentId),
      earlier.entries.map((e) => e.parentId),
    );
    final shifted = next.archives.last;
    expect(shifted.volumeName, '第三卷');
    expect(shifted.entries.single.id, shiftedSource.entries.single.id);
    expect(shifted.entries.single.id, startsWith('3-'));
    expect(
      shifted.entries.single.parentId,
      shiftedSource.entries.single.parentId,
    );
    expect(
      next.archives.expand((a) => a.entries).map((e) => e.text),
      isNot(contains('第二卷断言')),
    );
  });

  test('only an existing archived volume can be deleted', () {
    final book = named().startNewVolume('第二卷', now);
    expect(() => book.deleteArchivedVolume(book.volume), throwsStateError);
    expect(() => book.deleteArchivedVolume(9), throwsStateError);
    expect(book.volume, 2);
    expect(book.archives.single.volume, 1);
  });
}
