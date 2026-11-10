import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:diary008/volume_name_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

import 'app_language.dart';
import 'app_licenses.dart';
import 'app_localizations.dart';
import 'entry_editor.dart';
import 'journal_page.dart';
import 'journal_theme.dart';
import 'notebook.dart';
import 'notebook_storage.dart';
import 'notebook_backup.dart';
import 'backup_encryption.dart';
import 'backup_password_dialog.dart';
import 'volume_picker.dart';
import 'reminder_preferences.dart';
import 'reminder_service.dart';
import 'reminder_settings.dart';
import 'data_settings.dart';
import 'diagnostics.dart';
import 'theme_preferences.dart';
import 'theme_settings.dart';
import 'font_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerAppFontLicenses();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      Diagnostics.record(
        'flutter.error',
        '${details.exception.runtimeType}\n${details.stack}',
      ),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(Diagnostics.record('dart.error', '${error.runtimeType}\n$stack'));
    return false;
  };
  unawaited(Diagnostics.record('app.start', 'version=0.4.0+4'));
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: paper,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const DiaryApp());
}

@pragma('vm:entry-point')
Future<void> reminderBackgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  var success = false;
  try {
    await ReminderService.instance.refreshFromDisk();
    success = true;
  } catch (error, stack) {
    await Diagnostics.record(
      'reminder.background.failed',
      '${error.runtimeType}\n$stack',
    );
  } finally {
    await ReminderService.runtimeChannel.invokeMethod<void>(
      'complete',
      success,
    );
  }
}

class DiaryApp extends StatefulWidget {
  const DiaryApp({super.key});

  @override
  State<DiaryApp> createState() => _DiaryAppState();
}

class _DiaryAppState extends State<DiaryApp> {
  AppLanguage _language = AppLanguage.system;
  LanguageSettingsStore? _languageStore;
  ThemePreferences _themePreferences = const ThemePreferences();
  Future<void> _themeSaveQueue = Future<void>.value();
  int _themeRevision = 0;
  ThemePreferences? _pendingThemePreferences;
  final _fontPreferenceController = FontPreferenceController();

  @override
  void initState() {
    super.initState();
    unawaited(_loadLanguage());
    unawaited(_loadThemePreferences());
    unawaited(_fontPreferenceController.load());
  }

  Future<void> _loadLanguage() async {
    final store =
        await FileLanguageSettingsStore.inApplicationDocumentsDirectory();
    final language = await store.load();
    _languageStore = store;
    if (mounted) setState(() => _language = language);
  }

  Future<void> _changeLanguage(AppLanguage language) async {
    final store = _languageStore ??=
        await FileLanguageSettingsStore.inApplicationDocumentsDirectory();
    await store.save(language);
    if (mounted) setState(() => _language = language);
  }

