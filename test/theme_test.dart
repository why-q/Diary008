import 'dart:io';

import 'package:diary008/app_localizations.dart';
import 'package:diary008/journal_theme.dart';
import 'package:diary008/theme_preferences.dart';
import 'package:diary008/theme_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'theme preferences round-trip independently from notebook data',
    () async {
      final directory = await Directory.systemTemp.createTemp('diary-theme-');
      final file = File('${directory.path}/theme_preferences.json');
      addTearDown(() => directory.delete(recursive: true));

      const expected = ThemePreferences(
        mode: JournalThemeMode.dark,
        palette: JournalPalette.cyanPaper,
      );
      await writeThemePreferences(file, expected);

      expect(await readThemePreferences(file), expected);
      expect(
        await file.readAsString(),
        '{"mode":"dark","palette":"cyanPaper"}\n',
      );
    },
  );

  test('missing and malformed theme preferences fall back or fail without data loss', () async {
    final directory = await Directory.systemTemp.createTemp('diary-theme-');
    final file = File('${directory.path}/theme_preferences.json');
    addTearDown(() => directory.delete(recursive: true));

    expect(await readThemePreferences(file), const ThemePreferences());
    await file.writeAsString('{"mode":"unknown","palette":"plainWhite"}');
    expect(() => readThemePreferences(file), throwsA(isA<FormatException>()));
  });

  test('each paper palette provides readable light and dark variants', () {
    for (final palette in JournalPalette.values) {
      final light = JournalTheme.fromPalette(palette, Brightness.light);
      final dark = JournalTheme.fromPalette(palette, Brightness.dark);
      expect(light.paper, isNot(dark.paper));
      expect(_contrast(light.paper, light.ink), greaterThanOrEqualTo(4.5));
      expect(_contrast(dark.paper, dark.ink), greaterThanOrEqualTo(4.5));
      expect(_contrast(light.paper, light.fadedInk), greaterThanOrEqualTo(3));
      expect(_contrast(dark.paper, dark.fadedInk), greaterThanOrEqualTo(3));
    }
  });

  for (final locale in [const Locale('zh', 'CN'), const Locale('en')]) {
    testWidgets(
      'production theme save failure is reported in ${locale.languageCode} after sheet dismissal',
      (tester) async {
        final save = Completer<bool>();
        final navigatorKey = GlobalKey<NavigatorState>();
        var failureReported = false;
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            locale: locale,
            supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      builder: (_) => ThemeSettings(
                        preferences: const ThemePreferences(),
                        onChanged: (_) {},
                        onSave: (_) => save.future,
                        onSaveFailed: () {
                          // This matches the production callback in NotebookPage.
                          reportThemeSaveFailure(context);
                          failureReported = true;
                          return const ThemePreferences();
                        },
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('theme-mode-dark')));
        await tester.pump();
        navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
        save.complete(false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final expected = locale.languageCode == 'en'
            ? 'Theme settings could not be saved. Please try again.'
            : '外观设置未能保存，请重试。';
        expect(failureReported, isTrue);
        expect(find.text(expected), findsOneWidget);
      },
    );
  }

  testWidgets(
    'a later failed save rolls back to the latest successful choice',
    (tester) async {
      var saveCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThemeSettings(
              preferences: const ThemePreferences(),
              onChanged: (_) {},
              onSave: (_) async {
                saveCount++;
                return saveCount == 1;
              },
              onSaveFailed: () =>
                  const ThemePreferences(mode: JournalThemeMode.dark),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('theme-mode-dark')));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const Key('theme-mode-light')));
      await tester.pump();
      await tester.pump();

      expect(
        tester
            .widget<RadioGroup<JournalThemeMode>>(
              find.byType(RadioGroup<JournalThemeMode>).first,
            )
            .groupValue,
        JournalThemeMode.dark,
      );
    },
  );

  testWidgets('theme setting changes are reported immediately', (tester) async {
    ThemePreferences? changed;
    await tester.pumpWidget(
      MaterialApp(
        theme: journalThemeData(JournalPalette.antiquePaper, Brightness.light),
        home: ThemeSettings(
          preferences: const ThemePreferences(),
          onChanged: (value) => changed = value,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('theme-mode-dark')));
    await tester.pump();
    expect(changed?.mode, JournalThemeMode.dark);

    await tester.tap(find.byKey(const Key('theme-palette-cyanPaper')));
    await tester.pump();
    expect(changed?.palette, JournalPalette.cyanPaper);
  });
}

double _contrast(Color first, Color second) {
  final light = first.computeLuminance();
  final dark = second.computeLuminance();
  final brighter = light > dark ? light : dark;
  final dimmer = light > dark ? dark : light;
  return (brighter + .05) / (dimmer + .05);
}
