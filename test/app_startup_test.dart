import 'dart:async';
import 'dart:io';

import 'package:diary008/app_language.dart';
import 'package:diary008/app_startup.dart';
import 'package:diary008/font_preferences.dart';
import 'package:diary008/journal_theme.dart';
import 'package:diary008/main.dart';
import 'package:diary008/theme_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _GateLanguageStore implements LanguageSettingsStore {
  final gate = Completer<AppLanguage>();

  @override
  Future<AppLanguage> load() => gate.future;

  @override
  Future<void> save(AppLanguage language) async {}
}

class _GateThemeStore implements ThemePreferencesStore {
  final gate = Completer<ThemePreferences>();

  @override
  Future<ThemePreferences> load() => gate.future;

  @override
  Future<void> save(ThemePreferences preferences) async {}
}

class _ThrowingLanguageStore implements LanguageSettingsStore {
  @override
  Future<AppLanguage> load() async =>
      throw const FileSystemException('read failed');

  @override
  Future<void> save(AppLanguage language) async {}
}

class _ThrowingThemeStore implements ThemePreferencesStore {
  @override
  Future<ThemePreferences> load() async =>
      throw const FileSystemException('read failed');

  @override
  Future<void> save(ThemePreferences preferences) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bootstrap waits for preferences and loads only cached fonts', () async {
    final cacheRoot = await Directory.systemTemp.createTemp(
      'diary008-startup-font-cache-',
    );
    addTearDown(() => cacheRoot.delete(recursive: true));
    final cachedBook = Directory('${cacheRoot.path}/book-00000000000000000001');
    await cachedBook.create();
    await File('assets/fonts/NotoSerifSC.ttf')
        .copy('${cachedBook.path}/NotoSerifSC.ttf');
    await File('assets/fonts/Literata.ttf')
        .copy('${cachedBook.path}/Literata.ttf');

    final languageStore = _GateLanguageStore();
    final themeStore = _GateThemeStore();
    var networkDownloads = 0;
    final loadedFamilies = <String>[];
    final fontController = FontPreferenceController(
      downloader:
          (uri, {required expectedLength, required cancellation}) async {
            networkDownloads++;
            throw StateError('startup must not download fonts');
          },
      cacheDirectoryProvider: () async => cacheRoot,
      preferenceLoader: () async => AppFontPreference.book,
      fontLoader: (family, bytes) async => loadedFamilies.add(family),
    );
    var startupFinished = false;
    final startupFuture =
        loadDiaryStartupPreferences(
          languageStore: languageStore,
          themeStore: themeStore,
          fontPreferences: fontController,
        ).then((value) {
          startupFinished = true;
          return value;
        });

    expect(startupFinished, isFalse);
    languageStore.gate.complete(AppLanguage.english);
    themeStore.gate.complete(
      const ThemePreferences(
        mode: JournalThemeMode.dark,
        palette: JournalPalette.cyanPaper,
      ),
    );
    final startup = await startupFuture;

    expect(startup.language, AppLanguage.english);
    expect(startup.themePreferences.mode, JournalThemeMode.dark);
    expect(startup.themePreferences.palette, JournalPalette.cyanPaper);
    expect(fontController.preference, AppFontPreference.book);
    expect(loadedFamilies, containsAll(['NotoSerifSC', 'Literata']));
    expect(networkDownloads, 0);
    fontController.dispose();
  });

  test('preference read failures fall back without blocking startup', () async {
    final fontController = FontPreferenceController(
      preferenceLoader: () async =>
          throw const FileSystemException('font read failed'),
      cacheDirectoryProvider: () async => Directory.systemTemp,
      fontLoader: (family, bytes) async {},
    );
    final startup = await loadDiaryStartupPreferences(
      languageStore: _ThrowingLanguageStore(),
      themeStore: _ThrowingThemeStore(),
      fontPreferences: fontController,
    );

    expect(startup.language, AppLanguage.system);
    expect(startup.themePreferences, const ThemePreferences());
    expect(fontController.preference, AppFontPreference.followSystem);
    expect(fontController.lastError, contains('字体偏好或缓存无法读取'));
    fontController.dispose();
  });

  testWidgets('resolved startup settings are applied on the first app frame', (
    tester,
  ) async {
    final fontController = FontPreferenceController(
      preferenceLoader: () async => AppFontPreference.followSystem,
    );
    final startup = DiaryStartupPreferences(
      language: AppLanguage.english,
      themePreferences: const ThemePreferences(
        mode: JournalThemeMode.dark,
        palette: JournalPalette.cyanPaper,
      ),
      fontPreferenceController: fontController,
      languageStore: _GateLanguageStore(),
      themeStore: _GateThemeStore(),
    );
    await tester.pumpWidget(DiaryApp(startup: startup));
    await tester.pump();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.locale, const Locale('en'));
    expect(materialApp.themeMode, ThemeMode.dark);
    expect(
      materialApp.theme!.scaffoldBackgroundColor,
      JournalTheme.fromPalette(
        JournalPalette.cyanPaper,
        Brightness.light,
      ).paper,
    );
    expect(
      materialApp.darkTheme!.scaffoldBackgroundColor,
      JournalTheme.fromPalette(JournalPalette.cyanPaper, Brightness.dark).paper,
    );
    final overlay = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    expect(overlay.value.statusBarIconBrightness, Brightness.light);
    expect(
      overlay.value.systemNavigationBarColor,
      JournalTheme.fromPalette(JournalPalette.cyanPaper, Brightness.dark).paper,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
