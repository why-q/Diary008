import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'diagnostics.dart';
import 'notebook.dart';
import 'notebook_storage.dart';
import 'reminder_plan.dart';
import 'reminder_preferences.dart';
import 'reminder_preferences_storage.dart';

String _diagnosticFailure(Object error, StackTrace stack) {
  final summary = error is PlatformException && error.code == 'invalid_icon'
      ? 'PlatformException(code=${error.code}, message=${error.message})'
      : error.runtimeType.toString();
  return '$summary\n$stack';
}

class ReminderSyncResult {
  const ReminderSyncResult({
    required this.enabled,
    required this.scheduledCount,
    this.preferences = const ReminderPreferences(),
  });
  final bool enabled;
  final int scheduledCount;
  final ReminderPreferences preferences;
}

class ReminderService {
  ReminderService._();
  static final instance = ReminderService._();
  static const channelId = 'assertion_reminders_v1';
  static const runtimeChannel = MethodChannel('app.diary008/reminder_runtime');
  bool _timeZonesInitialized = false;

  Future<tz.Location> deviceTimeZone() async {
    if (!_timeZonesInitialized) {
      tzdata.initializeTimeZones();
      _timeZonesInitialized = true;
    }
    final name = await runtimeChannel.invokeMethod<String>('timeZone');
    if (name == null) throw StateError('设备未返回时区');
    return tz.getLocation(name);
  }

