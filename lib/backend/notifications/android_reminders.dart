import 'dart:convert';

import 'package:flutter/services.dart';

class AndroidReminders {
  static const _channel = MethodChannel('com.localpharmacy.app/reminders');

  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  Future<void> openSettings() => _channel.invokeMethod<void>('openSettings');

  Future<void> replace(bool enabled, List<Map<String, Object>> events) =>
      _channel.invokeMethod<void>('replace', {
        'enabled': enabled,
        'events': jsonEncode(events),
      });
}
