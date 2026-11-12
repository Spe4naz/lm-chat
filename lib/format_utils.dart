// Small formatting helpers shared by the model pickers and settings sheets.

import 'l10n.dart';

/// Groups thousands with a regular space: `32768` → `32 768`.
String formatNumber(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// `null` means "let LM Studio decide".
String formatContext(int? tokens) => tokens == null || tokens <= 0
    ? L10n.t('авто')
    : L10n.tf('{tokens} токенов', {'tokens': formatNumber(tokens)});

String formatSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  final units = L10n.isEnglish
      ? const ['B', 'KB', 'MB', 'GB', 'TB']
      : const ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = value >= 100 || unit == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

String formatDuration(int? seconds) {
  if (seconds == null || seconds <= 0) return L10n.t('по умолчанию');
  if (seconds % 3600 == 0) {
    final hours = seconds ~/ 3600;
    return hours == 1
        ? L10n.t('1 час')
        : L10n.tf('{hours} ч', {'hours': hours});
  }
  if (seconds % 60 == 0) {
    return L10n.tf('{minutes} мин', {'minutes': seconds ~/ 60});
  }
  return L10n.tf('{seconds} с', {'seconds': seconds});
}

/// `8340` ms → `8.3 с`; long generations are shown in minutes.
String formatGenerationTime(int? millis) {
  if (millis == null || millis <= 0) return '';
  final seconds = millis / 1000;
  if (seconds < 60) {
    return L10n.tf('{seconds} с', {
      'seconds': seconds.toStringAsFixed(seconds < 10 ? 1 : 0),
    });
  }
  final minutes = seconds ~/ 60;
  final rest = (seconds - minutes * 60).round();
  return L10n.tf('{minutes} мин {rest} с', {'minutes': minutes, 'rest': rest});
}

/// `2450` tokens in `8340` ms → `29.4 tok/s`.
String formatTokensPerSecond(int? tokens, int? millis) {
  if (tokens == null || tokens <= 0 || millis == null || millis <= 0) {
    return '';
  }
  return '${(tokens * 1000 / millis).toStringAsFixed(1)} tok/s';
}

String triStateLabel(bool? value) {
  if (value == null) return 'авто';
  return value ? 'включено' : 'выключено';
}

String formatGpuRatio(double? ratio) {
  if (ratio == null) return 'авто';
  if (ratio <= 0) return 'только CPU';
  return '${(ratio * 100).round()}%';
}

/// Removes ANSI escape sequences from CLI output before showing it in the UI.
String stripAnsi(String text) =>
    text.replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '');
