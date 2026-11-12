import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/app_state.dart';
import 'package:lm_chat/models.dart';
import 'package:lm_chat/widgets/context_indicator.dart';
import 'package:lm_chat/widgets/message_bubble.dart';

void main() {
  testWidgets('message bubble switches between saved versions', (tester) async {
    final message = ChatMessage(
      id: 'a1',
      role: 'assistant',
      content: 'новый ответ',
    );
    message.versions.add(ChatMessageVersion(id: 'v1', content: 'старый ответ'));
    message.selectVersion(1);

    final selected = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(message: message, onSelectVersion: selected.add),
        ),
      ),
    );

    expect(find.text('Вариант 1 из 2 — старый'), findsOneWidget);
    expect(find.textContaining('старый ответ'), findsOneWidget);

    await tester.tap(find.byTooltip('Следующий вариант'));
    expect(selected, [2]);
  });

  testWidgets('finished answer shows speed and generation time', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 'a1',
      role: 'assistant',
      content: 'ответ',
      completionTokens: 20,
      generationMs: 2000,
    );
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: message,
            onShowStats: () => opened = true,
          ),
        ),
      ),
    );

    expect(find.text('10.0 tok/s · 2.0 с'), findsOneWidget);
    await tester.tap(find.text('10.0 tok/s · 2.0 с'));
    expect(opened, isTrue);
  });

  testWidgets('context indicator shows the remaining window', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ContextIndicator(
            usage: ContextUsage(
              limit: 32768,
              used: 10000,
              estimated: false,
              source: 'модель',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Контекст: осталось 22 768 из 32 768'), findsOneWidget);
  });

  testWidgets('answer can be opened in the editor', (tester) async {
    final message = ChatMessage(id: 'a1', role: 'assistant', content: 'ответ');
    var edited = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(message: message, onEdit: () => edited = true),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Действия'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Редактировать ответ'));
    expect(edited, isTrue);
  });

  testWidgets('finished answer can be continued', (tester) async {
    final message = ChatMessage(id: 'a1', role: 'assistant', content: 'ответ');
    var continued = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: message,
            showContinue: true,
            onContinue: () => continued = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Действия'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продолжить ответ'));
    expect(continued, isTrue);
  });

  testWidgets('answer bubble survives large system text', (tester) async {
    final message = ChatMessage(
      id: 'a1',
      role: 'assistant',
      content: 'Ответ с достаточно длинным текстом для проверки переноса.',
      completionTokens: 20,
      generationMs: 2000,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: MessageBubble(message: message, onEdit: () {}),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('edited answer is marked in the bubble', (tester) async {
    final message = ChatMessage(
      id: 'a1',
      role: 'assistant',
      content: 'исправленный ответ',
      editedAt: DateTime(2026, 11, 9, 20, 0),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(message: message, onEdit: () {}),
        ),
      ),
    );

    expect(find.text('изменено'), findsOneWidget);
  });
}
