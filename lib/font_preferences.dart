import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_localizations.dart';

const _fontPreferenceStorageKey = 'app_font_preference';
const fontDownloadBaseUrl = String.fromEnvironment('DIARY008_FONT_BASE_URL');

enum AppFontPreference { followSystem, handwritten, book, clean }

extension AppFontPreferenceDetails on AppFontPreference {
  String get label => switch (this) {
    AppFontPreference.followSystem => '跟随系统',
    AppFontPreference.handwritten => '古朴手写',
    AppFontPreference.book => '经典书卷',
    AppFontPreference.clean => '清爽阅读',
  };

  String localizedLabel(AppLocalizations l10n) => switch (this) {
    AppFontPreference.followSystem => l10n.fontFollowSystem,
    AppFontPreference.handwritten => l10n.fontHandwritten,
    AppFontPreference.book => l10n.fontBook,
    AppFontPreference.clean => l10n.fontClean,
  };

  String localizedDescription(AppLocalizations l10n) => switch (this) {
    AppFontPreference.followSystem => l10n.fontFollowSystemDescription,
    AppFontPreference.handwritten => l10n.fontHandwrittenDescription,
    AppFontPreference.book => l10n.fontBookDescription,
    AppFontPreference.clean => l10n.fontCleanDescription,
  };

