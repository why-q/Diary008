import 'package:diary008/theme_preferences.dart';
import 'package:diary008/theme_preferences_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'unavailable persistent storage rolls back a new theme choice',
    () async {
      final store = UnavailableThemePreferencesStore();
      final initial = await store.load();
      final controller = ThemePreferencesController(store, initial: initial);
      const selected = ThemePreferences(mode: JournalThemeMode.dark);

      expect(await controller.change(selected), isFalse);
      expect(controller.current, initial);
      expect(controller.lastSaved, initial);
      expect(controller.failureCount, 1);
      controller.dispose();
    },
  );
}
