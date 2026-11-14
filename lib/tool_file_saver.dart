import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'l10n.dart';

/// Saves files reconstructed from tool calls.
///
/// The app has no direct access to the plugin workspace, but `fs_write`
/// arguments contain the complete file content, so it can offer the same file
/// for download on the device that runs LM Chat.
class ToolFileSaver {
  ToolFileSaver._();

  /// Opens the platform save dialog. Returns false when the user cancelled.
  static Future<bool> save({
    required String fileName,
    required String content,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    final destination = await FilePicker.saveFile(
      dialogTitle: L10n.t('Сохранить файл'),
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeTypeFor(fileName),
    );
    return destination != null;
  }

  /// MIME type used by the save dialog, mostly so mobile pickers show the
  /// right app suggestions.
  static String mimeTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
    if (lower.endsWith('.css')) return 'text/css';
    if (lower.endsWith('.js') || lower.endsWith('.mjs')) {
      return 'text/javascript';
    }
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.md')) return 'text/markdown';
    if (lower.endsWith('.xml')) return 'application/xml';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }
}
