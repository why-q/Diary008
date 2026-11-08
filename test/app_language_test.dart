import 'dart:io';

import 'package:diary008/app_language.dart';
import 'package:diary008/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('language preference', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('diary008-language-');
    });

    tearDown(() => directory.delete(recursive: true));

    test('persists each supported selection and restores it', () async {
      final store = FileLanguageSettingsStore(
        File('${directory.path}/language.json'),
      );

      expect(await store.load(), AppLanguage.system);
      await store.save(AppLanguage.english);
      expect(await store.load(), AppLanguage.english);
      await store.save(AppLanguage.simplifiedChinese);
      expect(await store.load(), AppLanguage.simplifiedChinese);
      await store.save(AppLanguage.system);
      expect(await store.load(), AppLanguage.system);
    });

    test(
      'invalid persisted data safely falls back to system language',
      () async {
        final store = FileLanguageSettingsStore(
          File('${directory.path}/language.json'),
        );
        await store.file.writeAsString('{"language":"unsupported"}');

        expect(await store.load(), AppLanguage.system);
      },
    );
  });

  group('localized copy', () {
    final chinese = AppLocalizations.forLocale(const Locale('zh', 'CN'));
    final english = AppLocalizations.forLocale(const Locale('en'));
    final date = DateTime(2026, 11, 8);

    test('formats dates and volume labels in the selected language', () {
      expect(chinese.dateFormat(date), '二〇二六年十一月八日');
      expect(english.dateFormat(date), 'November 8, 2026');
      expect(chinese.volumeTitle(3, ''), '卷三');
      expect(english.volumeTitle(3, ''), 'Volume 3');
    });

    test(
      'provides notification channel and body text in the selected language',
      () {
        expect(chinese.notificationChannelName, '笔记提醒');
        expect(chinese.dailyNotificationBody, contains('翻阅笔记'));
        expect(english.notificationChannelName, 'Notebook reminders');
        expect(english.dailyNotificationBody, contains('read the notebook'));
        expect(english.assertionNotificationBody, contains('assertions'));
      },
    );
  });
}