  String get description => switch (this) {
    AppFontPreference.followSystem => '使用设备的默认字体',
    AppFontPreference.handwritten => 'Ma Shan Zheng · Cormorant Garamond（内置）',
    AppFontPreference.book => 'Noto Serif SC · Literata（首次选择时下载）',
    AppFontPreference.clean => 'Noto Sans SC · Inter（首次选择时下载）',
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

/// Pinned SHA-256 and source lengths for the Google Fonts files in assets/fonts.
/// Lengths are checked first to bound network reads; hashes are authoritative.
class FontFileResource {
  const FontFileResource({
    required this.family,
    required this.fileName,
    required this.byteLength,
    required this.sha256,
  });

  final String family;
  final String fileName;
  final int byteLength;
  final String sha256;
}

class FontBundleResource {
  const FontBundleResource({required this.preference, required this.files});

  final AppFontPreference preference;
  final List<FontFileResource> files;
}

const bookFontBundle = FontBundleResource(
  preference: AppFontPreference.book,
  files: [
    FontFileResource(
      family: 'NotoSerifSC',
      fileName: 'NotoSerifSC.ttf',
      byteLength: 2640524,
      sha256:
          '2dbb4ed2ede1db0c72d8ea4e8e66beb9b39e70c73f377636721a03959b25585a',
    ),
    FontFileResource(
      family: 'Literata',
      fileName: 'Literata.ttf',
      byteLength: 955132,
      sha256:
          'b41138c9373112f32abb589cc22e8674b06ed4048b0c513be922bdd26f274440',
    ),
  ],
);

const cleanFontBundle = FontBundleResource(
  preference: AppFontPreference.clean,
  files: [
    FontFileResource(
      family: 'NotoSansSC',
      fileName: 'NotoSansSC.ttf',
      byteLength: 1914844,
      sha256:
          '50a546b9d73075e841f78e170e4fda0e806f3bcc40b3089d80d8c6f63d40cc1b',
    ),
    FontFileResource(
      family: 'Inter',
      fileName: 'Inter.ttf',
      byteLength: 876576,
      sha256:
          '29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031',
    ),
  ],
);

FontBundleResource? fontBundleFor(AppFontPreference preference) =>
    switch (preference) {
      AppFontPreference.book => bookFontBundle,
      AppFontPreference.clean => cleanFontBundle,
      AppFontPreference.followSystem || AppFontPreference.handwritten => null,
    };

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
    snackBarTheme: theme.snackBarTheme.copyWith(
      contentTextStyle: applyFont(theme.snackBarTheme.contentTextStyle),
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

class FontDownloadCancelledException implements Exception {
  const FontDownloadCancelledException();
}

class FontDownloadSourceNotConfiguredException implements Exception {
  const FontDownloadSourceNotConfiguredException();
}

/// Cooperative cancellation passed to the downloader, also used to abort its
/// in-flight HttpClient request when the user presses Cancel.
class FontDownloadCancellation {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};

  bool get isCancelled => _cancelled;

  void throwIfCancelled() {
    if (_cancelled) throw const FontDownloadCancelledException();
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  void Function() onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

typedef FontAssetDownloader = Future<Uint8List> Function(
  Uri uri, {
  required int expectedLength,
  required FontDownloadCancellation cancellation,
});
typedef FontLoaderCallback = Future<void> Function(
  String family,
  Uint8List fontBytes,
);
typedef FontCacheDirectoryProvider = Future<Directory> Function();

String _directoryName(Directory directory) => directory.path
    .split(Platform.pathSeparator)
    .where((part) => part.isNotEmpty)
    .last;

class _CachedFontBundle {
  const _CachedFontBundle(this.directory, this.fontBytes);

  final Directory directory;
  final Map<String, Uint8List> fontBytes;
}

class FontPreferenceController extends ChangeNotifier {
  FontPreferenceController({
    String? downloadBaseUrl,
    FontAssetDownloader? downloader,
    FontLoaderCallback? fontLoader,
    FontCacheDirectoryProvider? cacheDirectoryProvider,
    this._preferenceLoader,
  }) : _downloadBaseUrl = downloadBaseUrl ?? fontDownloadBaseUrl,
       _downloader = downloader ?? _httpDownload,
       _fontLoader = fontLoader ?? _loadFont,
       _cacheDirectoryProvider =
           cacheDirectoryProvider ?? _defaultFontCacheDirectory;

  final Future<AppFontPreference> Function()? _preferenceLoader;
  final String _downloadBaseUrl;
  final FontAssetDownloader _downloader;
  final FontLoaderCallback _fontLoader;
  final FontCacheDirectoryProvider _cacheDirectoryProvider;
  final Set<String> _loadedFamilies = {};
  AppFontPreference _preference = AppFontPreference.followSystem;
  Future<void>? _loading;
  FontDownloadCancellation? _cancellation;
  AppFontPreference? _pendingPreference;
  String? _lastError;
  bool _isBusy = false;
  bool _disposed = false;

  AppFontPreference get preference => _preference;
  bool get isBusy => _isBusy;
  AppFontPreference? get pendingPreference => _pendingPreference;
  String? get lastError => _lastError;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final saved = _preferenceLoader != null
          ? await _preferenceLoader()
          : AppFontPreferenceDetails.fromStorage(
              (await SharedPreferences.getInstance()).getString(
                _fontPreferenceStorageKey,
              ),
            );
      final bundle = fontBundleFor(saved);
      if (bundle == null) {
        _preference = saved;
      } else {
        final cached = await _findValidCache(bundle);
        if (cached == null) {
          _lastError = '已选字体缓存不可用；请重新选择并下载字体。';
        } else {
          await _registerBundle(bundle, cached);
          _preference = saved;
        }
      }
    } catch (_) {
      // Storage or cache problems must not prevent the diary from opening.
      _preference = AppFontPreference.followSystem;
      _lastError = '字体偏好或缓存无法读取，已暂用系统字体。';
    }
    _notifyIfAlive();
  }

  Future<void> setPreference(AppFontPreference preference) async {
    if (_loading != null) await _loading;
    if (_disposed || preference == _preference) return;
    if (_isBusy) throw StateError('字体操作正在进行中。');

    final bundle = fontBundleFor(preference);
    final cancellation = FontDownloadCancellation();
    _cancellation = cancellation;
    _pendingPreference = preference;
    _lastError = null;
    _isBusy = true;
    _notifyIfAlive();

    try {
      if (bundle != null) {
        var cached = await _findValidCache(bundle);
        if (cached == null) {
          final baseUri = _validatedBaseUri(_downloadBaseUrl);
          if (baseUri == null) {
            throw const FontDownloadSourceNotConfiguredException();
          }
          cached = await _downloadBundle(bundle, baseUri, cancellation);
        }
        cancellation.throwIfCancelled();
        await _registerBundle(bundle, cached);
      }

      cancellation.throwIfCancelled();
      if (_disposed) return;
      final preferences = await SharedPreferences.getInstance();
      final saved = await preferences.setString(
        _fontPreferenceStorageKey,
        preference.name,
      );
      if (!saved) throw StateError('字体偏好无法保存。');
      if (_disposed) return;

      _preference = preference;
      _pendingPreference = null;
      _lastError = null;
    } catch (error) {
      if (!_disposed) _lastError = _friendlyError(error);
      rethrow;
    } finally {
      _cancellation = null;
      _isBusy = false;
      _notifyIfAlive();
    }
  }

  Future<void> retry() async {
    final target = _pendingPreference;
    if (target != null && !_isBusy) await setPreference(target);
  }

  void cancelDownload() => _cancellation?.cancel();

  String _friendlyError(Object error) => switch (error) {
    FontDownloadSourceNotConfiguredException() =>
      '字体下载源尚未配置；请等待应用提供安全的 HTTPS 字体源。',
    FontDownloadCancelledException() => '字体下载已取消，仍保留原字体设置。可重新选择再试。',
    _ => '字体下载、校验或加载失败，仍保留原字体设置。请检查网络后重试。',
  };

  Future<_CachedFontBundle?> _findValidCache(FontBundleResource bundle) async {
    final root = await _cacheDirectoryProvider();
    if (!await root.exists()) return null;
    final prefix = '${bundle.preference.name}-';
    final candidates = <Directory>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is Directory && _directoryName(entity).startsWith(prefix)) {
        candidates.add(entity);
      }
    }
    candidates.sort((a, b) => _directoryName(b).compareTo(_directoryName(a)));
    for (final candidate in candidates) {
      final cached = await _readValidBundle(bundle, candidate);
      if (cached != null) return cached;
    }
    return null;
  }

