import 'dart:io';

import 'package:flutter/services.dart';

/// Keeps the Android process alive while an answer is being generated.
///
/// A foreground service with a partial wake lock stops the system from freezing
/// the app in the background, so the streaming connection is not torn down.
class BackgroundKeepAlive {
  BackgroundKeepAlive._();

  static const _channel = MethodChannel('lm_chat/keepalive');

  static int _depth = 0;

  /// Shows the ongoing notification and acquires the wake lock. Nested calls
  /// are reference counted, so loading a model and then streaming reuse the
  /// same service.
  static Future<void> start([String text = 'Готовится ответ…']) async {
    if (!Platform.isAndroid) return;
    _depth++;
    if (_depth > 1) return;
    try {
      await _channel.invokeMethod<void>('start', {'text': text});
    } catch (_) {
      // Missing plugin (tests, desktop) or a vendor ROM restriction.
      _depth = 0;
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    if (_depth > 0) _depth--;
    if (_depth > 0) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {
      // Nothing to stop.
    }
  }
}