  Future<void> _loadThemePreferences() async {
    final revision = _themeRevision;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final preferences = await readThemePreferences(
        File('${directory.path}/theme_preferences.json'),
      );
      if (mounted && revision == _themeRevision) {
        setState(() => _themePreferences = preferences);
      }
    } catch (error, stack) {
      await Diagnostics.record(
        'theme.preferences.read.failed',
        '${error.runtimeType}\n$stack',
      );
    }
  }

  void _changeThemePreferences(ThemePreferences preferences) {
    if (_themePreferences == preferences) return;
    _themeRevision++;
    _pendingThemePreferences = preferences;
    setState(() => _themePreferences = preferences);
    _themeSaveQueue = _themeSaveQueue.then((_) async {
      final toSave = _pendingThemePreferences;
      _pendingThemePreferences = null;
      if (toSave == null) return;
      try {
        final directory = await getApplicationDocumentsDirectory();
        await writeThemePreferences(
          File('${directory.path}/theme_preferences.json'),
          toSave,
        );
      } catch (error, stack) {
        await Diagnostics.record(
          'theme.preferences.write.failed',
          '${error.runtimeType}\n$stack',
        );
      }
    });
  }

  @override
  void dispose() {
    _fontPreferenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = switch (_themePreferences.mode) {
      JournalThemeMode.system => ThemeMode.system,
      JournalThemeMode.light => ThemeMode.light,
      JournalThemeMode.dark => ThemeMode.dark,
    };
    return AnimatedBuilder(
      animation: _fontPreferenceController,
      builder: (context, _) => MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        debugShowCheckedModeBanner: false,
        locale: _language.locale,
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localeResolutionCallback: (locale, supportedLocales) =>
            locale?.languageCode == 'zh'
            ? const Locale('zh', 'CN')
            : const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        builder: (context, child) {
          final brightness = _themePreferences.mode == JournalThemeMode.dark
              ? Brightness.dark
              : _themePreferences.mode == JournalThemeMode.light
              ? Brightness.light
              : MediaQuery.platformBrightnessOf(context);
          final colors = JournalTheme.fromPalette(
            _themePreferences.palette,
            brightness,
          );
          final dark = brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: dark
                  ? Brightness.light
                  : Brightness.dark,
              systemNavigationBarColor: colors.paper,
              systemNavigationBarIconBrightness: dark
                  ? Brightness.light
                  : Brightness.dark,
            ),
            child: child!,
          );
        },
        theme: applyFontPreference(
          journalThemeData(_themePreferences.palette, Brightness.light),
          _fontPreferenceController.preference,
        ),
        darkTheme: applyFontPreference(
          journalThemeData(_themePreferences.palette, Brightness.dark),
          _fontPreferenceController.preference,
        ),
        themeMode: mode,
        home: NotebookPage(
          language: _language,
          onLanguageChanged: _changeLanguage,
          themePreferences: _themePreferences,
          onThemeChanged: _changeThemePreferences,
          fontPreferenceController: _fontPreferenceController,
        ),
      ),
    );
  }
}

class NotebookPage extends StatefulWidget {
  const NotebookPage({
    super.key,
    required this.language,
    required this.onLanguageChanged,
    required this.themePreferences,
    required this.onThemeChanged,
    required this.fontPreferenceController,
  });

  final AppLanguage language;
  final Future<void> Function(AppLanguage language) onLanguageChanged;
  final ThemePreferences themePreferences;
  final ValueChanged<ThemePreferences> onThemeChanged;
  final FontPreferenceController fontPreferenceController;
  @override
  State<NotebookPage> createState() => _NotebookPageState();
}