  Future<_CachedFontBundle?> _readValidBundle(
    FontBundleResource bundle,
    Directory directory,
  ) async {
    try {
      final fontBytes = <String, Uint8List>{};
      for (final resource in bundle.files) {
        final bytes = Uint8List.fromList(
          await File('${directory.path}/${resource.fileName}').readAsBytes(),
        );
        if (!await _matches(resource, bytes)) return null;
        fontBytes[resource.family] = bytes;
      }
      return _CachedFontBundle(directory, fontBytes);
    } catch (_) {
      return null;
    }
  }

  Future<_CachedFontBundle> _downloadBundle(
    FontBundleResource bundle,
    Uri baseUri,
    FontDownloadCancellation cancellation,
  ) async {
    final root = await _cacheDirectoryProvider();
    await root.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch.toString().padLeft(
      20,
      '0',
    );
    final staging = Directory(
      '${root.path}/.staging-${bundle.preference.name}-$stamp',
    );
    await staging.create();
    try {
      final bytesByFamily = <String, Uint8List>{};
      for (final resource in bundle.files) {
        cancellation.throwIfCancelled();
        final uri = _fontUri(baseUri, resource.fileName);
        final bytes = await _downloader(
          uri,
          expectedLength: resource.byteLength,
          cancellation: cancellation,
        );
        cancellation.throwIfCancelled();
        if (!await _matches(resource, bytes)) {
          throw const FormatException('字体文件长度或 SHA-256 不匹配。');
        }
        await File('${staging.path}/${resource.fileName}')
            .writeAsBytes(bytes, flush: true);
        bytesByFamily[resource.family] = bytes;
      }
      cancellation.throwIfCancelled();

      var suffix = int.parse(stamp);
      var target = Directory('${root.path}/${bundle.preference.name}-$stamp');
      while (await target.exists()) {
        suffix++;
        target = Directory(
          '${root.path}/${bundle.preference.name}-${suffix.toString().padLeft(20, '0')}',
        );
      }
      final committed = await staging.rename(target.path);
      return _CachedFontBundle(committed, bytesByFamily);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<bool> _matches(FontFileResource resource, Uint8List bytes) async {
    if (bytes.length != resource.byteLength) return false;
    final digest = await Sha256().hash(bytes);
    final actual = digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return actual == resource.sha256;
  }

  Future<void> _registerBundle(
    FontBundleResource bundle,
    _CachedFontBundle cached,
  ) async {
    for (final resource in bundle.files) {
      if (_loadedFamilies.contains(resource.family)) continue;
      final bytes = cached.fontBytes[resource.family];
      if (bytes == null) throw StateError('字体缓存缺少 ${resource.family}。');
      await _fontLoader(resource.family, bytes);
      _loadedFamilies.add(resource.family);
    }
  }

  static Uri? _validatedBaseUri(String value) {
    if (value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    return uri;
  }

  static Uri _fontUri(Uri base, String fileName) {
    final baseText = base.toString().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$baseText/${Uri.encodeComponent(fileName)}');
  }

  void _notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancellation?.cancel();
    super.dispose();
  }
}

Future<Directory> _defaultFontCacheDirectory() async {
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}/diary008-fonts');
}

Future<Uint8List> _httpDownload(
  Uri uri, {
  required int expectedLength,
  required FontDownloadCancellation cancellation,
}) async {
  if (uri.scheme != 'https' || uri.host.isEmpty) {
    throw const FontDownloadSourceNotConfiguredException();
  }
  cancellation.throwIfCancelled();
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  HttpClientRequest? request;
  void Function() removeCancellationListener = () {};
  try {
    request = await client.getUrl(uri).timeout(const Duration(seconds: 30));
    cancellation.throwIfCancelled();
    request.followRedirects = false;
    removeCancellationListener = cancellation.onCancel(
      () => request?.abort(const FontDownloadCancelledException()),
    );
    final response = await request.close().timeout(const Duration(seconds: 45));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Font server returned ${response.statusCode}.',
        uri: uri,
      );
    }
    return await readFontResponseBody(
      response,
      expectedLength: expectedLength,
      cancellation: cancellation,
      idleTimeout: const Duration(seconds: 30),
    );
  } finally {
    removeCancellationListener();
    client.close(force: true);
  }
}

