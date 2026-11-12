import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Small bridge to the Windows runner that keeps the native title bar in sync
/// with the Flutter theme. On other platforms every call is a no-op.
class WindowChrome {
  WindowChrome._();

  static const MethodChannel _channel = MethodChannel('lm_chat/window');
  static bool? _lastDark;

  /// `true` paints the Win32 caption dark, `false` uses the light variant.
  static Future<void> setDarkTitleBar(bool dark) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    if (_lastDark == dark) return;
    _lastDark = dark;
    try {
      await _channel.invokeMethod<void>('setDarkTitleBar', dark);
    } on MissingPluginException {
      // Older runner or a platform without the channel: nothing to do.
    } catch (_) {
      // The native call is cosmetic; never break the UI because of it.
    }
  }
}