  Future<File> _preferencesFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/reminder_preferences.json');
  }

  Future<ReminderPreferences> loadPreferences() async =>
      readReminderPreferences(await _preferencesFile());

  Future<ReminderSyncResult> updatePreferences(
    Notebook book,
    ReminderPreferences preferences,
  ) async {
    // The existing native barrier also quiesces a background rescheduler;
    // otherwise it could reinstall the old mode after this switch completes.
    await beginDestruction();
    try {
      await _queue;
      await writeReminderPreferences(await _preferencesFile(), preferences);
      await cancelAllForDestruction();
    } finally {
      await endDestruction();
    }
    return synchronize(book);
  }

  Future<void> refreshFromDisk() async {
    final generation = _destructionGeneration;
    if (_suspendedForDestruction) {
      await Diagnostics.record(
        'reminder.background_refresh.skipped',
        'reason=suspended',
      );
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final book = await readNotebook(
        File('${dir.path}/notebook.json'),
        migrate: false,
      );
      if (_suspendedForDestruction || generation != _destructionGeneration) {
        await Diagnostics.record(
          'reminder.background_refresh.skipped',
          _suspendedForDestruction ? 'reason=suspended' : 'reason=stale',
        );
        return;
      }
      await synchronize(book);
      await Diagnostics.record('reminder.background_refresh.success');
    } catch (error, stack) {
      await Diagnostics.record(
        'reminder.background_refresh.failure',
        _diagnosticFailure(error, stack),
      );
      Error.throwWithStackTrace(error, stack);
    }
  }

  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initializing;
  Future<void> _queue = Future.value();
  int _destructionGeneration = 0;
  bool _suspendedForDestruction = false;
  ReminderTarget? _pendingTarget;
  void Function()? onTap;
  AndroidFlutterLocalNotificationsPlugin get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()!;
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      '笔记提醒',
      channelDescription: '按计划或每天固定时间提醒翻阅笔记',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      visibility: NotificationVisibility.private,
      category: AndroidNotificationCategory.reminder,
      onlyAlertOnce: true,
    ),
  );

  Future<void> initialize() => _initializing ??= _initialize().catchError((
    Object error,
    StackTrace stack,
  ) {
    _initializing = null;
    Error.throwWithStackTrace(error, stack);
  });
  Future<void> _initialize() async {
    runtimeChannel.setMethodCallHandler((call) async {
      if (call.method != 'refresh') throw MissingPluginException();
      await refreshFromDisk();
    });
    final initialized = await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_journal_notification'),
      ),
      onDidReceiveNotificationResponse: (response) =>
          _receive(response.payload),
    );
    if (initialized != true) throw StateError('通知初始化未完成');
    await _android.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        '断言提醒',
        description: '按期限和间隔提醒当前卷中尚待履行的断言',
        importance: Importance.defaultImportance,
      ),
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      _receive(launch?.notificationResponse?.payload);
    }
  }

  void _receive(String? payload) {
    final target = ReminderTarget.fromPayload(payload);
    unawaited(
      Diagnostics.record(
        'reminder.tap',
        target == null ? '' : 'mode=${target.mode.name}',
      ),
    );
    if (target == null) return;
    _pendingTarget = target;
    onTap?.call();
  }

  ReminderTarget? takePendingTarget() {
    final target = _pendingTarget;
    _pendingTarget = null;
    return target;
  }

  Future<bool> requestPermission() async {
    try {
      await initialize();
      final supportsRuntimePermission =
          await runtimeChannel.invokeMethod<bool>(
            'supportsRuntimeNotificationPermission',
          ) ??
          false;
      if (!supportsRuntimePermission) {
        final enabled = await _notificationsEnabled();
        if (!enabled) await openSystemSettings();
        await Diagnostics.record(
          'reminder.permission.success',
          'granted=$enabled;runtime_prompt=false',
        );
        return enabled;
      }

      final granted = await _android.requestNotificationsPermission() ?? false;
      if (granted && !(await _notificationsEnabled())) {
        await openSystemSettings();
      }
      await Diagnostics.record(
        'reminder.permission.success',
        'granted=$granted',
      );
      return granted;
    } catch (error, stack) {
      await Diagnostics.record(
        'reminder.permission.failure',
        _diagnosticFailure(error, stack),
      );
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<bool> openSystemSettings() async {
    try {
      final appNotificationsEnabled =
          await _android.areNotificationsEnabled() ?? false;
      final settingsChannelId =
          appNotificationsEnabled && !(await _reminderChannelEnabled())
          ? channelId
          : null;
      final opened =
          await runtimeChannel.invokeMethod<bool>(
            'openNotificationSettings',
            settingsChannelId,
          ) ??
          false;
      await Diagnostics.record(
        'reminder.permission_settings.success',
        'opened=$opened',
      );
      return opened;
    } catch (error, stack) {
      await Diagnostics.record(
        'reminder.permission_settings.failure',
        _diagnosticFailure(error, stack),
      );
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<bool> _notificationsEnabled() async {
    final appEnabled = await _android.areNotificationsEnabled() ?? false;
    return appEnabled && await _reminderChannelEnabled();
  }

  Future<bool> _reminderChannelEnabled() async {
    final channels = await _android.getNotificationChannels();
    return channels?.any(
          (channel) =>
              channel.id == channelId && channel.importance != Importance.none,
        ) ??
        false;
  }

  Future<void> beginDestruction() async {
    final wasSuspended = _suspendedForDestruction;
    _suspendedForDestruction = true;
    _destructionGeneration++;
    try {
      await runtimeChannel.invokeMethod<void>('beginDestruction');
    } catch (_) {
      _suspendedForDestruction = wasSuspended;
      rethrow;
    }
  }

  Future<void> endDestruction() async {
    _suspendedForDestruction = false;
    await runtimeChannel.invokeMethod<void>('endDestruction');
  }

  Future<ReminderSyncResult> synchronize(Notebook book) {
    if (_suspendedForDestruction) {
      unawaited(
        Diagnostics.record('reminder.sync.failure', 'reason=destruction'),
      );
      return Future<ReminderSyncResult>.error(
        StateError('Cannot synchronize reminders during destruction'),
      );
    }
    final result = _queue.then((_) async {
      try {
        final applied = await _apply(book);
        await Diagnostics.record(
          'reminder.sync.success',
          'enabled=${applied.enabled};scheduled=${applied.scheduledCount}',
        );
        return applied;
      } catch (error, stack) {
        await Diagnostics.record(
          'reminder.sync.failure',
          _diagnosticFailure(error, stack),
        );
        Error.throwWithStackTrace(error, stack);
      }
    });
    // Keep subsequent mutations usable after an error; the caller still receives it.
    _queue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<void> cancelAllForDestruction() {
    final result = _queue.then((_) async {
      _pendingTarget = null;
      try {
        await initialize();
        try {
          await _plugin.cancelAll();
        } finally {
          await runtimeChannel.invokeMethod<void>('cancelDailyReminder');
        }
      } finally {
        _pendingTarget = null;
      }
    });
    _queue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<ReminderSyncResult> _apply(Notebook book) async {
    await initialize();
    final preferences = await loadPreferences();
    final enabled = await _notificationsEnabled();
    if (!enabled) {
      await _plugin.cancelAll();
      await runtimeChannel.invokeMethod<void>('cancelDailyReminder');
      return ReminderSyncResult(
        enabled: false,
        scheduledCount: 0,
        preferences: preferences,
      );
    }
    final location = await deviceTimeZone();
    final now = tz.TZDateTime.now(location);
    final plans = planReminders(
      book,
      now: now,
      location: location,
      preferences: preferences,
    );
    if (preferences.mode == ReminderMode.daily) {
      // Plugin calendar repeats derive their clock from the previous occurrence,
      // which can drift after a DST gap. Each native alarm instead wakes the
      // existing rescheduler; the next occurrence is recomputed from preferences.
      for (final request in await _plugin.pendingNotificationRequests()) {
        await _plugin.cancel(id: request.id);
      }
      final todayId = now.year * 10000 + now.month * 100 + now.day;
      for (final active in await _plugin.getActiveNotifications()) {
        if (active.id != null && active.id != todayId) {
          await _plugin.cancel(id: active.id!, tag: active.tag);
        }
      }
      final nativeState = await runtimeChannel.invokeMapMethod<String, dynamic>(
        'dailyReminderState',
      );
      if (nativeState == null) throw StateError('每日提醒状态不可用');
      final dueAt = nativeState['dueAt'] as int?;
      if (dueAt != null) {
        final due = tz.TZDateTime.fromMillisecondsSinceEpoch(location, dueAt);
        if (due.year == now.year &&
            due.month == now.month &&
            due.day == now.day) {
          await _plugin.show(
            id: todayId,
            title: '家族笔记',
            body: '到了约定的时间，翻阅笔记，写下今天的记录。',
            notificationDetails: _details,
            payload: const ReminderTarget(mode: ReminderMode.daily).payload,
          );
        }
        await runtimeChannel.invokeMethod<bool>('completeDailyReminder', dueAt);
      }
      final nextAt = plans.single.at.millisecondsSinceEpoch;
      if (nativeState['scheduled'] != true || nativeState['at'] != nextAt) {
        await runtimeChannel.invokeMethod<void>('scheduleDailyReminder', {
          'at': nextAt,
        });
      }
      return ReminderSyncResult(
        enabled: true,
        scheduledCount: 1,
        preferences: preferences,
      );
    }
    await runtimeChannel.invokeMethod<void>('cancelDailyReminder');
    final desired = {
      for (final plan in plans)
        plan.id: (
          plan: plan,
          payload: jsonEncode({
            'kind': 'notebook',
            'mode': plan.target.mode.name,
            'at': plan.at.toIso8601String(),
            'timeZone': location.name,
          }),
        ),
    };
    final pending = await _plugin.pendingNotificationRequests();
    final existing = {
      for (final request in pending) request.id: request.payload,
    };
    for (final request in pending) {
      if (desired[request.id]?.payload != request.payload ||
          !desired.containsKey(request.id)) {
        await _plugin.cancel(id: request.id);
      }
    }
    for (final active in await _plugin.getActiveNotifications()) {
      // Android does not expose payloads for active notifications. Identify
      // retained requests by ID, and invalidate the snapshot after cancellation.
      if (active.id != null && !desired.containsKey(active.id)) {
        await _plugin.cancel(id: active.id!, tag: active.tag);
        existing.remove(active.id);
      }
    }
    for (final item in desired.values) {
      if (existing[item.plan.id] == item.payload) continue;
      await _plugin.zonedSchedule(
        id: item.plan.id,
        scheduledDate: item.plan.at,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: '家族笔记',
        body: '笔记中有待履行的约定，今天记得翻阅。',
        payload: item.payload,
      );
    }
    return ReminderSyncResult(
      enabled: true,
      scheduledCount: plans.length,
      preferences: preferences,
    );
  }
}
