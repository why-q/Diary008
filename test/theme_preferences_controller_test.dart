import 'dart:async';

import 'package:diary008/theme_preferences.dart';
import 'package:diary008/theme_preferences_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeThemeStore implements ThemePreferencesStore {
  _FakeThemeStore(this.saved);

  ThemePreferences saved;
  final writes = <ThemePreferences>[];
  final gates = <Completer<void>>[];
  bool failImmediately = false;

  @override
  Future<ThemePreferences> load() async => saved;

  @override
  Future<void> save(ThemePreferences preferences) async {
    writes.add(preferences);
    if (failImmediately) throw StateError('disk full');
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    saved = preferences;
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition did not become true.');
}

void main() {
  test(
    'a failed last theme write rolls back to the last saved value',
    () async {
      const initial = ThemePreferences();
      final store = _FakeThemeStore(initial)..failImmediately = true;
      final controller = ThemePreferencesController(store, initial: initial);
      const selected = ThemePreferences(mode: JournalThemeMode.dark);

      await controller.change(selected);

      expect(controller.current, initial);
      expect(controller.failureCount, 1);
      expect(store.saved, initial);
      controller.dispose();
    },
  );

  test('a failed later queued selection rolls back to the most recent saved choice', () async {
    const initial = ThemePreferences();
    final store = _FakeThemeStore(initial);
    final controller = ThemePreferencesController(store, initial: initial);
    const first = ThemePreferences(mode: JournalThemeMode.dark);
    const second = ThemePreferences(
      mode: JournalThemeMode.light,
      palette: JournalPalette.cyanPaper,
    );

    final firstSave = controller.change(first);
    await _waitUntil(() => store.writes.length == 1);
    final secondSave = controller.change(second);
    store.gates[0].complete();
    await _waitUntil(() => store.writes.length == 2);
    store.gates[1].completeError(StateError('disk full'));
    expect(await firstSave, isTrue);
    expect(await secondSave, isFalse);

    expect(store.saved, first);
    expect(controller.lastSaved, first);
    expect(controller.current, first);
    expect(controller.failureCount, 1);
    controller.dispose();
  });

  test(
    'rapid selections serialize and a later successful choice wins',
    () async {
      const initial = ThemePreferences();
      final store = _FakeThemeStore(initial);
      final controller = ThemePreferencesController(store, initial: initial);
      const first = ThemePreferences(mode: JournalThemeMode.dark);
      const second = ThemePreferences(
        mode: JournalThemeMode.light,
        palette: JournalPalette.cyanPaper,
      );

      final firstSave = controller.change(first);
      await _waitUntil(() => store.writes.length == 1);
      final secondSave = controller.change(second);
      store.gates[0].completeError(StateError('disk full'));
      await _waitUntil(() => store.writes.length == 2);
      expect(controller.current, second);
      store.gates[1].complete();
      await Future.wait([firstSave, secondSave]);

      expect(store.saved, second);
      expect(controller.current, second);
      expect(controller.failureCount, 1);
      controller.dispose();
    },
  );

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
