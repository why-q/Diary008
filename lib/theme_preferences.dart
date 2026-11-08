import 'dart:convert';
import 'dart:io';

enum JournalThemeMode { system, light, dark }

enum JournalPalette { antiquePaper, plainWhite, cyanPaper }

class ThemePreferences {
  const ThemePreferences({
    this.mode = JournalThemeMode.system,
    this.palette = JournalPalette.antiquePaper,
  });

  final JournalThemeMode mode;
  final JournalPalette palette;

  ThemePreferences copyWith({
    JournalThemeMode? mode,
    JournalPalette? palette,
  }) => ThemePreferences(
    mode: mode ?? this.mode,
    palette: palette ?? this.palette,
  );

  Map<String, dynamic> toJson() => {'mode': mode.name, 'palette': palette.name};

  factory ThemePreferences.fromJson(Map<String, dynamic> json) {
    final mode = switch (json['mode']) {
      'system' => JournalThemeMode.system,
      'light' => JournalThemeMode.light,
      'dark' => JournalThemeMode.dark,
      _ => throw const FormatException('主题模式无效'),
    };
    final palette = switch (json['palette']) {
      'antiquePaper' => JournalPalette.antiquePaper,
      'plainWhite' => JournalPalette.plainWhite,
      'cyanPaper' => JournalPalette.cyanPaper,
      _ => throw const FormatException('纸张配色无效'),
    };
    return ThemePreferences(mode: mode, palette: palette);
  }

  @override
  bool operator ==(Object other) =>
      other is ThemePreferences &&
      other.mode == mode &&
      other.palette == palette;

  @override
  int get hashCode => Object.hash(mode, palette);
}

Future<ThemePreferences> readThemePreferences(File file) async {
  if (!await file.exists()) return const ThemePreferences();
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('主题偏好格式无效');
    }
    return ThemePreferences.fromJson(decoded);
  } on FormatException {
    rethrow;
  } on Object {
    throw FormatException('主题偏好读取失败');
  }
}

Future<void> writeThemePreferences(
  File file,
  ThemePreferences preferences,
) async {
  final temp = File('${file.path}.tmp');
  await temp.writeAsString(
    '${jsonEncode(preferences.toJson())}\n',
    flush: true,
  );
  await temp.rename(file.path);
}
