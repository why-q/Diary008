import 'dart:convert';

import 'package:diary008/font_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('font preference mapping', () {
    test('system selection leaves the theme unchanged', () {
      final theme = ThemeData();
      expect(
        applyFontPreference(theme, AppFontPreference.followSystem),
        same(theme),
      );
      expect(
        AppFontPreferenceDetails.fromStorage('not-a-font'),
        AppFontPreference.followSystem,
      );
    });

    test('maps every custom option to its Latin and Chinese families', () {
      final expected = {
        AppFontPreference.handwritten: ('CormorantGaramond', 'MaShanZheng'),
        AppFontPreference.book: ('Literata', 'NotoSerifSC'),
        AppFontPreference.clean: ('Inter', 'NotoSansSC'),
      };

      for (final entry in expected.entries) {
        final theme = applyFontPreference(ThemeData(), entry.key);
        expect(theme.textTheme.bodyMedium?.fontFamily, entry.value.$1);
        expect(
          theme.textTheme.bodyMedium?.fontFamilyFallback,
          contains(entry.value.$2),
        );
        expect(theme.primaryTextTheme.titleLarge?.fontFamily, entry.value.$1);
        expect(
          theme.primaryTextTheme.titleLarge?.fontFamilyFallback,
          contains(entry.value.$2),
        );
      }
    });
  });

  test('font families resolve to bundled fonts and license texts', () async {
    final fonts = (jsonDecode(
      await rootBundle.loadString('FontManifest.json'),
    ) as List<dynamic>).cast<Map<String, dynamic>>();
    const expected = {
      'MaShanZheng': (
        'assets/fonts/MaShanZheng.ttf',
        'assets/fonts/MaShanZheng-OFL.txt',
      ),
      'CormorantGaramond': (
        'assets/fonts/CormorantGaramond.ttf',
        'assets/fonts/CormorantGaramond-OFL.txt',
      ),
      'NotoSerifSC': (
        'assets/fonts/NotoSerifSC.ttf',
        'assets/fonts/NotoSerifSC-OFL.txt',
      ),
      'Literata': (
        'assets/fonts/Literata.ttf',
        'assets/fonts/Literata-OFL.txt',
      ),
      'NotoSansSC': (
        'assets/fonts/NotoSansSC.ttf',
        'assets/fonts/NotoSansSC-OFL.txt',
      ),
      'Inter': ('assets/fonts/Inter.ttf', 'assets/fonts/Inter-OFL.txt'),
    };

    for (final entry in expected.entries) {
      expect(
        fonts.any(
          (font) =>
              font['family'] == entry.key &&
              (font['fonts'] as List<dynamic>).any(
                (asset) => asset['asset'] == entry.value.$1,
              ),
        ),
        isTrue,
        reason: '${entry.key} must resolve to its local asset',
      );
      await rootBundle.load(entry.value.$1);
      expect(
        await rootBundle.loadString(entry.value.$2),
        contains('SIL OPEN FONT LICENSE Version 1.1'),
      );
    }
  });

  test('preference loads and persists independently', () async {
    final controller = FontPreferenceController();
    await controller.load();
    expect(controller.preference, AppFontPreference.followSystem);

    await controller.setPreference(AppFontPreference.book);
    expect(controller.preference, AppFontPreference.book);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('app_font_preference'), 'book');

    final restored = FontPreferenceController();
    await restored.load();
    expect(restored.preference, AppFontPreference.book);
    controller.dispose();
    restored.dispose();
  });

  testWidgets('changing the settings control updates app-wide default text', (
    tester,
  ) async {
    final controller = FontPreferenceController();
    await controller.load();

    Widget app() => AnimatedBuilder(
      animation: controller,
      builder: (context, _) => MaterialApp(
        theme: applyFontPreference(
          ThemeData(
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                textStyle: const TextStyle(fontSize: 19),
              ),
            ),
          ),
          controller.preference,
        ),
        home: Scaffold(
          body: Column(
            children: [
              const Text('Diary body', key: Key('global-default-text')),
              TextButton(
                key: const Key('global-font-button'),
                onPressed: () {},
                child: const Text('Themed button'),
              ),
              FontPreferenceSettings(controller: controller),
            ],
          ),
        ),
      ),
    );

    await tester.pumpWidget(app());
    String? globalFontFamily() => DefaultTextStyle.of(
      tester.element(find.byKey(const Key('global-default-text'))),
    ).style.fontFamily;
    String? themedButtonFontFamily() =>
        DefaultTextStyle.of(tester.element(find.text('Themed button')))
            .style
            .fontFamily;

    expect(globalFontFamily(), isNot('Literata'));
    await tester.tap(find.byKey(const Key('app-font-preference-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('经典书卷').last);
    await tester.pumpAndSettle();

    expect(globalFontFamily(), 'Literata');
    expect(themedButtonFontFamily(), 'Literata');
    expect(
      DefaultTextStyle.of(
        tester.element(find.byKey(const Key('global-default-text'))),
      ).style.fontFamilyFallback,
      contains('NotoSerifSC'),
    );

    await tester.tap(find.byKey(const Key('app-font-preference-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清爽阅读').last);
    await tester.pumpAndSettle();
    expect(globalFontFamily(), 'Inter');
    expect(themedButtonFontFamily(), 'Inter');
    controller.dispose();
  });
}
