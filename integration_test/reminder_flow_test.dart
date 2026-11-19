import 'dart:convert';
import 'dart:io';

import 'package:diary008/main.dart';
import 'package:diary008/notebook.dart';
import 'package:diary008/reminder_plan.dart';
import 'package:diary008/reminder_preferences.dart';
import 'package:diary008/reminder_preferences_storage.dart';
import 'package:diary008/reminder_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:path_provider/path_provider.dart';

import 'support/notebook_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'daily summaries replace entry alarms and daily mode survives reload',
    (tester) async {
      final notebook = await snapshotNotebook();
      final file = notebook.file;
      final support = await getApplicationSupportDirectory();
      final preferences = await FileSnapshot.capture(
        File('${support.path}/reminder_preferences.json'),
      );
      final preferencesFile = preferences.file;
      final reminders = ReminderService.instance;
      final plugin = FlutterLocalNotificationsPlugin();
      final now = DateTime.now();
      final entries = List.generate(
        1000,
        (i) => JournalEntry(
          id: 'summary-$i',
          text: '共同约定 ${i + 1}',
          createdAt: now,
          createdOn: now,
          due: now.add(const Duration(days: 365)),
          status: EntryStatus.pending,
        ),
      );
      final old = Notebook.empty()
          .add('旧卷的记录', now.add(const Duration(days: 365)), now)
          .startNewVolume('', now);
      final book = Notebook(
        volume: 2,
        entries: entries,
        archives: old.archives,
      );

      Future<void> openSettings() async {
        final scrollable = find.byType(Scrollable);
        final position = tester.state<ScrollableState>(scrollable).position;
        final button = find.textContaining('提醒 ·');
        for (
          var i = 0;
          i < 20 && button.hitTestable().evaluate().isEmpty;
          i++
        ) {
          position.jumpTo(position.maxScrollExtent);
          await tester.pumpAndSettle();
        }
        await tester.tap(button.hitTestable());
        await tester.pumpAndSettle();
      }

      Future<void> saveMode(String label) async {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('保存设置'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('保存设置'));
        await tester.pumpAndSettle();
      }

      Future<void> assertAutomatic() async {
        final pending = await plugin.pendingNotificationRequests();
        final expected = planReminders(
          book,
          now: DateTime.now(),
          location: await reminders.deviceTimeZone(),
        );
        expect(
          pending.map((p) => p.id).toSet(),
          expected.map((p) => p.id).toSet(),
        );
        expect(pending.length, 11);
        expect(
          pending.every((p) => jsonDecode(p.payload!)['mode'] == 'automatic'),
          isTrue,
        );
        expect(
          pending.map((p) => jsonDecode(p.payload!)['at']).toSet().length,
          pending.length,
        );
        final native = await ReminderService.runtimeChannel
            .invokeMapMethod<String, dynamic>('dailyReminderState');
        expect(native!['scheduled'], isFalse);
      }

      Future<void> assertDaily() async {
        expect(await plugin.pendingNotificationRequests(), isEmpty);
        final native = await ReminderService.runtimeChannel
            .invokeMapMethod<String, dynamic>('dailyReminderState');
        final expected = planReminders(
          Notebook.empty(),
          now: DateTime.now(),
          location: await reminders.deviceTimeZone(),
          preferences: await readReminderPreferences(preferencesFile),
        ).single;
        expect(native!['scheduled'], isTrue);
        expect(native['at'], expected.at.millisecondsSinceEpoch);
      }

      try {
        await file.writeAsString(jsonEncode(book.toJson()));
        await writeReminderPreferences(
          preferencesFile,
          const ReminderPreferences(),
        );
        await reminders.initialize();
        final zone = await reminders.deviceTimeZone();
        await plugin.zonedSchedule(
          id: 42,
          scheduledDate: tz.TZDateTime.now(zone).add(const Duration(days: 1)),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              ReminderService.channelId,
              '笔记提醒',
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: '旧条目提醒',
          payload: '{"volume":2,"entryId":"summary-0"}',
        );
        await tester.pumpWidget(const DiaryApp());
        await tester.pumpAndSettle();
        final baseline = await reminders.synchronize(book);
        expect(
          baseline.enabled,
          isTrue,
          reason: 'Use a dedicated emulator with the reminder channel enabled.',
        );
        await assertAutomatic();

        await openSettings();
        await tester.ensureVisible(find.text('每日提醒'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('每日提醒'));
        await tester.pumpAndSettle();
        final timeButton = find.byKey(const Key('reminder-time'));
        await tester.ensureVisible(timeButton);
        await tester.pumpAndSettle();
        await tester.tap(timeButton);
        await tester.pumpAndSettle();
        final dialog = find.byType(TimePickerDialog);
        expect(dialog, findsOneWidget);
        final localizations = MaterialLocalizations.of(tester.element(dialog));
        await tester.tap(
          find.byTooltip(localizations.inputTimeModeButtonLabel),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(0), '17');
        await tester.enterText(find.byType(TextField).at(1), '45');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.tap(find.text(localizations.okButtonLabel));
        await tester.pumpAndSettle();
        expect(find.byType(TimePickerDialog), findsNothing);
        await saveMode('每日提醒');
        expect(
          await readReminderPreferences(preferencesFile),
          const ReminderPreferences(
            mode: ReminderMode.daily,
            hour: 17,
            minute: 45,
          ),
        );
        await assertDaily();
        final initialDaily = await ReminderService.runtimeChannel
            .invokeMapMethod<String, dynamic>('dailyReminderState');
        // Simulate the stale future alarm left by moving the system date back.
        await ReminderService.runtimeChannel.invokeMethod<void>(
          'scheduleDailyReminder',
          {
            'at':
                (initialDaily!['at'] as int) +
                const Duration(days: 2).inMilliseconds,
          },
        );
        await reminders.refreshFromDisk();
        await assertDaily();

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(const DiaryApp());
        await tester.pumpAndSettle();
        await openSettings();
        expect(find.text('每日提醒时间 · 17:45'), findsOneWidget);
        await tester.ensureVisible(find.text('自动提醒'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('自动提醒'));
        await tester.pumpAndSettle();
        // Dismissing an unsaved mode change must not replace the native alarm.
        Navigator.of(tester.element(find.text('保存设置'))).pop();
        await tester.pumpAndSettle();
        expect(
          (await readReminderPreferences(preferencesFile)).mode,
          ReminderMode.daily,
        );
        await reminders.refreshFromDisk();
        await assertDaily();

        // Daily writing reminders remain scheduled for an empty notebook too.
        await reminders.synchronize(Notebook.empty());
        await assertDaily();
        await reminders.synchronize(book);
        await openSettings();
        await saveMode('自动提醒');
        await assertAutomatic();

        await tester.tap(find.widgetWithText(TextButton, '卷二'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('卷一 · 已封存'));
        await tester.pumpAndSettle();
        expect(find.text('本卷已封存 · 只读'), findsOneWidget);
        // Inject native delivery's callback, without pretending to test OS delivery.
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'dexterous.com/flutter/local_notifications',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('didReceiveNotificationResponse', {
              'notificationId': 1,
              'notificationResponseType': 0,
              'payload': const ReminderTarget(mode: ReminderMode.automatic)
                  .payload,
            }),
          ),
          null,
        );
        await tester.pumpAndSettle();
        expect(find.text('本卷已封存 · 只读'), findsNothing);
        expect(find.text(entries.first.text).hitTestable(), findsOneWidget);
        expect(jsonDecode(await file.readAsString()), book.toJson());
        await openSettings();
        await saveMode('每日提醒');
        await tester.tap(find.widgetWithText(TextButton, '设置'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('销毁所有记录'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('销毁所有记录'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认销毁记录'));
        await tester.pumpAndSettle();
        final cleared = Notebook.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        );
        expect(cleared.entries, isEmpty);
        expect(cleared.archives, isEmpty);
        await reminders.refreshFromDisk();
        await assertDaily();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await reminders.beginDestruction();
        try {
          await reminders.cancelAllForDestruction();
          await notebook.restore();
          await preferences.restore();
        } finally {
          await reminders.endDestruction();
        }
      }
    },
  );
}
