import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/l10n.dart';
import 'package:lm_chat/l10n_text.dart' as localized;

void main() {
  tearDown(() => L10n.setLanguage('ru'));

  test('English translations and placeholders work', () {
    L10n.setLanguage('en');
    expect(L10n.t('Новый чат'), 'New chat');
    expect(L10n.t('Выберите модель'), 'Select a model');
    expect(
      L10n.tf('Импортировано чатов: {count}', {'count': 3}),
      'Imported chats: 3',
    );
    expect(L10n.t('Неизвестная строка'), 'Неизвестная строка');
  });

  test('Russian is the default and fallback', () {
    L10n.setLanguage('ru');
    expect(L10n.t('Новый чат'), 'Новый чат');
    expect(
      L10n.tf('Импортировано чатов: {count}', {'count': 3}),
      'Импортировано чатов: 3',
    );
  });

  test('known fragments translate concatenated text', () {
    L10n.setLanguage('en');
    expect(L10n.t('Отправить'), 'Send');
  });

  testWidgets('localized Text widget renders English', (tester) async {
    L10n.setLanguage('en');
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: localized.Text('Новый чат'))),
    );
    expect(find.text('New chat'), findsOneWidget);
    expect(find.text('Новый чат'), findsNothing);
  });
}
