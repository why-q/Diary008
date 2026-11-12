import 'package:diary008/app_localizations.dart';
import 'package:diary008/journal_theme.dart';
import 'package:diary008/notebook.dart';
import 'package:diary008/reminder_preferences.dart';
import 'package:diary008/reminder_service.dart';
import 'package:diary008/reminder_settings.dart';
import 'package:diary008/theme_preferences.dart';
import 'package:diary008/volume_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(JournalPalette palette, Brightness brightness, Widget home) =>
    MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: journalThemeData(palette, Brightness.light),
      darkTheme: journalThemeData(palette, Brightness.dark),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: home,
    );

void main() {
  testWidgets('reminder settings use theme colors across palettes', (
    tester,
  ) async {
    for (final palette in JournalPalette.values) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final colors = JournalTheme.fromPalette(palette, brightness);
        await tester.pumpWidget(
          _app(
            palette,
            brightness,
            Scaffold(
              body: ReminderSettings(
                preferences: const ReminderPreferences(),
                result: const ReminderSyncResult(
                  enabled: true,
                  scheduledCount: 0,
                  preferences: ReminderPreferences(),
                ),
                hasError: false,
                onEnable: () {},
                onCheck: () {},
                onSystemSettings: () {},
                onSave: (_) async => false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(
                find.byKey(const Key('reminder-automatic-description')),
              )
              .style
              ?.color,
          colors.fadedInk,
        );
        expect(
          tester
              .widget<Text>(find.byKey(const Key('reminder-timezone-notice')))
              .style
              ?.color,
          colors.fadedInk,
        );
        await tester.tap(find.byKey(const Key('reminder-save')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(find.byKey(const Key('reminder-save-error')))
              .style
              ?.color,
          colors.ink,
        );
      }
    }
  });

  testWidgets('volume picker and archive confirmation use theme colors', (
    tester,
  ) async {
    final archivedAt = DateTime(2026, 10, 1);
    final archive = NotebookArchive(
      volume: 1,
      entries: const [],
      invalidatedAt: null,
      archivedAt: archivedAt,
      reason: ArchiveReason.manualClosure,
      failedEntryIds: const {},
    );
    final book = Notebook(volume: 2, entries: const [], archives: [archive]);
    for (final palette in JournalPalette.values) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final colors = JournalTheme.fromPalette(palette, brightness);
        await tester.pumpWidget(
          _app(
            palette,
            brightness,
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  key: const Key('open-volume-picker'),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => VolumePicker(book: book),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('open-volume-picker')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(find.byKey(const Key('archived-volume-date')))
              .style
              ?.color,
          colors.fadedInk,
        );
        await tester.tap(find.byKey(const Key('archive-delete')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<AlertDialog>(
                find.byKey(const Key('archive-delete-confirmation')),
              )
              .backgroundColor,
          colors.paper,
        );
        await tester.tap(find.byKey(const Key('archive-delete-cancel')));
        await tester.pumpAndSettle();
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
      }
    }
  });
}
