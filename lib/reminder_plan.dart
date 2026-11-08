import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

import 'notebook.dart';
import 'reminder_preferences.dart';

class ReminderTarget {
  const ReminderTarget({required this.mode});

  final ReminderMode mode;

  String get payload => jsonEncode({'kind': 'notebook', 'mode': mode.name});

  static ReminderTarget? fromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final value = jsonDecode(payload);
      if (value is! Map<String, dynamic> || value['kind'] != 'notebook') {
        return null;
      }
      final mode = switch (value['mode']) {
        'automatic' => ReminderMode.automatic,
        'daily' => ReminderMode.daily,
        _ => null,
      };
      return mode == null ? null : ReminderTarget(mode: mode);
    } on FormatException {
      return null;
    }
  }
}

class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.at,
    required this.target,
  });

  final int id;
  final tz.TZDateTime at;
  final ReminderTarget target;
}

List<PlannedReminder> planReminders(
  Notebook book, {
  required DateTime now,
  required tz.Location location,
  ReminderPreferences preferences = const ReminderPreferences(),
}) {
  if (preferences.mode == ReminderMode.daily) {
    final localNow = tz.TZDateTime.fromMillisecondsSinceEpoch(
      location,
      now.millisecondsSinceEpoch,
    );
    var at = tz.TZDateTime(
      location,
      localNow.year,
      localNow.month,
      localNow.day,
      preferences.hour,
      preferences.minute,
    );
    if (!at.isAfter(now)) {
      at = tz.TZDateTime(
        location,
        localNow.year,
        localNow.month,
        localNow.day + 1,
        preferences.hour,
        preferences.minute,
      );
    }
    return List<PlannedReminder>.unmodifiable([
      PlannedReminder(
        id: 1000000000,
        at: at,
        target: const ReminderTarget(mode: ReminderMode.daily),
      ),
    ]);
  }

  tz.TZDateTime? cutoff;
  for (final entry in book.entries) {
    if (entry.status != EntryStatus.pending) continue;
    final due = entry.due!;
    final entryCutoff = tz.TZDateTime(
      location,
      due.year,
      due.month,
      due.day + 1,
    );
    if (cutoff == null || entryCutoff.isBefore(cutoff)) cutoff = entryCutoff;
  }
  final effectiveCutoff = cutoff;
  if (effectiveCutoff == null || !now.isBefore(effectiveCutoff)) {
    return const [];
  }

  final dates = <int, tz.TZDateTime>{};
  void include(tz.TZDateTime at) {
    if (!at.isAfter(now) || !at.isBefore(effectiveCutoff)) return;
    final dateId = at.year * 10000 + at.month * 100 + at.day;
    if (!dates.containsKey(dateId)) dates[dateId] = at;
  }

  for (final entry in book.entries) {
    if (entry.status != EntryStatus.pending) continue;
    final created = entry.createdOn;
    final due = entry.due!;
    final dueDay = DateTime.utc(due.year, due.month, due.day);
    final duration = dueDay
        .difference(DateTime.utc(created.year, created.month, created.day))
        .inDays;
    include(tz.TZDateTime(location, due.year, due.month, due.day, 9));
    if (duration > 7) {
      for (final offset in const [1, 3, 7, 14, 30, 60, 90, 180, 270]) {
        if (offset > duration) continue;
        include(
          tz.TZDateTime(
            location,
            created.year,
            created.month,
            created.day + offset,
            9,
          ),
        );
      }
    }
    if (duration > 30) {
      include(tz.TZDateTime(location, due.year, due.month, due.day - 7, 9));
    }
  }

  final ids = dates.keys.toList()..sort();
  return List<PlannedReminder>.unmodifiable([
    for (final id in ids)
      PlannedReminder(
        id: id,
        at: dates[id]!,
        target: const ReminderTarget(mode: ReminderMode.automatic),
      ),
  ]);
}
