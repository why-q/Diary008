import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:diary008/font_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

late Directory cacheRoot;

Future<Uint8List> sourceFont(String fileName) async =>
    Uint8List.fromList(await File('assets/fonts/$fileName').readAsBytes());

FontPreferenceController makeController({
  String downloadBaseUrl = 'https://fonts.example.invalid/diary008',
  FontAssetDownloader? downloader,
  FontLoaderCallback? fontLoader,
}) => FontPreferenceController(
  downloadBaseUrl: downloadBaseUrl,
  cacheDirectoryProvider: () async => cacheRoot,
  downloader:
      downloader ??
      (uri, {required expectedLength, required cancellation}) =>
          sourceFont(uri.pathSegments.last),
  fontLoader: fontLoader ?? (family, bytes) async {},
);

Future<Directory> writeCache(FontBundleResource bundle) async {
  final directory = Directory(
    '${cacheRoot.path}/${bundle.preference.name}-00000000000000000001',
  );
  await directory.create(recursive: true);
  for (final resource in bundle.files) {
    await File('${directory.path}/${resource.fileName}')
        .writeAsBytes(await sourceFont(resource.fileName));
  }
  return directory;
}

Future<void> waitForPreference(
  FontPreferenceController controller,
  AppFontPreference preference,
) async {
  await testerRunAsync(() async {
    for (var tries = 0; tries < 100; tries++) {
      if (controller.preference == preference) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Font preference did not change to $preference.');
  });
}

Future<void> testerRunAsync(Future<void> Function() callback) async {
  // Filled by the widget test through the active TestWidgetsFlutterBinding.
  await TestWidgetsFlutterBinding.ensureInitialized().runAsync(callback);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cacheRoot = await Directory.systemTemp.createTemp('diary008-font-test-');
  });

  tearDown(() async {
    if (await cacheRoot.exists()) await cacheRoot.delete(recursive: true);
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

  test(
    'only handwritten fonts are bundled; all licenses and hashes are valid',
    () async {
      final fonts = (jsonDecode(
        await rootBundle.loadString('FontManifest.json'),
      ) as List<dynamic>).cast<Map<String, dynamic>>();
      const bundled = {
        'MaShanZheng': 'assets/fonts/MaShanZheng.ttf',
        'CormorantGaramond': 'assets/fonts/CormorantGaramond.ttf',
      };
      for (final entry in bundled.entries) {
        expect(
          fonts.any(
            (font) =>
                font['family'] == entry.key &&
                (font['fonts'] as List<dynamic>).any(
                  (asset) => asset['asset'] == entry.value,
                ),
          ),
          isTrue,
        );
        await rootBundle.load(entry.value);
      }

      final manifestFamilies = fonts.map((font) => font['family']).toSet();
      expect(manifestFamilies, isNot(contains('NotoSerifSC')));
      expect(manifestFamilies, isNot(contains('Literata')));
      expect(manifestFamilies, isNot(contains('NotoSansSC')));
      expect(manifestFamilies, isNot(contains('Inter')));

      for (final bundle in [bookFontBundle, cleanFontBundle]) {
        for (final resource in bundle.files) {
          final bytes = await sourceFont(resource.fileName);
          expect(bytes.length, resource.byteLength, reason: resource.fileName);
          final digest = await Sha256().hash(bytes);
          final actual = digest.bytes
              .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
              .join();
          expect(actual, resource.sha256, reason: resource.fileName);
        }
      }

      const licenses = {
        'MaShanZheng-OFL.txt',
        'CormorantGaramond-OFL.txt',
        'NotoSerifSC-OFL.txt',
        'NotoSansSC-OFL.txt',
        'Literata-OFL.txt',
        'Inter-OFL.txt',
      };
      for (final license in licenses) {
        expect(
          await rootBundle.loadString('assets/fonts/$license'),
          contains('SIL OPEN FONT LICENSE Version 1.1'),
          reason: license,
        );
      }
    },
  );

  test(
    'preference loads and persists after a valid font set is available',
    () async {
      final controller = makeController();
      await controller.load();
      expect(controller.preference, AppFontPreference.followSystem);

      await controller.setPreference(AppFontPreference.book);
      expect(controller.preference, AppFontPreference.book);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('app_font_preference'), 'book');

      final restored = makeController();
      await restored.load();
      expect(restored.preference, AppFontPreference.book);
      controller.dispose();
      restored.dispose();
    },
  );

  test(
    'valid cache hit avoids network and dynamically registers both fonts',
    () async {
      await writeCache(bookFontBundle);
      final registered = <String>[];
      var downloads = 0;
      final controller = makeController(
        downloader:
            (uri, {required expectedLength, required cancellation}) async {
              downloads++;
              throw StateError('A cache hit must not download.');
            },
        fontLoader: (family, bytes) async => registered.add(family),
      );
      await controller.load();

      await controller.setPreference(AppFontPreference.book);

      expect(downloads, 0);
      expect(registered, ['NotoSerifSC', 'Literata']);
      expect(controller.preference, AppFontPreference.book);
      controller.dispose();
    },
  );

  test(
    'startup restores selected fonts from a validated offline cache',
    () async {
      await writeCache(cleanFontBundle);
      SharedPreferences.setMockInitialValues({'app_font_preference': 'clean'});
      final registered = <String>[];
      final controller = makeController(
        downloader:
            (uri, {required expectedLength, required cancellation}) async {
              throw StateError('Startup restore must use cache while offline.');
            },
        fontLoader: (family, bytes) async => registered.add(family),
      );

      await controller.load();

      expect(controller.preference, AppFontPreference.clean);
      expect(registered, ['NotoSansSC', 'Inter']);
      controller.dispose();
    },
  );

  test('bad hash leaves the previous choice and storage unchanged', () async {
    final controller = makeController(
      downloader:
          (uri, {required expectedLength, required cancellation}) async {
            final valid = await sourceFont(uri.pathSegments.last);
            valid[0] ^= 0xff;
            return valid;
          },
    );
    await controller.load();
    await controller.setPreference(AppFontPreference.handwritten);
    final oldPref = await SharedPreferences.getInstance();

    await expectLater(
      controller.setPreference(AppFontPreference.book),
      throwsA(isA<FormatException>()),
    );

    expect(controller.preference, AppFontPreference.handwritten);
    expect(oldPref.getString('app_font_preference'), 'handwritten');
    expect(controller.lastError, contains('仍保留原字体设置'));
    expect(
      (await cacheRoot.list(followLinks: false).toList())
          .whereType<Directory>(),
      isEmpty,
    );
    controller.dispose();
  });

  test(
    'partial download does not commit a set and can be retried successfully',
    () async {
      var failSecondFile = true;
      var calls = 0;
      final registered = <String>[];
      final controller = makeController(
        downloader:
            (uri, {required expectedLength, required cancellation}) async {
              calls++;
              if (failSecondFile && uri.pathSegments.last == 'Literata.ttf') {
                throw const SocketException('offline');
              }
              return sourceFont(uri.pathSegments.last);
            },
        fontLoader: (family, bytes) async => registered.add(family),
      );
      await controller.load();
      await controller.setPreference(AppFontPreference.handwritten);

      await expectLater(
        controller.setPreference(AppFontPreference.book),
        throwsA(isA<SocketException>()),
      );
      expect(controller.preference, AppFontPreference.handwritten);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'app_font_preference',
        ),
        'handwritten',
      );
      expect(
        (await cacheRoot.list(followLinks: false).toList())
            .whereType<Directory>(),
        isEmpty,
      );

      failSecondFile = false;
      await controller.retry();
      expect(controller.preference, AppFontPreference.book);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'app_font_preference',
        ),
        'book',
      );
      expect(calls, 4);
      expect(registered, ['NotoSerifSC', 'Literata']);
      expect(controller.lastError, isNull);
      controller.dispose();
    },
  );

  test('cancelled download retains old setting and exposes retry', () async {
    final started = Completer<void>();
    var block = true;
    final controller = makeController(
      downloader: (uri, {required expectedLength, required cancellation}) {
        if (!block) return sourceFont(uri.pathSegments.last);
        started.complete();
        final result = Completer<Uint8List>();
        cancellation.onCancel(() {
          if (!result.isCompleted) {
            result.completeError(const FontDownloadCancelledException());
          }
        });
        return result.future;
      },
    );
    await controller.load();
    await controller.setPreference(AppFontPreference.handwritten);
    final pending = controller.setPreference(AppFontPreference.clean);
    await started.future;
    controller.cancelDownload();
    await expectLater(pending, throwsA(isA<FontDownloadCancelledException>()));

    expect(controller.preference, AppFontPreference.handwritten);
    expect(
      (await SharedPreferences.getInstance()).getString('app_font_preference'),
      'handwritten',
    );
    expect(controller.lastError, contains('已取消'));
    expect(controller.pendingPreference, AppFontPreference.clean);

    block = false;
    await controller.retry();
    expect(controller.preference, AppFontPreference.clean);
    expect(
      (await SharedPreferences.getInstance()).getString('app_font_preference'),
      'clean',
    );
    controller.dispose();
  });

  test(
    'an absent or non-HTTPS source is reported without changing selection',
    () async {
      final controller = makeController(
        downloadBaseUrl: 'http://fonts.invalid',
      );
      await controller.load();
      await controller.setPreference(AppFontPreference.handwritten);

      await expectLater(
        controller.setPreference(AppFontPreference.book),
        throwsA(isA<FontDownloadSourceNotConfiguredException>()),
      );

      expect(controller.preference, AppFontPreference.handwritten);
      expect(controller.lastError, contains('尚未配置'));
      controller.dispose();
    },
  );

  testWidgets('settings selection updates app-wide text and themed buttons', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await writeCache(bookFontBundle);
      await writeCache(cleanFontBundle);
    });
    final controller = makeController();
    await tester.runAsync(controller.load);

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
    await tester.runAsync(
      () => controller.setPreference(AppFontPreference.book),
    );
    expect(controller.preference, AppFontPreference.book);
    await tester.pumpAndSettle();

    expect(globalFontFamily(), 'Literata');
    expect(themedButtonFontFamily(), 'Literata');
    expect(
      DefaultTextStyle.of(
        tester.element(find.byKey(const Key('global-default-text'))),
      ).style.fontFamilyFallback,
      contains('NotoSerifSC'),
    );

    await tester.runAsync(
      () => controller.setPreference(AppFontPreference.clean),
    );
    expect(controller.preference, AppFontPreference.clean);
    await tester.pumpAndSettle();
    expect(globalFontFamily(), 'Inter');
    expect(themedButtonFontFamily(), 'Inter');
    controller.dispose();
  });
}
