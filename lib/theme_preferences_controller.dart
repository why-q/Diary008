import 'dart:async';

import 'theme_preferences.dart';

/// Serializes theme writes and reverts only the latest unsaved selection.
class ThemePreferencesController {
  ThemePreferencesController(
    this._store, {
    ThemePreferences initial = const ThemePreferences(),
  }) : _current = initial,
       _saved = initial;

  final ThemePreferencesStore _store;
  ThemePreferences _current;
  ThemePreferences _saved;
  Future<void> _saveQueue = Future<void>.value();
  int _revision = 0;
  int _failureCount = 0;
  bool _disposed = false;

  ThemePreferences get current => _current;
  ThemePreferences get lastSaved => _saved;
  int get failureCount => _failureCount;

  Future<bool> change(ThemePreferences preferences) {
    if (_disposed) return Future<bool>.value(false);
    if (preferences == _current) return Future<bool>.value(true);
    _current = preferences;
    final revision = ++_revision;
    final result = Completer<bool>();
    _saveQueue = _saveQueue.then((_) async {
      try {
        await _store.save(preferences);
        _saved = preferences;
        result.complete(true);
      } catch (_) {
        _failureCount++;
        if (revision == _revision) _current = _saved;
        result.complete(false);
      }
    });
    return result.future;
  }

  void dispose() => _disposed = true;
}
