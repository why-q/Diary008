import 'dart:io';

import 'package:diary008/journal_theme.dart';
import 'package:diary008/theme_preferences.dart';
import 'package:diary008/theme_settings.dart';
import 'package:flutter/material.dart';
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
        '{"mode":"dark","palette":"cyanPaper"}',
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

  testWidgets('theme setting changes are reported immediately', (tester) async {
    ThemePreferences? changed;
    await tester.pumpWidget(
      MaterialApp(
        theme: journalThemeData(JournalPalette.antiquePaper, Brightness.light),
        home: Material(
          child: ThemeSettings(
            preferences: const ThemePreferences(),
            onChanged: (value) => changed = value,
          ),
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
