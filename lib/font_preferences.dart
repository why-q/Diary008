import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _fontPreferenceStorageKey = 'app_font_preference';

enum AppFontPreference { followSystem, handwritten, book, clean }

extension AppFontPreferenceDetails on AppFontPreference {
  String get label => switch (this) {
    AppFontPreference.followSystem => '跟随系统',
    AppFontPreference.handwritten => '古朴手写',
    AppFontPreference.book => '经典书卷',
    AppFontPreference.clean => '清爽阅读',
  };

  String get description => switch (this) {
    AppFontPreference.followSystem => '使用设备的默认字体',
    AppFontPreference.handwritten => 'Ma Shan Zheng · Cormorant Garamond',
    AppFontPreference.book => 'Noto Serif SC · Literata',
    AppFontPreference.clean => 'Noto Sans SC · Inter',
  };

  FontFamilyPair? get families => switch (this) {
    AppFontPreference.followSystem => null,
    AppFontPreference.handwritten => const FontFamilyPair(
      primary: 'CormorantGaramond',
      fallback: ['MaShanZheng', 'serif'],
    ),
    AppFontPreference.book => const FontFamilyPair(
      primary: 'Literata',
      fallback: ['NotoSerifSC', 'MaShanZheng', 'serif'],
    ),
    AppFontPreference.clean => const FontFamilyPair(
      primary: 'Inter',
      fallback: ['NotoSansSC', 'MaShanZheng', 'sans-serif'],
    ),
  };

  static AppFontPreference fromStorage(String? value) =>
      AppFontPreference.values.firstWhere(
        (preference) => preference.name == value,
        orElse: () => AppFontPreference.followSystem,
      );
}

class FontFamilyPair {
  const FontFamilyPair({required this.primary, required this.fallback});

  final String primary;
  final List<String> fallback;
}

/// Applies the selected Latin family and script-aware fallback to every
/// Material text style. The system option intentionally leaves the theme alone.
ThemeData applyFontPreference(ThemeData theme, AppFontPreference preference) {
  final families = preference.families;
  if (families == null) return theme;

  TextStyle applyFont(TextStyle? style) =>
      style?.copyWith(
        fontFamily: families.primary,
        fontFamilyFallback: families.fallback,
      ) ??
      TextStyle(
        fontFamily: families.primary,
        fontFamilyFallback: families.fallback,
      );

  WidgetStateProperty<TextStyle?>? applyTextButtonFont(
    WidgetStateProperty<TextStyle?>? property,
  ) {
    if (property == null) return null;
    return WidgetStateProperty.resolveWith(
      (states) => applyFont(property.resolve(states)),
    );
  }

  final textButtonStyle = theme.textButtonTheme.style;
  final textButtonTheme = TextButtonThemeData(
    style: (textButtonStyle ?? const ButtonStyle()).copyWith(
      textStyle:
          applyTextButtonFont(textButtonStyle?.textStyle) ??
          WidgetStatePropertyAll(applyFont(null)),
    ),
  );

  return theme.copyWith(
    textTheme: theme.textTheme.apply(
      fontFamily: families.primary,
      fontFamilyFallback: families.fallback,
    ),
    primaryTextTheme: theme.primaryTextTheme.apply(
      fontFamily: families.primary,
      fontFamilyFallback: families.fallback,
    ),
    textButtonTheme: textButtonTheme,
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: (theme.elevatedButtonTheme.style ?? const ButtonStyle()).copyWith(
        textStyle:
            applyTextButtonFont(theme.elevatedButtonTheme.style?.textStyle) ??
            WidgetStatePropertyAll(applyFont(null)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: (theme.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
        textStyle:
            applyTextButtonFont(theme.outlinedButtonTheme.style?.textStyle) ??
            WidgetStatePropertyAll(applyFont(null)),
      ),
    ),
  );
}

class FontPreferenceController extends ChangeNotifier {
  AppFontPreference _preference = AppFontPreference.followSystem;
  Future<void>? _loading;

  AppFontPreference get preference => _preference;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _preference = AppFontPreferenceDetails.fromStorage(
        preferences.getString(_fontPreferenceStorageKey),
      );
    } catch (_) {
      // A preference read failure must not prevent the diary from opening.
      _preference = AppFontPreference.followSystem;
    }
    notifyListeners();
  }

  Future<void> setPreference(AppFontPreference preference) async {
    if (_loading != null) await _loading;
    if (_preference == preference) return;

    _preference = preference;
    notifyListeners();

    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _fontPreferenceStorageKey,
      preference.name,
    );
    if (!saved) throw StateError('字体偏好无法保存。');
  }
}

class FontPreferenceSettings extends StatefulWidget {
  const FontPreferenceSettings({super.key, required this.controller});

  final FontPreferenceController controller;

  @override
  State<FontPreferenceSettings> createState() => _FontPreferenceSettingsState();
}

class _FontPreferenceSettingsState extends State<FontPreferenceSettings> {
  Future<void> _select(AppFontPreference? preference) async {
    if (preference == null) return;
    try {
      await widget.controller.setPreference(preference);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('字体已切换，但偏好保存失败，请稍后重试。')));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('应用字体'),
      const SizedBox(height: 8),
      AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => DropdownButtonFormField<AppFontPreference>(
          key: const Key('app-font-preference-dropdown'),
          initialValue: widget.controller.preference,
          decoration: const InputDecoration(
            labelText: '字体风格',
            border: OutlineInputBorder(),
          ),
          items: AppFontPreference.values
              .map(
                (preference) => DropdownMenuItem(
                  value: preference,
                  child: Text(preference.label),
                ),
              )
              .toList(growable: false),
          onChanged: _select,
        ),
      ),
      const SizedBox(height: 8),
      AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => Text(
          widget.controller.preference.description,
          key: const Key('app-font-preference-description'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      const SizedBox(height: 4),
      const Text(
        '字体设置独立于语言与主题，选中后立即应用。未覆盖的字形会回退到系统字体。',
        style: TextStyle(fontSize: 12),
      ),
    ],
  );
}