class _NotebookPageState extends State<NotebookPage>
    with WidgetsBindingObserver {
  Notebook? _book;
  File? _file;
  String? _loadError;
  bool _busy = false;
  bool _destroying = false;
  bool _resumeExpiryPending = false;
  Future<void>? _loading;
  int? _selectedArchive;
  NotebookFilter _filter = NotebookFilter.pending;
  final _reminders = ReminderService.instance;
  final _scrollController = ScrollController();
  ReminderSyncResult? _reminderResult;
  bool _reminderError = false;
  int _reminderGeneration = 0;
  NotebookArchive? get _archive => _selectedArchive == null || _book == null
      ? null
      : _book!.archives.firstWhere((a) => a.volume == _selectedArchive);
  AppLocalizations get _l10n => AppLocalizations.of(context);
  Locale? _lastLocale;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reminders.onTap = _consumeReminderTap;
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (_lastLocale != null && _lastLocale != locale) {
      unawaited(_refreshReminders());
    }
    _lastLocale = locale;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    if (_reminders.onTap == _consumeReminderTap) _reminders.onTap = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(Diagnostics.record('app.lifecycle', state.name));
    if (state == AppLifecycleState.resumed) unawaited(_resume());
  }

  Future<void> _load() {
    if (_destroying) return Future.value();
    return _loading ??= _loadFromDisk().whenComplete(() => _loading = null);
  }

  Future<void> _loadFromDisk() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/notebook.json');
      final book = await readNotebook(file);
      if (!mounted) return;
      setState(() {
        _file = file;
        _book = book;
        _loadError = null;
      });
      if (!await _expire()) await _refreshReminders();
    } catch (_) {
      if (mounted) setState(() => _loadError = _l10n.loadError);
    }
  }

  Future<bool> _persist(
    Notebook book, {
    bool updateReminders = true,
    int? removedArchiveVolume,
    required String operation,
  }) async {
    if (_busy) return false;
    _busy = true;
    await Diagnostics.record('notebook.operation.requested', operation);
    try {
      await writeNotebook(_file!, book);
      await Diagnostics.record('notebook.operation.saved', operation);
      if (!mounted) return false;
      setState(() {
        if (removedArchiveVolume != null) {
          if (_selectedArchive == removedArchiveVolume) {
            _selectedArchive = null;
            _filter = NotebookFilter.pending;
          } else if (_selectedArchive != null &&
              _selectedArchive! > removedArchiveVolume) {
            _selectedArchive = _selectedArchive! - 1;
          } else if (_selectedArchive == null) {
            _filter = NotebookFilter.pending;
          }
        } else if (_book?.volume != book.volume && _selectedArchive == null) {
          _filter = NotebookFilter.pending;
        }
        _book = book;
      });
      if (updateReminders && !_resumeExpiryPending) {
        unawaited(_refreshReminders());
      }
      return true;
    } catch (error, stack) {
      await Diagnostics.record(
        'notebook.operation.failed',
        '$operation ${error.runtimeType}\n$stack',
      );
      if (mounted) _notice(_l10n.saveFailed);
      return false;
    } finally {
      await _releaseBusy();
    }
  }

  void _notice(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 17)),
        backgroundColor: journalThemeOf(context).ink,
        duration: const Duration(seconds: 4),
      ),
    );
  Future<bool> _expire() async {
    if (_book == null || _busy || !_book!.expired(DateTime.now())) return false;
    final saved = await _persist(
      _book!.reconcile(DateTime.now()),
      updateReminders: false,
      operation: 'expire',
    );
    if (saved && mounted) {
      _notice(_l10n.volumeExpired);
      await _refreshReminders();
    }
    return true;
  }

  Future<void> _edit({JournalEntry? original}) async {
    if (_selectedArchive != null || _busy || await _expire() || !mounted) {
      return;
    }
    final volume = _book!.volume;
    final draft = await Navigator.push<EntryDraft>(
      context,
      MaterialPageRoute(builder: (_) => EntryEditor(original: original)),
    );
    if (!mounted || draft == null || _busy) return;
    if (await _expire() || _book!.volume != volume) {
      if (mounted) _notice(_l10n.originalExpired);
      return;
    }
    try {
      final now = DateTime.now();
      final updated = original == null
          ? _book!.add(draft.text, draft.due!, now)
          : _book!.revise(original.id, draft.text, draft.due, now);
      await _persist(updated, operation: original == null ? 'add' : 'revise');
    } on ArgumentError {
      _notice(_l10n.dateInPast);
    } on StateError {
      await _expire();
    }
  }

  Future<void> _fulfill(JournalEntry entry) async {
    if (_selectedArchive != null || _busy || await _expire() || !mounted) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_l10n.fulfillTitle),
        content: Text(_l10n.fulfillContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_l10n.confirmFulfillment),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busy || await _expire() || !mounted) {
      return;
    }
    try {
      if (await _persist(
            _book!.fulfill(entry.id, DateTime.now()),
            operation: 'fulfill',
          ) &&
          mounted) {
        HapticFeedback.lightImpact();
        _notice(_l10n.fulfilledNotice);
      }
    } on StateError {
      await _expire();
    }
  }

  Future<void> _changeSortOrder(NotebookSortOrder order) async {
    if (_busy || await _expire() || !mounted || _book!.sortOrder == order) {
      return;
    }
    await _persist(
      _book!.withSortOrder(order),
      updateReminders: false,
      operation: 'sort',
    );
  }

  Future<void> _chooseVolume() async {
    if (_busy || await _expire() || !mounted) return;
    final chosen = await showModalBottomSheet<VolumeSelection>(
      context: context,
      backgroundColor: journalThemeOf(context).paper,
      builder: (_) => VolumePicker(book: _book!),
    );
    if (!mounted || chosen == null || _busy || await _expire() || !mounted) {
      return;
    }
    switch (chosen.action) {
      case VolumeAction.create:
        await _editVolume(create: true);
      case VolumeAction.rename:
        await _editVolume(create: false);
      case VolumeAction.open:
        setState(() {
          _selectedArchive = chosen.volume == _book!.volume
              ? null
              : chosen.volume;
          _filter = _selectedArchive == null
              ? NotebookFilter.pending
              : NotebookFilter.all;
        });
      case VolumeAction.delete:
        await _deleteArchivedVolume(chosen.volume!);
    }
  }

  Future<void> _deleteArchivedVolume(int volume) async {
    if (_busy || await _expire() || !mounted) return;
    try {
      final next = _book!.deleteArchivedVolume(volume);
      if (!await _persist(
            next,
            removedArchiveVolume: volume,
            operation: 'delete_archive',
          ) ||
          !mounted) {
        return;
      }
      _notice(_l10n.archiveDeleted);
    } on StateError {
      if (mounted) _notice(_l10n.archiveDeleteOnly);
    }
  }

  Future<void> _editVolume({required bool create}) async {
    if (_busy || await _expire() || !mounted) return;
    final current = _book!;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => VolumeNameDialog(
        volume: create ? current.volume + 1 : current.volume,
        initialName: create ? '' : current.volumeName,
        sealingVolumeTitle: create
            ? _l10n.volumeTitle(current.volume, current.volumeName)
            : null,
      ),
    );
    if (!mounted || name == null) return;
    if (_busy || _book!.volume != current.volume || await _expire()) {
      if (mounted) _notice(_l10n.volumeStateChanged);
      return;
    }
    try {
      final next = create
          ? _book!.startNewVolume(name, DateTime.now())
          : _book!.withVolumeName(name);
      if (!await _persist(
            next,
            updateReminders: create,
            operation: create ? 'new_volume' : 'rename_volume',
          ) ||
          !mounted) {
        return;
      }
      if (create) {
        setState(() {
          _selectedArchive = null;
          _filter = NotebookFilter.pending;
        });
        _notice(_l10n.oldVolumeArchived);
      } else {
        _notice(_l10n.volumeNameSaved);
      }
    } on StateError {
      await _expire();
    }
  }

  String _filterName(NotebookFilter filter) => switch (filter) {
    NotebookFilter.all => _l10n.filterName(filter),
    NotebookFilter.pending => _l10n.filterName(filter),
    NotebookFilter.fulfilled => _l10n.filterName(filter),
    NotebookFilter.unfulfilled => _l10n.filterName(filter),
  };

  String? _archiveAnnotation(JournalEntry entry, NotebookArchive? archive) {
    if (archive == null || entry.status != EntryStatus.pending) return null;
    return _l10n.archiveAnnotation(archive.failedEntryIds.contains(entry.id));
  }

  Future<void> _resume() async {
    if (!mounted) return;
    if (_busy || _destroying) {
      _resumeExpiryPending = true;
      return;
    }
    if (!await _expire()) await _refreshReminders();
  }

  Future<bool> _releaseBusy() async {
    _busy = false;
    if (mounted && !_destroying && _resumeExpiryPending) {
      _resumeExpiryPending = false;
      await _resume();
      return true;
    }
    return false;
  }

  Future<void> _refreshReminders({bool reportStatus = false}) async {
    final book = _book;
    if (_destroying || book == null) {
      if (reportStatus && mounted) _notice(_l10n.notebookNotLoaded);
      return;
    }
    final generation = ++_reminderGeneration;
    try {
      final result = await _reminders.synchronize(
        book,
        locale: Localizations.localeOf(context),
      );
      if (!mounted) return;
      final isCurrent = generation == _reminderGeneration;
      if (isCurrent) {
        setState(() {
          _reminderResult = result;
          _reminderError = false;
        });
      }
      if (reportStatus) {
        final status = result.enabled
            ? _l10n.remindersChecked(result.scheduledCount)
            : _l10n.remindersDisabled;
        _notice(isCurrent ? status : _l10n.reminderCheckStale(status));
      }
      if (isCurrent) _consumeReminderTap();
    } catch (_) {
      if (!mounted) return;
      final isCurrent = generation == _reminderGeneration;
      if (isCurrent) setState(() => _reminderError = true);
      if (reportStatus) {
        _notice(
          isCurrent
              ? _l10n.reminderCheckFailure
              : _l10n.reminderCheckFailureStale,
        );
      }
    }
  }

  void _consumeReminderTap() {
    if (!mounted || _book == null) return;
    if (_destroying) return;
    if (_reminders.takePendingTarget() != null) {
      unawaited(_openNotebookFromReminder());
    }
  }

  Future<void> _openNotebookFromReminder() async {
    await _expire();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      _selectedArchive = null;
      _filter = NotebookFilter.pending;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && _scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Future<bool> _saveReminderPreferences(ReminderPreferences preferences) async {
    if (_busy || _destroying || _book == null) return false;
    _busy = true;
    ++_reminderGeneration;
    try {
      final result = await _reminders.updatePreferences(
        _book!,
        preferences,
        locale: Localizations.localeOf(context),
      );
      if (!mounted) return false;
      setState(() {
        _reminderResult = result;
        _reminderError = false;
      });
      return true;
    } catch (_) {
      if (mounted) setState(() => _reminderError = true);
      return false;
    } finally {
      await _releaseBusy();
    }
  }

  Future<void> _requestReminderPermission() async {
    try {
      await _reminders.requestPermission();
      if (!mounted) return;
      await _refreshReminders(reportStatus: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _reminderError = true);
      _notice(_l10n.permissionFailure);
    }
  }

  Future<void> _openNotificationSettings() async {
    try {
      final opened = await _reminders.openSystemSettings();
      if (!mounted) return;
      _notice(_l10n.settingsOpened(opened));
    } catch (_) {
      if (!mounted) return;
      setState(() => _reminderError = true);
      _notice(_l10n.settingsOpenFailure);
    }
  }

  Future<void> _showReminderSettings() async {
    late final ReminderPreferences preferences;
    try {
      preferences = await _reminders.loadPreferences();
    } catch (_) {
      if (!mounted) return;
      setState(() => _reminderError = true);
      _notice(_l10n.reminderPreferencesFailure);
      return;
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: journalThemeOf(context).paper,
      isScrollControlled: true,
      builder: (_) => ReminderSettings(
        result: _reminderResult,
        preferences: preferences,
        hasError: _reminderError,
        onEnable: () => unawaited(_requestReminderPermission()),
        onCheck: () => unawaited(_refreshReminders(reportStatus: true)),
        onSystemSettings: () => unawaited(_openNotificationSettings()),
        onSave: _saveReminderPreferences,
      ),
    );
  }

  void _showDataSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: journalThemeOf(context).paper,
      isScrollControlled: true,
      isDismissible: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      enableDrag: false,
      builder: (_) => DataSettings(
        onTheme: _showThemeSettings,
        fontPreferenceController: widget.fontPreferenceController,
        onDestroy: _destroyAllRecords,
        onExport: _exportBackup,
        onImport: _importBackup,
        language: widget.language,
        onLanguageChanged: widget.onLanguageChanged,
      ),
    );
  }

  void _showThemeSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: journalThemeOf(context).paper,
      isScrollControlled: true,
      builder: (_) => ThemeSettings(
        preferences: widget.themePreferences,
        onChanged: widget.onThemeChanged,
      ),
    );
  }

  Future<String> _exportBackup() async {
    if (_loading != null || _busy) return _l10n.busyReading;
    final book = _book;
    if (book == null) return _l10n.exportUnavailable;
    final snapshot = jsonEncode(book.toJson());
    final encrypted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: journalThemeOf(context).paper,
        title: Text(_l10n.backupChoiceTitle),
        content: Text(_l10n.backupChoiceContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_l10n.plainBackup),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_l10n.encryptedBackup),
          ),
        ],
      ),
    );
    if (encrypted == null || !mounted) return _l10n.exportCancelled;
    String contents = snapshot;
    if (encrypted) {
      final password = await showBackupPassword(context);
      if (password == null || !mounted) return _l10n.exportCancelled;
      contents = await encryptBackup(snapshot, password);
      if (!mounted) return _l10n.exportCancelled;
    }
    final exported = await backupChannel.invokeMethod<bool>('export', {
      'contents': contents,
    });
    await Diagnostics.record('notebook.backup.export', 'exported=$exported');
    return exported == true ? _l10n.backupExported : _l10n.exportCancelled;
  }

  Future<String> _importBackup() async {
    if (_busy || _destroying || _loading != null) {
      return _l10n.busyReading;
    }
    _busy = true;
    _destroying = true;
    ++_reminderGeneration;
    var gateAcquired = false;
    var saved = false;
    var reminderFailure = false;
    var resumeScheduled = false;
    try {
      final text = await backupChannel.invokeMethod<String>('import');
      if (text == null) return _l10n.importCancelled;
      String contents = text;
      if (isEncryptedBackup(text)) {
        if (!mounted) return _l10n.importCancelled;
        final decrypted = await showBackupPassword(context, encrypted: text);
        if (decrypted == null) return _l10n.importCancelled;
        contents = decrypted;
      }
      final backup = decodeNotebookBackup(contents);
      if (!mounted) return _l10n.importCancelled;
      final count =
          backup.entries.length +
          backup.archives.fold<int>(
            0,
            (sum, archive) => sum + archive.entries.length,
          );
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: journalThemeOf(context).paper,
          title: Text(_l10n.replaceBackupTitle(backup.archives.length)),
          content: Text(
            _l10n.replaceBackupContent(backup.archives.length, count),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_l10n.importBackup),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return _l10n.importCancelled;
      await _reminders.beginDestruction();
      gateAcquired = true;
      final dir = await getApplicationDocumentsDirectory();
      final file = _file ?? File('${dir.path}/notebook.json');
      final restored = backup.reconcile(DateTime.now());
      await writeNotebook(file, restored);
      saved = true;
      if (mounted) {
        setState(() {
          _file = file;
          _book = restored;
          _loadError = null;
          _selectedArchive = null;
          _filter = NotebookFilter.pending;
        });
      }
      await Diagnostics.record('notebook.backup.import.saved');
      await _reminders.cancelAllForDestruction();
    } catch (error, stack) {
      await Diagnostics.record(
        'notebook.backup.import.failed',
        '${error.runtimeType}\n$stack',
      );
      if (!saved) rethrow;
      reminderFailure = true;
    } finally {
      if (gateAcquired) {
        try {
          await _reminders.endDestruction();
        } catch (_) {
          reminderFailure = true;
        }
      }
      _destroying = false;
      resumeScheduled = await _releaseBusy();
    }
    if (!resumeScheduled) await _refreshReminders();
    if (reminderFailure || _reminderError) {
      return _l10n.importReminderFailure;
    }
    return _l10n.importComplete;
  }

  Future<String> _destroyAllRecords() async {
    if (_busy || _destroying) return _l10n.saving;
    if (_loading != null || (_book == null && _loadError == null)) {
      return _l10n.reading;
    }
    _destroying = true;
    _busy = true;
    ++_reminderGeneration;
    var gateAcquired = false;
    await Diagnostics.record('notebook.destroy.requested');
    try {
      await _reminders.beginDestruction();
      gateAcquired = true;
      final dir = await getApplicationDocumentsDirectory();
      final file = _file ?? File('${dir.path}/notebook.json');
      final empty = Notebook.empty();
      await writeNotebook(file, empty);
      if (mounted) {
        setState(() {
          _file = file;
          _book = empty;
          _loadError = null;
          _selectedArchive = null;
          _filter = NotebookFilter.pending;
        });
      }
      await Diagnostics.record('notebook.destroy.saved');
      try {
        await _reminders.cancelAllForDestruction();
        if (mounted) {
          setState(() {
            _reminderResult = ReminderSyncResult(
              enabled: _reminderResult?.enabled ?? false,
              scheduledCount: 0,
              preferences:
                  _reminderResult?.preferences ?? const ReminderPreferences(),
            );
            _reminderError = false;
          });
        }
      } catch (error, stack) {
        await Diagnostics.record(
          'notebook.destroy.reminders.failed',
          '${error.runtimeType}\n$stack',
        );
        if (mounted) setState(() => _reminderError = true);
        return _l10n.destroyReminderFailure;
      }
      await Diagnostics.record('notebook.destroy.completed');
      return _l10n.destroyComplete;
    } catch (error, stack) {
      await Diagnostics.record(
        'notebook.destroy.failed',
        '${error.runtimeType}\n$stack',
      );
      return _l10n.destroyFailure;
    } finally {
      if (gateAcquired) {
        try {
          await _reminders.endDestruction();
        } catch (error, stack) {
          await Diagnostics.record(
            'notebook.destroy.release.failed',
            '${error.runtimeType}\n$stack',
          );
          if (mounted) {
            setState(() => _reminderError = true);
            _notice(_l10n.reminderRecoveryFailure);
          }
        }
      }
      _destroying = false;
      final resumeScheduled = await _releaseBusy();
      if (gateAcquired && mounted && !resumeScheduled) {
        unawaited(_refreshReminders());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final archive = _archive;
    final entries =
        _book?.viewEntries(filter: _filter, archivedVolume: _selectedArchive) ??
        const <JournalEntry>[];
    final volumeEntries =
        archive?.entries ?? _book?.entries ?? const <JournalEntry>[];
    final entryIndices = {
      for (var i = 0; i < entries.length; i++) entries[i].id: i,
    };
    return Scaffold(
      body: SizedBox.expand(
        child: PaperSurface(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 22, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _l10n.sealedNotebook,
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 2,
                            color: journalThemeOf(context).fadedInk,
                          ),
                        ),
                      ),
                      if (_book != null)
                        Expanded(
                          child: TextButton(
                            onPressed: _chooseVolume,
                            child: Text(
                              _l10n.volumeTitle(
                                archive?.volume ?? _book!.volume,
                                archive?.volumeName ?? _book!.volumeName,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                color: journalThemeOf(context).fadedInk,
                              ),
                            ),
                          ),
                        ),
                      TextButton(
                        onPressed: _showDataSettings,
                        child: Text(
                          _l10n.settings,
                          style: TextStyle(
                            fontSize: 15,
                            color: journalThemeOf(context).fadedInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loadError != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  _loadError!,
                                  style: journalText.copyWith(
                                    color: journalThemeOf(context).ink,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _load,
                                child: Text(_l10n.reload),
                              ),
                            ],
                          ),
                        )
                      : _book == null
                      ? Center(
                          child: CircularProgressIndicator(
                            color: journalThemeOf(context).fadedInk,
                          ),
                        )
                      : CustomScrollView(
                          controller: _scrollController,
                          slivers: [
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: 24),
                                    Text(
                                      _l10n.appTitle,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 34,
                                        letterSpacing: 8,
                                        color: journalThemeOf(context).ink,
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    Text(
                                      'THE FAMILY JOURNAL',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        letterSpacing: 2.4,
                                        color: journalThemeOf(context).fadedInk,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        PopupMenuButton<NotebookFilter>(
                                          tooltip: _l10n.filterRecords,
                                          initialValue: _filter,
                                          onSelected: (value) =>
                                              setState(() => _filter = value),
                                          itemBuilder: (_) => NotebookFilter
                                              .values
                                              .map(
                                                (filter) => PopupMenuItem(
                                                  value: filter,
                                                  child: Text(
                                                    _filterName(filter),
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                              horizontal: 2,
                                            ),
                                            child: Text(
                                              _filterName(_filter),
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: journalThemeOf(context)
                                                    .fadedInk,
                                              ),
                                            ),
                                          ),
                                        ),
                                        PopupMenuButton<NotebookSortOrder>(
                                          tooltip: _l10n.sortOrder,
                                          initialValue: _book!.sortOrder,
                                          onSelected: _changeSortOrder,
                                          itemBuilder: (_) => [
                                            PopupMenuItem(
                                              value: NotebookSortOrder.writing,
                                              child: Text(_l10n.writingOrder),
                                            ),
                                            PopupMenuItem(
                                              value: NotebookSortOrder.deadline,
                                              child: Text(_l10n.dueDateOrder),
                                            ),
                                          ],
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                              horizontal: 2,
                                            ),
                                            child: Text(
                                              _book!.sortOrder ==
                                                      NotebookSortOrder.writing
                                                  ? _l10n.writingOrder
                                                  : _l10n.dueDateOrder,
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: journalThemeOf(context)
                                                    .fadedInk,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (archive != null) ...[
                                      const SizedBox(height: 16),
                                      Text(
                                        _l10n.readOnlyArchived,
                                        style: TextStyle(
                                          fontSize: 18,
                                          color: journalThemeOf(context)
                                              .fadedInk,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        archive.reason ==
                                                ArchiveReason.manualClosure
                                            ? _l10n.archiveSummaryActive(
                                                archive.archivedAt.toLocal(),
                                              )
                                            : _l10n.archiveSummaryExpired(
                                                archive.invalidatedAt!
                                                    .toLocal(),
                                                archive.archivedAt.toLocal(),
                                              ),
                                        style: TextStyle(
                                          fontSize: 14,
                                          height: 1.8,
                                          color: journalThemeOf(context)
                                              .fadedInk,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 24),
                                    if (entries.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 64,
                                        ),
                                        child: Text(
                                          volumeEntries.isEmpty
                                              ? _l10n.emptyPage
                                              : _filter ==
                                                    NotebookFilter.pending
                                              ? _l10n.noPending
                                              : _l10n.noMatchingRecords,
                                          textAlign: TextAlign.center,
                                          style: journalText.copyWith(
                                            color: journalThemeOf(context)
                                                .fadedInk,
                                            height: 2.2,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                              ),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final entry = entries[index];
                                    return JournalParagraph(
                                      key: ValueKey(entry.id),
                                      entry: entry,
                                      readOnly: archive != null,
                                      annotation: _archiveAnnotation(
                                        entry,
                                        archive,
                                      ),
                                      onFulfill: () => _fulfill(entry),
                                      onRevise: () => _edit(original: entry),
                                    );
                                  },
                                  childCount: entries.length,
                                  findChildIndexCallback: (key) =>
                                      key is ValueKey<String>
                                      ? entryIndices[key.value]
                                      : null,
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(28, 0, 28, 34),
                              sliver: SliverToBoxAdapter(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: 22),
                                    if (archive == null)
                                      Center(
                                        child: Semantics(
                                          label: _l10n.newAssertion,
                                          button: true,
                                          child: IconButton(
                                            tooltip: _l10n.newAssertionTooltip,
                                            onPressed: () => _edit(),
                                            padding: const EdgeInsets.all(14),
                                            icon: const Feather(),
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 20),
                                    Text(
                                      archive == null
                                          ? _l10n.fulfillOrRevise
                                          : _l10n.archivedReadOnlyHint,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.8,
                                        color: journalThemeOf(context).fadedInk,
                                      ),
                                    ),
                                    if (archive == null &&
                                        entries.any(
                                          (e) =>
                                              e.status == EntryStatus.pending,
                                        )) ...[
                                      const SizedBox(height: 18),
                                      Text(
                                        _l10n.swipeHint,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: journalThemeOf(context)
                                              .fadedInk,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 14),
                                    TextButton(
                                      onPressed: _showReminderSettings,
                                      child: Text(
                                        _reminderError
                                            ? _l10n.checkReminders
                                            : _reminderResult?.enabled == true
                                            ? _reminderResult!
                                                          .preferences
                                                          .mode ==
                                                      ReminderMode.daily
                                                  ? _l10n.dailyReminderAt(
                                                      '${_reminderResult!.preferences.hour.toString().padLeft(2, '0')}:${_reminderResult!.preferences.minute.toString().padLeft(2, '0')}',
                                                    )
                                                  : _l10n.automaticReminderAt(
                                                      '09:00',
                                                    )
                                            : _l10n.enableReminders,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: journalThemeOf(context)
                                              .fadedInk,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
