import 'dart:async';
import 'dart:convert';

import 'package:diary008/main.dart';
import 'package:diary008/notebook.dart';
import 'package:diary008/reminder_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/notebook_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'cancel preserves records; confirm destroys every volume across restart',
    (tester) async {
      final notebook = await snapshotNotebook();
      final file = notebook.file;
      final now = DateTime.now();
      final book = Notebook.empty()
          .add('历史记录秘密', now.add(const Duration(days: 10)), now)
          .startNewVolume('当前卷秘密', now)
          .add('当前记录秘密', now.add(const Duration(days: 20)), now);
      Future<void> tap(String text) async {
        await tester.ensureVisible(find.text(text));
        await tester.tap(find.text(text));
        await tester.pumpAndSettle();
      }

      try {
        await file.writeAsString(jsonEncode(book.toJson()));
        await tester.pumpWidget(const DiaryApp());
        await tester.pumpAndSettle();
        await tap('设置');
        await tap('销毁所有记录');
        await tap('取消');
        expect(
          Notebook.fromJson(jsonDecode(await file.readAsString())).toJson(),
          book.toJson(),
        );
        await tap('销毁所有记录');
        await tap('确认销毁记录');
        expect(
          Notebook.fromJson(jsonDecode(await file.readAsString())).entries,
          isEmpty,
        );
        expect(
          Notebook.fromJson(jsonDecode(await file.readAsString())).archives,
          isEmpty,
        );
        final notifications = FlutterLocalNotificationsPlugin();
        expect(await notifications.pendingNotificationRequests(), isEmpty);
        expect(await notifications.getActiveNotifications(), isEmpty);
        expect(find.text('当前记录秘密'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(const DiaryApp());
        await tester.pumpAndSettle();
        await tap('卷一');
        expect(find.textContaining('历史记录秘密'), findsNothing);
        expect(find.textContaining('当前卷秘密'), findsNothing);
        expect(
          Notebook.fromJson(jsonDecode(await file.readAsString())).volume,
          1,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await notebook.restore();
      }
    },
  );
  testWidgets('an old reload cannot restore destroyed records', (tester) async {
    final notebook = await snapshotNotebook();
    final file = notebook.file;
    const channel = MethodChannel('app.diary008/diagnostics');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final readReached = Completer<void>();
    final releaseRead = Completer<void>();
    Future<void> tap(String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    try {
      await file.writeAsString('{');
      await tester.pumpWidget(const DiaryApp());
      await tester.pumpAndSettle();
      expect(find.text('重新读取'), findsOneWidget);
      final now = DateTime.now();
      final old = Notebook.empty().add(
        '销毁前的延迟重读内容',
        now.add(const Duration(days: 10)),
        now,
      );
      await file.writeAsString(jsonEncode(old.toJson()));
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'record' &&
            (call.arguments as Map)['event'] == 'storage.read.success' &&
            !readReached.isCompleted) {
          readReached.complete();
          await releaseRead.future;
        }
        return null;
      });
      await tap('重新读取');
      await readReached.future;
      await tap('设置');
      await tap('销毁所有记录');
      await tap('确认销毁记录');
      // A read may still be migrating data: destruction must not race its writes.
      expect(
        Notebook.fromJson(jsonDecode(await file.readAsString())).toJson(),
        old.toJson(),
      );
      releaseRead.complete();
      await tester.pumpAndSettle();
      await tap('关闭');
      expect(find.text('销毁前的延迟重读内容'), findsOneWidget);
      await tap('设置');
      await tap('销毁所有记录');
      await tap('确认销毁记录');
      await tap('关闭');
      expect(find.text('销毁前的延迟重读内容'), findsNothing);
      expect(
        Notebook.fromJson(jsonDecode(await file.readAsString())).entries,
        isEmpty,
      );
    } finally {
      if (!releaseRead.isCompleted) releaseRead.complete();
      messenger.setMockMethodCallHandler(channel, null);
      await tester.pumpWidget(const SizedBox.shrink());
      await notebook.restore();
    }
  });
  testWidgets(
    'a delayed reminder disk read cannot recreate destroyed reminders',
    (tester) async {
      final notebook = await snapshotNotebook();
      final file = notebook.file;
      const channel = MethodChannel('app.diary008/diagnostics');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final readReached = Completer<void>();
      final releaseRead = Completer<void>();
      final reminders = ReminderService.instance;
      var gateHeld = false;
      Future<void>? refresh;
      try {
        final now = DateTime.now();
        final old = Notebook.empty().add(
          '待销毁的提醒',
          now.add(const Duration(days: 10)),
          now,
        );
        await file.writeAsString(jsonEncode(old.toJson()));
        final baseline = await reminders.synchronize(old);
        if (!baseline.enabled) {
          markTestSkipped('通知权限未开启，无法验证旧提醒是否复活');
          return;
        }
        final notifications = FlutterLocalNotificationsPlugin();
        await notifications.show(
          id: 808008,
          title: '通知清理回归',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              ReminderService.channelId,
              '断言提醒',
            ),
          ),
        );
        var active = await notifications.getActiveNotifications();
        for (
          var attempt = 0;
          !active.any((item) => item.id == 808008) && attempt < 50;
          attempt++
        ) {
          await tester.pump(const Duration(milliseconds: 50));
          active = await notifications.getActiveNotifications();
        }
        expect(active.map((item) => item.id), contains(808008));
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'record' &&
              (call.arguments as Map)['event'] == 'storage.read.success' &&
              !readReached.isCompleted) {
            readReached.complete();
            await releaseRead.future;
          }
          return null;
        });
        refresh = reminders.refreshFromDisk();
        await readReached.future;
        await reminders.beginDestruction();
        gateHeld = true;
        await file.writeAsString(jsonEncode(Notebook.empty().toJson()));
        await reminders.cancelAllForDestruction();
        await reminders.endDestruction();
        gateHeld = false;
        releaseRead.complete();
        await refresh;
        expect(
          await FlutterLocalNotificationsPlugin().pendingNotificationRequests(),
          isEmpty,
        );
        expect(await notifications.getActiveNotifications(), isEmpty);
      } finally {
        if (!releaseRead.isCompleted) releaseRead.complete();
        await refresh;
        if (gateHeld) await reminders.endDestruction();
        await reminders.cancelAllForDestruction();
        messenger.setMockMethodCallHandler(channel, null);
        await notebook.restore();
      }
    },
  );
}
