import 'app_language.dart';
import 'font_preferences.dart';
import 'theme_preferences.dart';

class DiaryStartupPreferences {
  const DiaryStartupPreferences({
    required this.language,
    required this.themePreferences,
    required this.fontPreferenceController,
    required this.languageStore,
    required this.themeStore,
  });

  final AppLanguage language;
  final ThemePreferences themePreferences;
  final FontPreferenceController fontPreferenceController;
  final LanguageSettingsStore languageStore;
  final ThemePreferencesStore themeStore;
}

/// Resolves persisted preferences and cached fonts before the first app frame.
/// FontPreferenceController.load only reads the local preference/cache; it does
/// not invoke the network downloader.
Future<DiaryStartupPreferences> loadDiaryStartupPreferences({
  required LanguageSettingsStore languageStore,
  required ThemePreferencesStore themeStore,
  required FontPreferenceController fontPreferences,
}) async {
  final languageFuture = languageStore.load().then<AppLanguage>(
    (value) => value,
    onError: (Object _) => AppLanguage.system,
  );
  final themeFuture = themeStore.load().then<ThemePreferences>(
    (value) => value,
    onError: (Object _) => const ThemePreferences(),
  );
  final fontFuture = fontPreferences.load().then<void>(
    (_) {},
    onError: (Object _) {},
  );
  final values = await Future.wait<Object>([
    languageFuture,
    themeFuture,
    fontFuture.then<Object>((_) => true),
  ]);
  return DiaryStartupPreferences(
    language: values[0] as AppLanguage,
    themePreferences: values[1] as ThemePreferences,
    fontPreferenceController: fontPreferences,
    languageStore: languageStore,
    themeStore: themeStore,
  );
}
