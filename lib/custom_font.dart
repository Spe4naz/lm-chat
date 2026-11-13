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

  /// Only generated names such as `custom_1730000000000000.ttf` and older
  /// sanitized names are accepted. Path separators, `..`, control characters
  /// and names without the `.ttf` extension are rejected.
  static final RegExp _fileNamePattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._-]{0,120}\.ttf$',
    caseSensitive: false,
  );

  static Future<Directory> _directory() async {
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${documents.path}${Platform.pathSeparator}$folderName',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String? _safeFileName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 128) return null;
    if (trimmed.contains('..') ||
        trimmed.contains('/') ||
        trimmed.contains(r'\')) {
      return null;
    }
    return _fileNamePattern.hasMatch(trimmed) ? trimmed : null;
  }

  /// True when [name] is a plain TTF file name that stays inside `fonts/`.
  static bool isValidFileName(String name) => _safeFileName(name) != null;

  static Future<File> _fileFor(String fileName) async {
    final directory = await _directory();
    final safe = _safeFileName(fileName);
    if (safe == null) {
      throw ArgumentError.value(fileName, 'fileName', 'Invalid font file name');
    }
    final directoryPath = directory.absolute.path;
    final file = File('$directoryPath${Platform.pathSeparator}$safe');
    if (file.parent.absolute.path != directoryPath) {
      throw ArgumentError.value(fileName, 'fileName', 'Path escapes fonts/');
    }
    // Never follow a symlink planted inside the fonts directory.
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw ArgumentError.value(fileName, 'fileName', 'Font file is a symlink');
    }
    return file;
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
      try {
        final old = await _fileFor(oldFileName);
        if (await old.exists()) await old.delete();
      } catch (_) {
        // An invalid or stale old name is harmless; the new font is active.
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
    final File file;
    try {
      file = await _fileFor(fileName);
    } catch (_) {
      return false;
    }
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
    try {
      final file = await _fileFor(fileName);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // The setting is cleared either way.
    }
  }

  static Future<void> _register(String family, Uint8List bytes) {
    final loader = FontLoader(family)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    return loader.load();
  }
}
