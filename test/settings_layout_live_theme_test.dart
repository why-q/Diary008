import 'package:diary008/app_language.dart';
import 'package:diary008/app_startup.dart';
import 'package:diary008/data_settings.dart';
import 'package:diary008/font_preferences.dart';
import 'package:diary008/journal_theme.dart';
import 'package:diary008/main.dart';
import 'package:diary008/theme_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<DiaryStartupPreferences> _startup({
  ThemePreferencesStore? themeStore,
}) async => DiaryStartupPreferences(
  language: AppLanguage.english,
  themePreferences: const ThemePreferences(mode: JournalThemeMode.light),
  fontPreferenceController: FontPreferenceController(
    preferenceLoader: () async => AppFontPreference.followSystem,
  ),
  languageStore: MemoryLanguageSettingsStore(AppLanguage.english),
  themeStore:
      themeStore ??
      MemoryThemePreferencesStore(
        const ThemePreferences(mode: JournalThemeMode.light),
      ),
);

class _FailingThemeStore implements ThemePreferencesStore {
  @override
  Future<ThemePreferences> load() async =>
      const ThemePreferences(mode: JournalThemeMode.light);

  @override
  Future<void> save(ThemePreferences value) async {
    throw StateError("test save failure");
  }
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.pumpWidget(DiaryApp(startup: await _startup()));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.text('Settings'));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('production settings entry groups every appearance control', (
    tester,
  ) async {
    await _openSettings(tester);

    final appearance = find.text('Appearance');
    expect(appearance, findsOneWidget);
    expect(
      find.ancestor(of: appearance, matching: find.byType(TextButton)),
      findsNothing,
      reason: 'Appearance is a section heading, not a second modal action.',
    );

    final appearanceY = tester.getTopLeft(appearance).dy;
    final languageY = tester.getTopLeft(find.text('Language')).dy;
    final fontY = tester.getTopLeft(find.text('App font')).dy;
    final modeY = tester.getTopLeft(find.text('Display mode')).dy;
    final paletteY = tester.getTopLeft(find.text('Paper palette')).dy;
    final diagnosticsY = tester.getTopLeft(find.text('Data & diagnostics')).dy;
    expect(languageY, greaterThan(appearanceY));
    expect(fontY, greaterThan(languageY));
    expect(modeY, greaterThan(fontY));
    expect(paletteY, greaterThan(modeY));
    expect(diagnosticsY, greaterThan(paletteY));
    expect(find.byKey(const Key('theme-palette-cyanPaper')), findsOneWidget);
    expect(find.byKey(const Key('theme-mode-dark')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    "failed theme saves roll back and report from the settings entry",
    (tester) async {
      await tester.pumpWidget(
        DiaryApp(startup: await _startup(themeStore: _FailingThemeStore())),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text("Settings"));
      await tester.pump(const Duration(milliseconds: 400));

      final darkModeOption = find.byKey(const Key("theme-mode-dark"));
      await Scrollable.ensureVisible(
        tester.element(darkModeOption),
        alignment: 0.5,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(darkModeOption);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text("Theme settings could not be saved. Please try again."),
        findsOneWidget,
      );
      expect(
        tester
            .widget<RadioGroup<JournalThemeMode>>(
              find.byType(RadioGroup<JournalThemeMode>).first,
            )
            .groupValue,
        JournalThemeMode.light,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('theme choices immediately repaint the open settings surface', (
    tester,
  ) async {
    await _openSettings(tester);
    final paletteOption = find.byKey(const Key('theme-palette-cyanPaper'));
    await Scrollable.ensureVisible(
      tester.element(paletteOption),
      alignment: 0.5,
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('theme-palette-cyanPaper')));
    await tester.pump();
    final settingsContext = tester.element(find.byType(DataSettings));
    expect(
      journalThemeOf(settingsContext).paper,
      JournalTheme.fromPalette(
        JournalPalette.cyanPaper,
        Brightness.light,
      ).paper,
    );

    final darkModeOption = find.byKey(const Key('theme-mode-dark'));
    await Scrollable.ensureVisible(
      tester.element(darkModeOption),
      alignment: 0.5,
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('theme-mode-dark')));
    await tester.pump();
    expect(
      journalThemeOf(tester.element(find.byType(DataSettings))).paper,
      JournalTheme.fromPalette(JournalPalette.cyanPaper, Brightness.dark).paper,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