/// Collects a bounded HTTP body while enforcing an inactivity timeout per chunk.
Future<Uint8List> readFontResponseBody(
  Stream<List<int>> response, {
  required int expectedLength,
  required FontDownloadCancellation cancellation,
  Duration idleTimeout = const Duration(seconds: 30),
}) async {
  final builder = BytesBuilder(copy: false);
  var length = 0;
  await for (final chunk in response.timeout(idleTimeout)) {
    cancellation.throwIfCancelled();
    length += chunk.length;
    if (length > expectedLength) {
      throw const FormatException('字体下载超过预期文件大小。');
    }
    builder.add(chunk);
  }
  cancellation.throwIfCancelled();
  return builder.takeBytes();
}

Future<void> _loadFont(String family, Uint8List fontBytes) async {
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.sublistView(fontBytes)));
  await loader.load();
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
      // The controller retains the prior choice and exposes a retry message.
    }
  }

  String _localizedError(String error, AppLocalizations l10n) {
    if (error.contains('下载源尚未配置')) return l10n.fontSourceNotConfigured;
    if (error.contains('下载已取消')) return l10n.fontDownloadCancelled;
    if (error.contains('缓存不可用')) return l10n.fontUnavailable;
    if (error.contains('无法读取')) return l10n.fontPreferencesUnavailable;
    return l10n.fontDownloadFailed;
  }

  Future<void> _retry() async {
    try {
      await widget.controller.retry();
    } catch (_) {
      // Keep the failed target available for another retry.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.fontSettingTitle),
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => DropdownButtonFormField<AppFontPreference>(
            key: const Key('app-font-preference-dropdown'),
            initialValue: widget.controller.preference,
            decoration: InputDecoration(
              labelText: l10n.fontSettingStyle,
              border: const OutlineInputBorder(),
            ),
            items: AppFontPreference.values
                .map(
                  (preference) => DropdownMenuItem(
                    value: preference,
                    child: Text(preference.localizedLabel(l10n)),
                  ),
                )
                .toList(growable: false),
            onChanged: widget.controller.isBusy ? null : _select,
          ),
        ),
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => Text(
            widget.controller.preference.localizedDescription(l10n),
            key: const Key('app-font-preference-description'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 4),
        Text(l10n.fontDownloadPrivacy, style: const TextStyle(fontSize: 12)),
        AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            if (widget.controller.isBusy) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    l10n.fontDownloading(
                      widget.controller.pendingPreference?.localizedLabel(
                            l10n,
                          ) ??
                          '',
                    ),
                  ),
                  TextButton(
                    onPressed: widget.controller.cancelDownload,
                    child: Text(l10n.cancelDownload),
                  ),
                ],
              );
            }
            final error = widget.controller.lastError;
            if (error == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _localizedError(error, l10n),
                    key: const Key('font-preference-error'),
                  ),
                  if (widget.controller.pendingPreference != null)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        key: const Key('font-preference-retry'),
                        onPressed: _retry,
                        child: Text(l10n.retryDownload),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
