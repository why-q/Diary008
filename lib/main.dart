import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:diary008/volume_name_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

import 'app_licenses.dart';
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
import 'font_preferences.dart';
import 'diagnostics.dart';

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
  final _fontPreference = FontPreferenceController();

  @override
  void initState() {
    super.initState();
    unawaited(_fontPreference.load());
  }

  @override
  void dispose() {
    _fontPreference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _fontPreference,
    builder: (context, _) => MaterialApp(
      title: '家族笔记',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: paper,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: child!,
      ),
      theme: applyFontPreference(
        ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: paper,
          colorScheme: ColorScheme.fromSeed(seedColor: ink, surface: paper),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: ink,
              textStyle: const TextStyle(fontSize: 19),
            ),
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: InputBorder.none,
          ),
        ),
        _fontPreference.preference,
      ),
      home: NotebookPage(fontPreferenceController: _fontPreference),
    ),
  );
}

class NotebookPage extends StatefulWidget {
  const NotebookPage({super.key, required this.fontPreferenceController});
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reminders.onTap = _consumeReminderTap;
    _load();
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
      if (mounted) setState(() => _loadError = '笔记暂时无法读取，原有内容未被覆盖。');
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
      if (mounted) _notice('落笔未能保存，请重试。');
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
        backgroundColor: ink,
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
      _notice('本卷已封存，新的空白页已开启。点击卷号可翻阅旧卷。');
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
      if (mounted) _notice('原卷已经失效，请在新页重新书写。');
      return;
    }
    try {
      final now = DateTime.now();
      final updated = original == null
          ? _book!.add(draft.text, draft.due!, now)
          : _book!.revise(original.id, draft.text, draft.due, now);
      await _persist(updated, operation: original == null ? 'add' : 'revise');
    } on ArgumentError {
      _notice('日期已经过去，请重新选择。');
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
        title: const Text('是否确认已履行？'),
        content: const Text('确认后将标记为已履行，不能撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认履行'),
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
        _notice('这一段预言，已成为事实。');
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
      backgroundColor: paper,
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
      _notice('这一卷已删除，其后卷号已前移。');
    } on StateError {
      if (mounted) _notice('只能删除已封存的卷。');
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
            ? journalVolumeTitle(current.volume, current.volumeName)
            : null,
      ),
    );
    if (!mounted || name == null) return;
    if (_busy || _book!.volume != current.volume || await _expire()) {
      if (mounted) _notice('卷册状态已更新，请重新操作。');
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
        _notice('旧卷已封存，新的空白页已开启。');
      } else {
        _notice('卷名已保存。');
      }
    } on StateError {
      await _expire();
    }
  }

  String _filterName(NotebookFilter filter) => switch (filter) {
    NotebookFilter.all => '全部',
    NotebookFilter.pending => '履行中',
    NotebookFilter.fulfilled => '已履行',
    NotebookFilter.unfulfilled => '未履行',
  };

  String? _archiveAnnotation(JournalEntry entry, NotebookArchive? archive) {
    if (archive == null || entry.status != EntryStatus.pending) return null;
    return archive.failedEntryIds.contains(entry.id) ? '未如期履行' : '随卷封存';
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
      if (reportStatus && mounted) _notice('笔记尚未加载，无法检查提醒。');
      return;
    }
    final generation = ++_reminderGeneration;
    try {
      final result = await _reminders.synchronize(book);
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
            ? '提醒状态已检查：通知已开启，已安排 ${result.scheduledCount} 次未来提醒。'
            : '提醒状态已检查：系统通知尚未开启，或提醒通道已关闭。';
        _notice(isCurrent ? status : '$status 后续检查可能已更新状态。');
      }
      if (isCurrent) _consumeReminderTap();
    } catch (_) {
      if (!mounted) return;
      final isCurrent = generation == _reminderGeneration;
      if (isCurrent) setState(() => _reminderError = true);
      if (reportStatus) {
        _notice(
          isCurrent
              ? '提醒检查失败，请重试；如果持续失败，请打开系统通知设置。笔记内容已保存。'
              : '本次提醒检查失败；后续状态可能已更新。请重新检查或打开系统通知设置；笔记内容已保存。',
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
      final result = await _reminders.updatePreferences(_book!, preferences);
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
      _notice('启用通知提醒失败，请检查系统通知设置后重试。笔记内容已保存。');
    }
  }

  Future<void> _openNotificationSettings() async {
    try {
      final opened = await _reminders.openSystemSettings();
      if (!mounted) return;
      _notice(
        opened ? '已打开系统通知设置，返回后可重新检查提醒。' : '无法打开系统通知设置；请在系统设置中为 家族笔记 开启通知。',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _reminderError = true);
      _notice('系统通知设置打开失败；请在系统设置中为 家族笔记 开启通知。');
    }
  }

  Future<void> _showReminderSettings() async {
    late final ReminderPreferences preferences;
    try {
      preferences = await _reminders.loadPreferences();
    } catch (_) {
      if (!mounted) return;
      setState(() => _reminderError = true);
      _notice('提醒设置暂时无法读取，请稍后重试。');
      return;
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: paper,
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
      backgroundColor: paper,
      isScrollControlled: true,
      isDismissible: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      enableDrag: false,
      builder: (_) => DataSettings(
        fontPreferenceController: widget.fontPreferenceController,
        onDestroy: _destroyAllRecords,
        onExport: _exportBackup,
        onImport: _importBackup,
      ),
    );
  }

  Future<String> _exportBackup() async {
    if (_loading != null || _busy) return '正在读写笔记，请稍后重试。';
    final book = _book;
    if (book == null) return '笔记尚未读取成功，无法导出备份。';
    final snapshot = jsonEncode(book.toJson());
    final encrypted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: paper,
        title: const Text('选择备份方式'),
        content: const Text('明文备份可直接读取；密码加密备份需要密码才能恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('明文备份'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('密码加密备份'),
          ),
        ],
      ),
    );
    if (encrypted == null || !mounted) return '已取消导出备份。';
    String contents = snapshot;
    if (encrypted) {
      final password = await showBackupPassword(context);
      if (password == null || !mounted) return '已取消导出备份。';
      contents = await encryptBackup(snapshot, password);
      if (!mounted) return '已取消导出备份。';
    }
    final exported = await backupChannel.invokeMethod<bool>('export', {
      'contents': contents,
    });
    await Diagnostics.record('notebook.backup.export', 'exported=$exported');
    return exported == true ? '备份已导出。' : '已取消导出备份。';
  }

  Future<String> _importBackup() async {
    if (_busy || _destroying || _loading != null) {
      return '正在读写笔记，请稍后重试。';
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
      if (text == null) return '已取消导入备份。';
      String contents = text;
      if (isEncryptedBackup(text)) {
        if (!mounted) return '已取消导入备份。';
        final decrypted = await showBackupPassword(context, encrypted: text);
        if (decrypted == null) return '已取消导入备份。';
        contents = decrypted;
      }
      final backup = decodeNotebookBackup(contents);
      if (!mounted) return '已取消导入备份。';
      final count =
          backup.entries.length +
          backup.archives.fold<int>(
            0,
            (sum, archive) => sum + archive.entries.length,
          );
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: paper,
          title: const Text('用备份替换所有记录？'),
          content: Text(
            '备份包含 ${backup.archives.length + 1} 卷、$count 条记录。'
            '当前所有卷和记录将被完整替换，无法撤销。建议先取消并导出当前数据。'
            '恢复后按现有规则检查期限，已逾期的当前卷会自动封存；通知将重新计算。诊断日志保留。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认替换并导入'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return '已取消导入备份。';
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
      return '备份已导入；提醒更新未完成，请检查提醒设置并重新打开应用。';
    }
    return '备份已导入，已替换所有记录。';
  }

  Future<String> _destroyAllRecords() async {
    if (_busy || _destroying) return '正在保存，请稍后重试。';
    if (_loading != null || (_book == null && _loadError == null)) {
      return '正在读取笔记，请稍后重试。';
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
        return '所有记录已销毁，日志保留；提醒清理失败，请在提醒设置中检查。';
      }
      await Diagnostics.record('notebook.destroy.completed');
      return '所有记录已销毁，已回到空白卷。诊断日志保留。';
    } catch (error, stack) {
      await Diagnostics.record(
        'notebook.destroy.failed',
        '${error.runtimeType}\n$stack',
      );
      return '记录未能销毁，请重试。';
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
            _notice('提醒后台恢复失败，请关闭并重新打开应用。');
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
                      const Expanded(
                        child: Text(
                          'THE SEALED NOTEBOOK',
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 2,
                            color: fadedInk,
                          ),
                        ),
                      ),
                      if (_book != null)
                        Expanded(
                          child: TextButton(
                            onPressed: _chooseVolume,
                            child: Text(
                              journalVolumeTitle(
                                archive?.volume ?? _book!.volume,
                                archive?.volumeName ?? _book!.volumeName,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                color: fadedInk,
                              ),
                            ),
                          ),
                        ),
                      TextButton(
                        onPressed: _showDataSettings,
                        child: const Text(
                          '设置',
                          style: TextStyle(fontSize: 15, color: fadedInk),
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
                                child: Text(_loadError!, style: journalText),
                              ),
                              TextButton(
                                onPressed: _load,
                                child: const Text('重新读取'),
                              ),
                            ],
                          ),
                        )
                      : _book == null
                      ? const Center(
                          child: CircularProgressIndicator(color: fadedInk),
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
                                    const Text(
                                      '家族笔记',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 34,
                                        letterSpacing: 8,
                                        color: ink,
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    const Text(
                                      'THE FAMILY JOURNAL',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        letterSpacing: 2.4,
                                        color: fadedInk,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        PopupMenuButton<NotebookFilter>(
                                          tooltip: '筛选记录',
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
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: fadedInk,
                                              ),
                                            ),
                                          ),
                                        ),
                                        PopupMenuButton<NotebookSortOrder>(
                                          tooltip: '排列方式',
                                          initialValue: _book!.sortOrder,
                                          onSelected: _changeSortOrder,
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(
                                              value: NotebookSortOrder.writing,
                                              child: Text('书写顺序'),
                                            ),
                                            PopupMenuItem(
                                              value: NotebookSortOrder.deadline,
                                              child: Text('有效日期'),
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
                                                  ? '书写顺序'
                                                  : '有效日期',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: fadedInk,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (archive != null) ...[
                                      const SizedBox(height: 16),
                                      const Text(
                                        '本卷已封存 · 只读',
                                        style: TextStyle(
                                          fontSize: 18,
                                          color: fadedInk,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        archive.reason ==
                                                ArchiveReason.manualClosure
                                            ? '封存：${journalDate(archive.archivedAt.toLocal())}\n缘由：主动封存。状态以封存时为准。'
                                            : '失效：${journalDate(archive.invalidatedAt!.toLocal())}\n'
                                                  '封存：${journalDate(archive.archivedAt.toLocal())}\n'
                                                  '缘由：预言逾期未履行。状态以失效时为准。',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          height: 1.8,
                                          color: fadedInk,
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
                                              ? '此页尚白，\n故事将由你落笔。'
                                              : _filter ==
                                                    NotebookFilter.pending
                                              ? '此刻暂无待履行的预言。\n切换“全部”可翻阅已有记录。'
                                              : '此处暂无相应的记录。',
                                          textAlign: TextAlign.center,
                                          style: journalText.copyWith(
                                            color: fadedInk,
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
                                          label: '写下新的断言',
                                          button: true,
                                          child: IconButton(
                                            tooltip: '写下新的断言',
                                            onPressed: () => _edit(),
                                            padding: const EdgeInsets.all(14),
                                            icon: const Feather(),
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 20),
                                    Text(
                                      archive == null
                                          ? '请于期限前确认履行，或留下修订；\n逾期，本卷封存，另启新页。'
                                          : '旧卷留存，往事不可改写。',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        height: 1.8,
                                        color: fadedInk,
                                      ),
                                    ),
                                    if (archive == null &&
                                        entries.any(
                                          (e) =>
                                              e.status == EntryStatus.pending,
                                        )) ...[
                                      const SizedBox(height: 18),
                                      const Text(
                                        '左滑履行 · 右滑修订',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: fadedInk,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 14),
                                    TextButton(
                                      onPressed: _showReminderSettings,
                                      child: Text(
                                        _reminderError
                                            ? '提醒暂不可用 · 点击检查'
                                            : _reminderResult?.enabled == true
                                            ? _reminderResult!
                                                          .preferences
                                                          .mode ==
                                                      ReminderMode.daily
                                                  ? '每日提醒 · ${_reminderResult!.preferences.hour.toString().padLeft(2, '0')}:${_reminderResult!.preferences.minute.toString().padLeft(2, '0')}'
                                                  : '自动提醒 · 当地时间09:00'
                                            : '开启提醒',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: fadedInk,
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
