import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

enum AppLanguage { system, simplifiedChinese, english }

extension AppLanguageStorage on AppLanguage {
  String get storageValue => switch (this) {
    AppLanguage.system => 'system',
    AppLanguage.simplifiedChinese => 'zh-CN',
    AppLanguage.english => 'en',
  };

  String get localeName => switch (this) {
    AppLanguage.system => 'system',
    AppLanguage.simplifiedChinese => 'zh_CN',
    AppLanguage.english => 'en',
  };

  Locale? get locale => switch (this) {
    AppLanguage.system => null,
    AppLanguage.simplifiedChinese => const Locale('zh', 'CN'),
    AppLanguage.english => const Locale('en'),
  };

  static AppLanguage fromStorage(Object? value) => switch (value) {
    'zh-CN' => AppLanguage.simplifiedChinese,
    'en' => AppLanguage.english,
    _ => AppLanguage.system,
  };
}

abstract interface class LanguageSettingsStore {
  Future<AppLanguage> load();
  Future<void> save(AppLanguage language);
}

class FileLanguageSettingsStore implements LanguageSettingsStore {
  FileLanguageSettingsStore(this.file);

  static const fileName = 'language_preferences.json';
  final File file;

  static Future<FileLanguageSettingsStore>
  inApplicationDocumentsDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    return FileLanguageSettingsStore(File('${directory.path}/$fileName'));
  }

  @override
  Future<AppLanguage> load() async {
    if (!await file.exists()) return AppLanguage.system;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return AppLanguage.system;
      return AppLanguageStorage.fromStorage(json['language']);
    } on FormatException {
      return AppLanguage.system;
    } on IOException {
      return AppLanguage.system;
    }
  }

  @override
  Future<void> save(AppLanguage language) async {
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({'language': language.storageValue}),
      flush: true,
    );
    await temp.rename(file.path);
  }
}

class MemoryLanguageSettingsStore implements LanguageSettingsStore {
  MemoryLanguageSettingsStore([this.language = AppLanguage.system]);

  AppLanguage language;

  @override
  Future<AppLanguage> load() async => language;

  @override
  Future<void> save(AppLanguage language) async => this.language = language;
}
