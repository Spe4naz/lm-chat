import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/app_state.dart';
import 'package:lm_chat/models.dart';
import 'package:lm_chat/screens/home_screen.dart';
import 'package:lm_chat/theme.dart';
import 'package:provider/provider.dart';

AppState _stateWithChat() {
  final state = AppState();
  final server = ServerConfig(
    id: 'server',
    name: 'PC',
    baseUrl: '192.168.1.5:1234',
  );
  state.data.servers.add(server);
  state.data.activeServerId = server.id;
  state.setModelsForTest(server.id, const [
    LmModelInfo(key: 'model', displayName: 'Model', maxContextLength: 32768),
  ]);
  final chat = ChatSession(
    id: 'chat',
    serverId: server.id,
    model: 'model',
    title: 'Test chat',
    messages: [
      ChatMessage(id: 'u1', role: 'user', content: 'first question'),
      ChatMessage(id: 'a1', role: 'assistant', content: 'first answer'),
      ChatMessage(id: 'u2', role: 'user', content: 'second question'),
      ChatMessage(id: 'a2', role: 'assistant', content: 'second answer'),
    ],
  );
  state.data.chats.add(chat);
  state.activeChat = chat;
  return state;
}

void main() {
  test('messagesToMarkdown keeps only selected messages in chat order', () {
    final state = _stateWithChat();
    addTearDown(state.dispose);
    final chat = state.activeChat!;

    final markdown = state.messagesToMarkdown(chat, [
      chat.messages[3],
      chat.messages[0],
    ]);

    expect(markdown, contains('first question'));
    expect(markdown, contains('second answer'));
    expect(markdown, isNot(contains('first answer')));
    expect(markdown, isNot(contains('second question')));
    expect(
      markdown.indexOf('first question'),
      lessThan(markdown.indexOf('second answer')),
    );
    expect(markdown, contains('Выбранные сообщения: 2 из 4'));
  });

  test('messagesToMarkdown ignores messages from another chat', () {
    final state = _stateWithChat();
    addTearDown(state.dispose);
    final chat = state.activeChat!;

    final markdown = state.messagesToMarkdown(chat, [
      ChatMessage(id: 'foreign', role: 'user', content: 'not in chat'),
    ]);

    expect(markdown, isNot(contains('not in chat')));
    expect(markdown, contains('Выбранные сообщения: 0 из 4'));
  });

  testWidgets('chat menu selects messages and shows the selected count', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _stateWithChat();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать сообщения'));
    await tester.pumpAndSettle();

    expect(find.text('Выбрано: 0'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(4));

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.text('Выбрано: 1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.select_all_rounded));
    await tester.pump();
    expect(find.text('Выбрано: 4'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.deselect_rounded));
    await tester.pump();
    expect(find.text('Выбрано: 0'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
