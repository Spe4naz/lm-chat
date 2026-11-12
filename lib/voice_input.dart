import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'l10n.dart';

/// Locale id understood by Android's speech recognizer.
String voiceLocaleFor({required bool english}) => english ? 'en_US' : 'ru_RU';

/// Result of replacing a range with dictated words.
class DictationEdit {
  const DictationEdit({required this.value, required this.range});

  final TextEditingValue value;

  /// The range that the next partial result should replace.
  final TextRange range;
}

/// Inserts recognized speech at [range], keeping the text before and after it.
///
/// Android reports the whole utterance on every partial result, so the range
/// returned by a previous call must be replaced instead of appended to.
DictationEdit applyDictation({
  required TextEditingValue value,
  required TextRange range,
  required String words,
}) {
  final text = value.text;
  final start = range.start.clamp(0, text.length);
  final end = range.end.clamp(start, text.length);
  if (words.isEmpty) {
    return DictationEdit(
      value: value,
      range: TextRange(start: start, end: end),
    );
  }

  final needsSpace =
      start > 0 &&
      !_whitespace.hasMatch(text[start - 1]) &&
      !_leadingPunctuation.hasMatch(words);
  final insertion = needsSpace ? ' $words' : words;
  final nextText = text.replaceRange(start, end, insertion);
  final nextEnd = start + insertion.length;
  return DictationEdit(
    value: TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextEnd),
      composing: TextRange.empty,
    ),
    range: TextRange(start: start, end: nextEnd),
  );
}

final _whitespace = RegExp(r'\s');
final _leadingPunctuation = RegExp(r'^[\s.,!?;:)\]}»…]');

/// Thin wrapper around `speech_to_text`.
///
/// Keeping the plugin behind this class means the composer does not depend on
/// platform channels and the text insertion logic stays unit-testable.
class VoiceInputController extends ChangeNotifier {
  VoiceInputController({SpeechToText? engine})
    : _engine = engine ?? SpeechToText();

  final SpeechToText _engine;

  bool _initialized = false;
  bool _available = false;
  bool _starting = false;
  bool _listening = false;
  bool _disposed = false;
  String? _lastError;

  void Function(String words, bool isFinal)? _onWords;
  void Function(String message)? _onError;

  bool get listening => _listening;

  bool get starting => _starting;

  bool get available => _available;

  String? get lastError => _lastError;

  /// Starts dictation. Returns false when the device cannot recognize speech;
  /// [onError] receives a ready-to-show message in that case.
  Future<bool> start({
    required String localeId,
    required void Function(String words, bool isFinal) onWords,
    required void Function(String message) onError,
    String? contextualHint,
  }) async {
    if (_listening || _starting) return false;
    _starting = true;
    _lastError = null;
    _onWords = onWords;
    _onError = onError;
    _notify();

    try {
      if (!_initialized) {
        _available = await _engine.initialize(
          onError: _handleError,
          onStatus: _handleStatus,
        );
        _initialized = true;
      }
      if (!_available) {
        // Allow the next tap to retry after the user grants the microphone
        // permission in the system settings.
        _initialized = false;
        if (_lastError == null) {
          _fail(
            'Распознавание речи недоступно. Установите сервис распознавания '
            'Google или включите микрофон в настройках.',
          );
        }
        return false;
      }
      if (_disposed) return false;

      await _engine.listen(
        onResult: (result) {
          _onWords?.call(result.recognizedWords, result.finalResult);
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          pauseFor: const Duration(seconds: 4),
          listenFor: const Duration(minutes: 2),
          localeId: localeId,
          contextualPhrases: contextualHint == null || contextualHint.isEmpty
              ? null
              : [contextualHint],
        ),
      );
      _listening = true;
      return true;
    } catch (error) {
      _fail(
        L10n.tf('Не удалось начать распознавание речи: {error}', {
          'error': friendlySpeechError(error),
        }),
      );
      return false;
    } finally {
      _starting = false;
      _notify();
    }
  }

  Future<void> stop() async {
    if (!_initialized) return;
    try {
      // stop() waits for the final result, which is delivered to `onWords`.
      await _engine.stop();
    } catch (_) {
      // The recognizer may already be stopped.
    }
    _listening = false;
    _notify();
  }

  Future<void> cancel() async {
    if (!_initialized) return;
    try {
      await _engine.cancel();
    } catch (_) {
      // Nothing to cancel.
    }
    _listening = false;
    _notify();
  }

  void _handleStatus(String status) {
    final listening = status == SpeechToText.listeningStatus;
    if (listening != _listening) {
      _listening = listening;
      _notify();
    }
  }

  void _handleError(SpeechRecognitionError error) {
    _listening = false;
    _fail(speechErrorMessage(error.errorMsg));
  }

  void _fail(String message) {
    _listening = false;
    _lastError = message;
    _onError?.call(message);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_initialized) {
      unawaited(_engine.cancel());
    }
    super.dispose();
  }
}

/// Maps Android/iOS recognition errors to short user-facing text.
String speechErrorMessage(String code) {
  switch (code) {
    case 'error_no_match':
      return L10n.t('Речь не распознана. Попробуйте ещё раз.');
    case 'error_network':
    case 'error_network_timeout':
    case 'error_server':
      return L10n.t(
        'Сервис распознавания недоступен. Проверьте подключение к сети.',
      );
    case 'error_audio':
    case 'error_audio_error':
      return L10n.t('Не удалось записать звук. Проверьте микрофон.');
    case 'error_permission':
    case 'error_insufficient_permissions':
      return L10n.t(
        'Нет доступа к микрофону. Разрешите его в настройках приложения.',
      );
    case 'error_language_not_supported':
    case 'error_language_unavailable':
      return L10n.t('Этот язык не поддерживается распознаванием речи.');
    case 'error_busy':
      return L10n.t('Распознавание уже запущено.');
    case 'error_speech_timeout':
      return L10n.t('Речь не распознана. Попробуйте ещё раз.');
    default:
      return L10n.tf('Ошибка распознавания речи: {code}', {'code': code});
  }
}

String friendlySpeechError(Object error) {
  final text = error.toString().replaceFirst('Exception: ', '');
  return text.length > 160 ? '${text.substring(0, 160)}…' : text;
}
