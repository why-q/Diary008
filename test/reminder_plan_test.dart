import 'dart:convert';

import 'package:diary008/notebook.dart';
import 'package:diary008/reminder_plan.dart';
import 'package:diary008/reminder_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  tzdata.initializeTimeZones();
  final shanghai = tz.getLocation('Asia/Shanghai');
  final losAngeles = tz.getLocation('America/Los_Angeles');
  final created = tz.TZDateTime(shanghai, 2026, 10, 21, 10);
  Notebook bookFor(int days) =>
      Notebook.empty().add('一段预言', DateTime(2026, 10, 21 + days), created);
  List<PlannedReminder> plans(Notebook book, {DateTime? now}) =>
      planReminders(book, now: now ?? created, location: shanghai);
  String day(PlannedReminder p) => '${p.at.year}-${p.at.month}-${p.at.day}';
  Notebook overlappingOriginsBook() => Notebook(
    volume: 1,
    entries: [
      JournalEntry(
        id: 'early-origin',
        text: '早期预言',
        createdAt: tz.TZDateTime(shanghai, 2026, 10, 17, 10),
        createdOn: DateTime(2026, 10, 17),
        due: DateTime(2027, 10, 21),
        status: EntryStatus.pending,
      ),
      JournalEntry(
        id: 'later-origin',
        text: '晚期预言',
        createdAt: created,
        createdOn: DateTime(2026, 10, 21),
        due: DateTime(2027, 10, 21),
        status: EntryStatus.pending,
      ),
    ],
  );

  test('same-day reminders are shared by every entry', () {
    final due = DateTime(2027, 10, 21);
    final book = Notebook(
      volume: 1,
      entries: List.generate(
        1000,
        (index) => JournalEntry(
          id: 'entry-$index',
          text: '共同的约定',
          createdAt: created,
          createdOn: created,
          due: due,
          status: EntryStatus.pending,
        ),
      ),
    );
    final expected = plans(bookFor(365));
    final result = plans(book);
    expect(result.map((p) => p.at.toUtc()), expected.map((p) => p.at.toUtc()));
    expect(result.map((p) => p.id), expected.map((p) => p.id));
    expect(
      result.every((p) => p.target.mode == ReminderMode.automatic),
      isTrue,
    );
  });
  test('deduplicates one local date from different entry origins', () {
    final result = plans(overlappingOriginsBook());
    final overlap = result.where((p) => day(p) == '2026-10-24').toList();
    expect(overlap, hasLength(1));
    expect(overlap.single.id, 20261024);
  });
  test('date ID stays stable when another origin is fulfilled', () {
    final book = overlappingOriginsBook();
    final before = plans(book).singleWhere((p) => day(p) == '2026-10-24');
    final after = plans(book.fulfill('early-origin', created))
        .singleWhere((p) => day(p) == '2026-10-24');
    expect(after.id, before.id);
    expect(after.id, 20261024);
  });
  test('three-day deadline reminds only on the due day at local nine', () {
    final result = plans(bookFor(3));
    expect(result.map((p) => p.at.toUtc()), [DateTime.utc(2026, 10, 24, 1)]);
    expect(result.single.at.hour, 9);
  });
  test('year-long cadence has spaced nodes plus final week and day', () {
    final result = plans(bookFor(365));
    final base = DateTime.utc(2026, 10, 21, 1);
    expect(result.map((p) => p.at.toUtc().difference(base).inDays), [
      1,
      3,
      7,
      14,
      30,
      60,
      90,
      180,
      270,
      358,
      365,
    ]);
    expect(result.map((p) => p.id).toSet().length, result.length);
  });
  test('past nodes are skipped and due-day overlap is deduplicated with stable IDs', () {
    final book = bookFor(14);
    final result = plans(book, now: DateTime.utc(2026, 10, 24, 2));
    expect(result.map((p) => p.at.toUtc()), [
      DateTime.utc(2026, 10, 28, 1),
      DateTime.utc(2026, 11, 4, 1),
    ]);
    final ids = {for (final p in plans(book)) day(p): p.id};
    expect(result.every((p) => ids[day(p)] == p.id), isTrue);
  });
  test('UTC instant and calendar origin survive restore and travel across year rollover', () {
    final start = tz.TZDateTime(shanghai, 2027, 1, 1, 2);
    final book = Notebook.empty().add('跨年预言', DateTime(2027, 1, 11), start);
    final restored = Notebook.fromJson(
      jsonDecode(jsonEncode(book.toJson())) as Map<String, dynamic>,
    );
    final east = planReminders(restored, now: start, location: shanghai);
    final west = planReminders(restored, now: start, location: losAngeles);
    expect(east.first.at.toUtc(), DateTime.utc(2027, 1, 2, 1));
    expect(west.first.at.toUtc(), DateTime.utc(2027, 1, 2, 17));
    expect(west.map(day), east.map(day));
    expect(west.map((p) => p.id), east.map((p) => p.id));
  });
  test(
    'daylight saving transition preserves nine oclock, not a fixed UTC offset',
    () {
      final book = bookFor(365);
      final result = planReminders(book, now: created, location: losAngeles);
      expect(result.every((p) => p.at.hour == 9), isTrue);
      expect(result.first.at.toUtc(), DateTime.utc(2026, 10, 22, 16));
      expect(
        result.firstWhere((p) => day(p) == '2026-11-4').at.toUtc(),
        DateTime.utc(2026, 11, 4, 17),
      );
    },
  );
  test(
    'daily reminder follows the custom local clock on empty and expired books',
    () {
      const preferences = ReminderPreferences(
        mode: ReminderMode.daily,
        hour: 21,
        minute: 15,
      );
      final beforeClock = planReminders(
        Notebook.empty(),
        now: tz.TZDateTime(shanghai, 2026, 10, 21, 21, 14),
        location: shanghai,
        preferences: preferences,
      ).single;
      expect(beforeClock.at, tz.TZDateTime(shanghai, 2026, 10, 21, 21, 15));
      expect(beforeClock.id, 1000000000);
      expect(beforeClock.target.mode, ReminderMode.daily);

      final atClock = planReminders(
        Notebook.empty(),
        now: tz.TZDateTime(shanghai, 2026, 10, 21, 21, 15),
        location: shanghai,
        preferences: preferences,
      ).single;
      expect(atClock.at, tz.TZDateTime(shanghai, 2026, 10, 22, 21, 15));

      final expired = planReminders(
        bookFor(3),
        now: tz.TZDateTime(shanghai, 2026, 10, 26, 8),
        location: shanghai,
        preferences: preferences,
      ).single;
      expect(expired.at, tz.TZDateTime(shanghai, 2026, 10, 26, 21, 15));
      final expiredAfterClock = planReminders(
        bookFor(3),
        now: tz.TZDateTime(shanghai, 2026, 10, 26, 21, 15),
        location: shanghai,
        preferences: preferences,
      ).single;
      expect(
        expiredAfterClock.at,
        tz.TZDateTime(shanghai, 2026, 10, 27, 21, 15),
      );
    },
  );
  test(
    'daily custom time remains local through the daylight-saving change',
    () {
      final result = planReminders(
        Notebook.empty(),
        now: DateTime.utc(2026, 11, 1, 16, 30),
        location: losAngeles,
        preferences: const ReminderPreferences(
          mode: ReminderMode.daily,
          hour: 9,
          minute: 30,
        ),
      ).single;
      expect(result.at.hour, 9);
      expect(result.at.minute, 30);
      expect(result.at.toUtc(), DateTime.utc(2026, 11, 1, 17, 30));
    },
  );
  test(
    'daily recurrence returns to the configured clock after a spring gap',
    () {
      const preferences = ReminderPreferences(
        mode: ReminderMode.daily,
        hour: 2,
        minute: 30,
      );
      final first = planReminders(
        Notebook.empty(),
        now: tz.TZDateTime(losAngeles, 2027, 3, 14),
        location: losAngeles,
        preferences: preferences,
      ).single;
      expect(first.at, tz.TZDateTime(losAngeles, 2027, 3, 14, 3, 30));
      final next = planReminders(
        Notebook.empty(),
        now: first.at.add(const Duration(seconds: 1)),
        location: losAngeles,
        preferences: preferences,
      ).single;
      expect(next.at, tz.TZDateTime(losAngeles, 2027, 3, 15, 2, 30));
    },
  );
  test('corrupt saved settings cannot silently change the reminder clock', () {
    for (final json in <Map<String, dynamic>>[
      {},
      {'mode': 'weekly', 'hour': 9, 'minute': 0},
      {'mode': 'daily', 'hour': 24, 'minute': 30},
      {'mode': 'daily', 'hour': -1, 'minute': 30},
      {'mode': 'daily', 'hour': 23, 'minute': 60},
      {'mode': 'daily', 'hour': 9, 'minute': '30'},
    ]) {
      expect(() => ReminderPreferences.fromJson(json), throwsFormatException);
    }
    final preferences = ReminderPreferences.fromJson({
      'mode': 'daily',
      'hour': 23,
      'minute': 59,
    });
    final next = planReminders(
      Notebook.empty(),
      now: tz.TZDateTime(shanghai, 2026, 10, 21, 23, 58),
      location: shanghai,
      preferences: preferences,
    ).single;
    expect(next.at, tz.TZDateTime(shanghai, 2026, 10, 21, 23, 59));
  });
  test('expiry uses supplied local zone, including local due-day evening', () {
    final book = bookFor(3);
    final evening = tz.TZDateTime(losAngeles, 2026, 10, 24, 8);
    expect(
      planReminders(book, now: evening, location: losAngeles).single.at,
      tz.TZDateTime(losAngeles, 2026, 10, 24, 9),
    );
    expect(
      planReminders(
        book,
        now: tz.TZDateTime(losAngeles, 2026, 10, 24, 10),
        location: losAngeles,
      ),
      isEmpty,
    );
    expect(
      planReminders(
        book,
        now: tz.TZDateTime(losAngeles, 2026, 10, 25),
        location: losAngeles,
      ),
      isEmpty,
    );
  });
  test('earliest current-volume deadline caps all plans and fulfillment releases cap', () {
    var book = bookFor(365).add('短期预言', DateTime(2026, 10, 24), created);
    final cutoff = tz.TZDateTime(shanghai, 2026, 10, 25);
    expect(plans(book).every((p) => p.at.isBefore(cutoff)), isTrue);
    expect(plans(book, now: cutoff), isEmpty);
    expect(plans(book.reconcile(cutoff), now: cutoff), isEmpty);
    book = book.fulfill(book.entries.last.id, created);
    expect(plans(book).last.at.toUtc(), DateTime.utc(2027, 10, 21, 1));
  });
  test('fulfilled and explained entries stop reminders; replacement gets its own cadence', () {
    final book = bookFor(365);
    final id = book.entries.first.id;
    expect(plans(book.fulfill(id, created)), isEmpty);
    expect(plans(book.revise(id, '解释', null, created)), isEmpty);
    final revisedAt = tz.TZDateTime(shanghai, 2026, 10, 22, 10);
    final revised = book.revise(id, '新的预言', DateTime(2026, 11, 21), revisedAt);
    final result = plans(revised, now: revisedAt);
    expect(
      result.every((p) => p.target.mode == ReminderMode.automatic),
      isTrue,
    );
    expect(result.first.at.toUtc(), DateTime.utc(2026, 10, 23, 1));
    final decoded = ReminderTarget.fromPayload(result.first.target.payload)!;
    expect(decoded.mode, result.first.target.mode);
  });
  test('reminder targets accept only the new notebook payload', () {
    expect(
      ReminderTarget.fromPayload('{"mode":"daily","kind":"notebook"}')?.mode,
      ReminderMode.daily,
    );
    expect(ReminderTarget.fromPayload('not-json'), isNull);
    expect(ReminderTarget.fromPayload('{}'), isNull);
    expect(
      ReminderTarget.fromPayload('{"kind":"other","mode":"daily"}'),
      isNull,
    );
    expect(
      ReminderTarget.fromPayload('{"kind":"notebook","mode":"unknown"}'),
      isNull,
    );
    expect(ReminderTarget.fromPayload('{"volume":1,"entryId":"old"}'), isNull);
  });
}
