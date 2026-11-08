import 'package:flutter/material.dart';

import 'journal_theme.dart';
import 'theme_preferences.dart';

class ThemeSettings extends StatefulWidget {
  const ThemeSettings({
    super.key,
    required this.preferences,
    required this.onChanged,
  });

  final ThemePreferences preferences;
  final ValueChanged<ThemePreferences> onChanged;

  @override
  State<ThemeSettings> createState() => _ThemeSettingsState();
}

class _ThemeSettingsState extends State<ThemeSettings> {
  late ThemePreferences _preferences;

  @override
  void initState() {
    super.initState();
    _preferences = widget.preferences;
  }

  @override
  void didUpdateWidget(covariant ThemeSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferences != widget.preferences) {
      _preferences = widget.preferences;
    }
  }

  void _change({JournalThemeMode? mode, JournalPalette? palette}) {
    final next = _preferences.copyWith(mode: mode, palette: palette);
    setState(() => _preferences = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = journalThemeOf(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .86,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('外观设置', style: TextStyle(fontSize: 25, color: colors.ink)),
              const SizedBox(height: 8),
              Text(
                '选择后立即应用并保存。纸张配色会同时适配浅色与深色模式。',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: colors.fadedInk,
                ),
              ),
              const SizedBox(height: 14),
              Text('显示模式', style: TextStyle(color: colors.fadedInk)),
              RadioGroup<JournalThemeMode>(
                groupValue: _preferences.mode,
                onChanged: (value) {
                  if (value != null) _change(mode: value);
                },
                child: Column(
                  children: [
                    RadioListTile<JournalThemeMode>(
                      key: const Key('theme-mode-system'),
                      value: JournalThemeMode.system,
                      title: const Text('跟随系统'),
                      subtitle: const Text('使用设备当前的明暗设置'),
                      contentPadding: EdgeInsets.zero,
                      activeColor: colors.accent,
                    ),
                    RadioListTile<JournalThemeMode>(
                      key: const Key('theme-mode-light'),
                      value: JournalThemeMode.light,
                      title: const Text('浅色'),
                      contentPadding: EdgeInsets.zero,
                      activeColor: colors.accent,
                    ),
                    RadioListTile<JournalThemeMode>(
                      key: const Key('theme-mode-dark'),
                      value: JournalThemeMode.dark,
                      title: const Text('深色'),
                      contentPadding: EdgeInsets.zero,
                      activeColor: colors.accent,
                    ),
                  ],
                ),
              ),
              const Divider(),
              const SizedBox(height: 8),
              Text('纸张配色', style: TextStyle(color: colors.fadedInk)),
              RadioGroup<JournalPalette>(
                groupValue: _preferences.palette,
                onChanged: (value) {
                  if (value != null) _change(palette: value);
                },
                child: Column(
                  children: [
                    _paletteOption(
                      context,
                      JournalPalette.antiquePaper,
                      '古纸',
                      '温暖的旧纸与棕色墨迹',
                    ),
                    _paletteOption(
                      context,
                      JournalPalette.plainWhite,
                      '素白',
                      '清爽的白纸与蓝灰墨迹',
                    ),
                    _paletteOption(
                      context,
                      JournalPalette.cyanPaper,
                      '青笺',
                      '淡青笺纸与深青墨迹',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('theme-settings-close'),
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paletteOption(
    BuildContext context,
    JournalPalette palette,
    String title,
    String subtitle,
  ) {
    final brightness = Theme.of(context).brightness;
    final preview = JournalTheme.fromPalette(palette, brightness);
    return RadioListTile<JournalPalette>(
      key: Key('theme-palette-${palette.name}'),
      value: palette,
      title: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: preview.paper,
              border: Border.all(color: preview.edge),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: preview.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Text(title),
        ],
      ),
      subtitle: Text(subtitle),
      contentPadding: EdgeInsets.zero,
      activeColor: journalThemeOf(context).accent,
    );
  }
}
