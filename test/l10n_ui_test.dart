import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/app_state.dart';
import 'package:lm_chat/l10n.dart';
import 'package:lm_chat/models.dart';
import 'package:lm_chat/screens/home_screen.dart';
import 'package:lm_chat/screens/settings_screen.dart';
import 'package:lm_chat/screens/welcome_screen.dart';
import 'package:provider/provider.dart';

void main() {
  tearDown(() => L10n.setLanguage('ru'));

  testWidgets('settings and welcome have no Russian static labels in English', (
    tester,
  ) async {
    L10n.setLanguage('en');
    final state = AppState();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();

    final russian = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? '')
        .where((data) => RegExp(r'[А-Яа-яЁё]').hasMatch(data))
        .toList();
    expect(russian, isEmpty, reason: russian.join(' | '));

    await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));
    final welcomeRussian = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? '')
        .where((data) => RegExp(r'[А-Яа-яЁё]').hasMatch(data))
        .toList();
    expect(welcomeRussian, isEmpty, reason: welcomeRussian.join(' | '));

    final homeState = AppState();
    homeState.data.servers.add(
      ServerConfig(id: 'server', name: 'PC', baseUrl: '127.0.0.1:1234'),
    );
    homeState.data.activeServerId = 'server';
    homeState.setModelsForTest('server', const [
      LmModelInfo(key: 'model', displayName: 'Model', maxContextLength: 32768),
    ]);
    final chat = ChatSession(
      id: 'chat',
      serverId: 'server',
      model: 'model',
      title: 'Test chat',
      messages: [
        ChatMessage(id: 'u1', role: 'user', content: 'hello'),
        ChatMessage(id: 'a1', role: 'assistant', content: 'hi'),
      ],
    );
    homeState.data.chats.add(chat);
    homeState.activeChat = chat;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: homeState,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();

    final homeRussian = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? '')
        .where((data) => RegExp(r'[А-Яа-яЁё]').hasMatch(data))
        .toList();
    expect(homeRussian, isEmpty, reason: homeRussian.join(' | '));
  });
}
