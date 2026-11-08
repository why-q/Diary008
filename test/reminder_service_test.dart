import 'package:diary008/reminder_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

const _notificationsChannel = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);
const _diagnosticsChannel = MethodChannel('app.diary008/diagnostics');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pluginCalls = <String>[];
  final settingsArguments = <Object?>[];
  final diagnosticRecords = <Map<String, Object?>>[];
  var supportsRuntimePermissionRequest = false;
  var notificationsEnabled = false;
  var reminderChannelEnabled = true;
  var permissionGranted = true;
  var failInitialization = false;

  setUpAll(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_notificationsChannel, (call) async {
      pluginCalls.add(call.method);
      switch (call.method) {
        case 'initialize':
          if (failInitialization) {
            throw PlatformException(
              code: 'invalid_icon',
              message: 'Resource missing',
            );
          }
          return true;
        case 'getNotificationChannels':
          return [
            {
              'id': ReminderService.channelId,
              'name': '断言提醒',
              'description': '',
              'groupId': null,
              'showBadge': true,
              'importance': reminderChannelEnabled ? 3 : 0,
              'bypassDnd': false,
              'playSound': false,
              'soundSource': null,
              'sound': null,
              'enableLights': false,
              'enableVibration': false,
              'vibrationPattern': null,
              'ledColor': 0,
              'audioAttributesUsage': 5,
            },
          ];
        case 'areNotificationsEnabled':
          return notificationsEnabled;
        case 'requestNotificationsPermission':
          return permissionGranted;
        default:
          return null;
      }
    });
    messenger.setMockMethodCallHandler(ReminderService.runtimeChannel, (
      call,
    ) async {
      if (call.method == 'supportsRuntimeNotificationPermission') {
        return supportsRuntimePermissionRequest;
      }
      if (call.method == 'openNotificationSettings') {
        settingsArguments.add(call.arguments);
        return true;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(_diagnosticsChannel, (call) async {
      if (call.method == 'record') {
        diagnosticRecords.add(Map<String, Object?>.from(call.arguments as Map));
      }
      return null;
    });
  });

  setUp(() {
    pluginCalls.clear();
    diagnosticRecords.clear();
    settingsArguments.clear();
    supportsRuntimePermissionRequest = false;
    notificationsEnabled = false;
    reminderChannelEnabled = true;
    permissionGranted = false;
    failInitialization = false;
  });

  tearDownAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_notificationsChannel, null);
    messenger.setMockMethodCallHandler(ReminderService.runtimeChannel, null);
    messenger.setMockMethodCallHandler(_diagnosticsChannel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'system settings open even when notification initialization fails',
    () async {
      failInitialization = true;

      final opened = await ReminderService.instance.openSystemSettings();

      expect(opened, isTrue);
      expect(pluginCalls, isNot(contains('initialize')));
      expect(settingsArguments, [null]);
    },
  );

  test(
    'notification initialization failure is visible and retryable',
    () async {
      failInitialization = true;

      await expectLater(
        ReminderService.instance.requestPermission(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'invalid_icon',
          ),
        ),
      );

      final failure = diagnosticRecords.singleWhere(
        (record) => record['event'] == 'reminder.permission.failure',
      );
      expect(
        failure['details'],
        contains('PlatformException(code=invalid_icon'),
      );

      failInitialization = false;
      notificationsEnabled = true;
      expect(await ReminderService.instance.requestPermission(), isTrue);
      expect(
        pluginCalls.where((method) => method == 'initialize'),
        hasLength(2),
      );
    },
  );

  test(
    'pre-Android 13 blocked notifications open settings instead of prompting',
    () async {
      final granted = await ReminderService.instance.requestPermission();

      expect(granted, isFalse);
      expect(pluginCalls, isNot(contains('requestNotificationsPermission')));
      expect(settingsArguments, [null]);
    },
  );

  test(
    'a blocked reminder channel opens its channel settings on older Android',
    () async {
      notificationsEnabled = true;
      reminderChannelEnabled = false;

      final granted = await ReminderService.instance.requestPermission();

      expect(granted, isFalse);
      expect(pluginCalls, isNot(contains('requestNotificationsPermission')));
      expect(settingsArguments, [ReminderService.channelId]);
    },
  );

  test(
    'Android 13+ keeps using the runtime notification permission prompt',
    () async {
      supportsRuntimePermissionRequest = true;
      notificationsEnabled = true;
      permissionGranted = true;

      final granted = await ReminderService.instance.requestPermission();

      expect(granted, isTrue);
      expect(pluginCalls, contains('requestNotificationsPermission'));
      expect(settingsArguments, isEmpty);
    },
  );
}
