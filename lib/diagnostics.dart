import 'package:flutter/services.dart';

class Diagnostics {
  Diagnostics._();

  static const _channel = MethodChannel('app.diary008/diagnostics');

  static Future<void> record(String event, [String details = '']) async {
    try {
      await _channel.invokeMethod<void>('record', {
        'event': event,
        'details': details,
      });
    } catch (_) {
      // Diagnostics must never interfere with the operation being observed.
    }
  }

  static Future<bool> export() async =>
      await _channel.invokeMethod<bool>('export') ?? false;

  static Future<void> clear() async {
    await _channel.invokeMethod<void>('clear');
  }
}
