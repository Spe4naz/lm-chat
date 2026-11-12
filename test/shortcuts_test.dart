import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/app_state.dart';
import 'package:lm_chat/models.dart';
import 'package:lm_chat/screens/home_screen.dart';
import 'package:lm_chat/screens/settings_screen.dart';
import 'package:lm_chat/theme.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('Ctrl+F focuses the chat search', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await _pumpHome(tester);

    await _pressCtrl(tester, LogicalKeyboardKey.keyF);

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('chat-search-field')),
    );
    expect(field.focusNode?.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Ctrl+N creates a new chat', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final state = await _pumpHome(tester);
    final before = state.data.chats.length;

    await _pressCtrl(tester, LogicalKeyboardKey.keyN);

    expect(state.data.chats.length, before + 1);
    expect(tester.takeException(), isNull);
    state.cancelPendingSaveForTest();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Ctrl+comma opens settings', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await _pumpHome(tester);

    await _pressCtrl(tester, LogicalKeyboardKey.comma);
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Ctrl+F opens the drawer on a phone-sized window', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await _pumpHome(tester, size: const Size(390, 844));

    await _pressCtrl(tester, LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();

    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
    expect(scaffold.isDrawerOpen, isTrue);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('chat-search-field')),
    );
    expect(field.focusNode?.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}

Future<void> _pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

Future<AppState> _pumpHome(
  WidgetTester tester, {
  Size size = const Size(1280, 820),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final state = AppState();
  addTearDown(state.dispose);
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
      ChatMessage(id: 'u1', role: 'user', content: 'hello'),
      ChatMessage(id: 'a1', role: 'assistant', content: 'hi'),
    ],
  );
  state.data.chats.add(chat);
  state.activeChat = chat;

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
  return state;
}
