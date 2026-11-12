import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class CustomFontSaveResult {
  const CustomFontSaveResult({required this.family, required this.fileName});

  final String family;
  final String fileName;
}

/// Stores an imported TTF file inside the app's documents folder and registers
/// it with the Flutter engine under a unique family name.
///
/// The family name changes on every import: re-registering the same family
/// while the app is running would keep the old font face in some backends.
class CustomFontService {
  CustomFontService._();

  static const String folderName = 'fonts';
  static const int maxBytes = 32 * 1024 * 1024;

  static Future<Directory> _directory() async {
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${documents.path}${Platform.pathSeparator}$folderName',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _safeFileName(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  static Future<File> _fileFor(String fileName) async {
    final dir = await _directory();
    return File(
      '${dir.path}${Platform.pathSeparator}${_safeFileName(fileName)}',
    );
  }

  /// Writes the font, registers it and removes the previous file.
  static Future<CustomFontSaveResult> save(
    Uint8List bytes, {
    String? oldFileName,
  }) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final family = 'LmCustomFont$stamp';
    final fileName = 'custom_$stamp.ttf';
    final file = await _fileFor(fileName);
    await file.writeAsBytes(bytes, flush: true);
    try {
      await _register(family, bytes);
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
    if (oldFileName != null &&
        oldFileName.isNotEmpty &&
        oldFileName != fileName) {
      final old = await _fileFor(oldFileName);
      if (await old.exists()) {
        try {
          await old.delete();
        } catch (_) {
          // A stale file is harmless; the new one is already active.
        }
      }
    }
    return CustomFontSaveResult(family: family, fileName: fileName);
  }

  /// Registers a previously imported font. Returns false when the file is
  /// missing or not a valid font.
  static Future<bool> loadSaved({
    required String family,
    required String fileName,
  }) async {
    if (family.isEmpty || fileName.isEmpty) return false;
    final file = await _fileFor(fileName);
    if (!await file.exists()) return false;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > maxBytes) return false;
    try {
      await _register(family, bytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> delete(String fileName) async {
    if (fileName.isEmpty) return;
    final file = await _fileFor(fileName);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {
        // The setting is cleared either way.
      }
    }
  }

  static Future<void> _register(String family, Uint8List bytes) {
    final loader = FontLoader(family)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    return loader.load();
  }
}
