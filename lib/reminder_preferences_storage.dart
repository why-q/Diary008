import 'dart:convert';
import 'dart:io';

import 'reminder_preferences.dart';

Future<ReminderPreferences> readReminderPreferences(File file) async {
  if (!await file.exists()) return const ReminderPreferences();
  return ReminderPreferences.fromJson(
    jsonDecode(await file.readAsString()) as Map<String, dynamic>,
  );
}

Future<void> writeReminderPreferences(
  File file,
  ReminderPreferences preferences,
) async {
  if (preferences.hour < 0 ||
      preferences.hour > 23 ||
      preferences.minute < 0 ||
      preferences.minute > 59) {
    throw ArgumentError('提醒时间无效');
  }
  final temp = File('${file.path}.tmp');
  await temp.writeAsString(jsonEncode(preferences.toJson()), flush: true);
  await temp.rename(file.path);
}
