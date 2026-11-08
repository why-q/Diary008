import 'dart:async';

import 'package:diary008/reminder_preferences.dart';
import 'package:diary008/reminder_service.dart';
import 'package:diary008/reminder_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mode and clock changes are retained and saved together', (
    tester,
  ) async {
    final saves = <ReminderPreferences>[];
    await _openSettings(
      tester,
      preferences: const ReminderPreferences(
        mode: ReminderMode.daily,
        hour: 7,
        minute: 35,
      ),
      result: const ReminderSyncResult(
        enabled: true,
        scheduledCount: 1,
        preferences: ReminderPreferences(),
      ),
      onSave: (preferences) async {
        saves.add(preferences);
        return true;
      },
    );

    expect(find.text('每日提醒时间 · 07:35'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reminder-mode-automatic')));
    await tester.pump();
    expect(find.byKey(const Key('reminder-time')), findsNothing);
    await tester.tap(find.byKey(const Key('reminder-mode-daily')));
    await tester.pump();
    expect(find.text('每日提醒时间 · 07:35'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reminder-time')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    expect(
      int.parse(tester.widget<TextField>(fields.at(0)).controller!.text),
      7,
    );
    expect(
      int.parse(tester.widget<TextField>(fields.at(1)).controller!.text),
      35,
    );
    await tester.enterText(fields.at(0), '10');
    await tester.enterText(fields.at(1), '25');
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('每日提醒时间 · 10:25'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reminder-mode-automatic')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('reminder-mode-daily')));
    await tester.pump();
    expect(find.text('每日提醒时间 · 10:25'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reminder-save')));
    await tester.pumpAndSettle();
    expect(saves, [
      const ReminderPreferences(mode: ReminderMode.daily, hour: 10, minute: 25),
    ]);
    expect(find.byType(ReminderSettings), findsNothing);
  });

  testWidgets('loaded preferences initialize settings without a sync result', (
    tester,
  ) async {
    final saves = <ReminderPreferences>[];
    const preferences = ReminderPreferences(
      mode: ReminderMode.daily,
      hour: 6,
      minute: 45,
    );
    await _openSettings(
      tester,
      preferences: preferences,
      onSave: (saved) async {
        saves.add(saved);
        return true;
      },
    );

    expect(find.text('每日提醒时间 · 06:45'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reminder-save')));
    await tester.pumpAndSettle();

    expect(saves, [preferences]);
    expect(find.byType(ReminderSettings), findsNothing);
  });

  testWidgets('saving disables duplicates and only success dismisses', (
    tester,
  ) async {
    final completed = Completer<bool>();
    var attempts = 0;
    await _openSettings(
      tester,
      onSave: (_) {
        attempts++;
        return completed.future;
      },
    );

    await tester.tap(find.byKey(const Key('reminder-save')));
    await tester.pump();
    expect(attempts, 1);
    await tester.tap(find.byKey(const Key('reminder-save')));
    await tester.pump();
    expect(attempts, 1);
    final save = tester.widget<FilledButton>(
      find.byKey(const Key('reminder-save')),
    );
    expect(save.onPressed, isNull);
    expect(find.byType(ReminderSettings), findsOneWidget);
    completed.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(ReminderSettings), findsNothing);
  });

  testWidgets('pending save can be dismissed safely', (tester) async {
    final completed = Completer<bool>();
    var attempts = 0;
    await _openSettings(
      tester,
      onSave: (_) {
        attempts++;
        return completed.future;
      },
    );

    await tester.tap(find.byKey(const Key('reminder-save')));
    await tester.pump();
    expect(attempts, 1);
    await tester.tap(find.byKey(const Key('reminder-cancel')));
    await tester.pump();
    expect(find.byType(ReminderSettings), findsOneWidget);

    completed.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(ReminderSettings), findsNothing);
    expect(find.text('open settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('false and thrown saves remain recoverable', (tester) async {
    var attempts = 0;
    await _openSettings(
      tester,
      onSave: (_) async {
        attempts++;
        if (attempts == 1) return false;
        if (attempts == 2) throw StateError('save failed');
        return true;
      },
    );

    await tester.tap(find.byKey(const Key('reminder-save')));
    await tester.pumpAndSettle();
    expect(find.byType(ReminderSettings), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('reminder-save')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('reminder-save')));
    await tester.pumpAndSettle();
    expect(find.byType(ReminderSettings), findsOneWidget);

    await tester.tap(find.byKey(const Key('reminder-save')));
    await tester.pumpAndSettle();
    expect(attempts, 3);
    expect(find.byType(ReminderSettings), findsNothing);
  });

  testWidgets('cancel and barrier dismissal do not save', (tester) async {
    var saves = 0;
    await _openSettings(tester, onSave: (_) async => saves++ > 0);

    await tester.tap(find.byKey(const Key('reminder-cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(ReminderSettings), findsNothing);
    expect(saves, 0);

    await _openSettings(tester, onSave: (_) async => saves++ > 0);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byType(ReminderSettings), findsNothing);
    expect(saves, 0);
  });

  testWidgets('daily settings remain usable in a short viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openSettings(
      tester,
      preferences: const ReminderPreferences(
        mode: ReminderMode.daily,
        hour: 6,
        minute: 45,
      ),
      onSave: (_) async => true,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('每日提醒时间 · 06:45'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('reminder-time')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.byKey(const Key('reminder-time')).hitTestable(),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('reminder-save')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.byKey(const Key('reminder-save')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('reminder-save')));
    await tester.pumpAndSettle();
    expect(find.byType(ReminderSettings), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openSettings(
  WidgetTester tester, {
  ReminderPreferences preferences = const ReminderPreferences(),
  ReminderSyncResult? result,
  required Future<bool> Function(ReminderPreferences) onSave,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => ReminderSettings(
                result: result,
                preferences: preferences,
                hasError: false,
                onEnable: _noAction,
                onCheck: _noAction,
                onSystemSettings: _noAction,
                onSave: onSave,
              ),
            ),
            child: const Text('open settings'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open settings'));
  await tester.pumpAndSettle();
}

void _noAction() {}
