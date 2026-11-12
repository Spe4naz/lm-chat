import 'dart:collection';

import 'package:flutter/foundation.dart';

enum LogLevel { info, warning, error }

@immutable
class LogEntry {
  const LogEntry({
    required this.time,
    required this.level,
    required this.message,
    this.detail,
  });

  final DateTime time;
  final LogLevel level;
  final String message;
  final String? detail;

  String get formattedTime {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  String toText() {
    final buffer = StringBuffer('$formattedTime [${level.name}] $message');
    if (detail != null && detail!.isNotEmpty) {
      buffer.write('\n  $detail');
    }
    return buffer.toString();
  }
}

/// Small in-memory log for the diagnostics screen.
///
/// It is deliberately capped and never written to disk. Callers must not pass
/// API keys, bridge tokens or full prompts: the log can be copied and shared.
class AppLog extends ChangeNotifier {
  AppLog._();

  static final AppLog instance = AppLog._();
  static const int maxEntries = 200;

  final Queue<LogEntry> _entries = Queue<LogEntry>();

  List<LogEntry> get entries => List.unmodifiable(_entries);

  void add(LogLevel level, String message, {String? detail}) {
    _entries.addLast(
      LogEntry(
        time: DateTime.now(),
        level: level,
        message: message,
        detail: detail,
      ),
    );
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
    notifyListeners();
  }

  void info(String message, {String? detail}) =>
      add(LogLevel.info, message, detail: detail);

  void warning(String message, {String? detail}) =>
      add(LogLevel.warning, message, detail: detail);

  void error(String message, {String? detail}) =>
      add(LogLevel.error, message, detail: detail);

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  String asText() => _entries.map((entry) => entry.toText()).join('\n');
}
