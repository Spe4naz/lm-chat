import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/l10n.dart';
import 'package:lm_chat/models.dart';

void main() {
  tearDown(() => L10n.setLanguage('ru'));

  test('built-in prompt names and contents are fully translated', () {
    L10n.setLanguage('en');
    for (final template in builtInPromptTemplates) {
      final name = L10n.t(template.name);
      final content = L10n.t(template.content);
      expect(
        RegExp(r'[А-Яа-яЁё]').hasMatch(name),
        isFalse,
        reason: 'name: $name',
      );
      expect(
        RegExp(r'[А-Яа-яЁё]').hasMatch(content),
        isFalse,
        reason: 'content: $content',
      );
    }
  });

  test('empty-chat starter prompts are translated', () {
    L10n.setLanguage('en');
    const prompts = [
      'Объясни простыми словами, как работает Transformer',
      'Помоги написать письмо коллеге о переносе встречи',
      'Придумай 5 идей для выходных в городе',
      'Напиши функцию на Dart для парсинга JSON',
    ];
    for (final prompt in prompts) {
      final translated = L10n.t(prompt);
      expect(
        RegExp(r'[А-Яа-яЁё]').hasMatch(translated),
        isFalse,
        reason: translated,
      );
      expect(translated, isNot(prompt));
    }
  });
}
