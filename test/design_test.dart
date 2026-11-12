import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/app_state.dart';
import 'package:lm_chat/models.dart';
import 'package:lm_chat/profile.dart';
import 'package:lm_chat/screens/home_screen.dart';
import 'package:lm_chat/theme.dart';
import 'package:provider/provider.dart';

void main() {
  test('font preferences survive json round trip', () {
    final data = AppData(fontFamily: AppFontFamily.manrope, fontScale: 1.1);
    final restored = AppData.fromJson(data.toJson());
    expect(restored.fontFamily, AppFontFamily.manrope);
    expect(restored.fontScale, 1.1);
  });

  test('font scale is clamped to a sane range', () {
    final data = AppData.fromJson({'fontScale': 4.0});
    expect(data.fontScale, 1.3);
  });

  test('density and sidebar preferences survive json round trip', () {
    final data = AppData(
      uiDensity: UiDensity.compact,
      sidebarWidth: 400,
      sidebarCollapsed: true,
    );
    final restored = AppData.fromJson(data.toJson());
    expect(restored.uiDensity, UiDensity.compact);
    expect(restored.sidebarWidth, 400);
    expect(restored.sidebarCollapsed, isTrue);
  });

  test('sidebar width is clamped to a usable range', () {
    expect(AppData.fromJson({'sidebarWidth': 900}).sidebarWidth, 480);
    expect(AppData.fromJson({'sidebarWidth': 100}).sidebarWidth, 240);
  });

  test('theme exposes the selected density', () {
    final compact = buildTheme(Brightness.dark, density: UiDensity.compact);
    expect(compact.extension<AppDensity>()?.compact, isTrue);
    expect(compact.visualDensity, VisualDensity.compact);

    final normal = buildTheme(Brightness.dark);
    expect(normal.extension<AppDensity>()?.compact, isFalse);
    expect(normal.visualDensity, VisualDensity.standard);
  });

  test('theme applies the selected font family', () {
    final theme = buildTheme(Brightness.dark, fontFamily: 'Inter');
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
    expect(theme.extension<AppColors>(), isNotNull);
  });

  test('custom font preferences survive json round trip', () {
    final data = AppData(
      fontFamily: AppFontFamily.custom,
      customFontName: 'My Font',
      customFontFamily: 'LmCustomFont42',
      customFontFile: 'custom_42.ttf',
    );
    expect(data.effectiveFontFamily, 'LmCustomFont42');
    final restored = AppData.fromJson(data.toJson());
    expect(restored.fontFamily, AppFontFamily.custom);
    expect(restored.customFontName, 'My Font');
    expect(restored.customFontFamily, 'LmCustomFont42');
    expect(restored.customFontFile, 'custom_42.ttf');
    expect(restored.effectiveFontFamily, 'LmCustomFont42');
  });

  test('missing custom font data falls back to the theme default', () {
    final data = AppData(fontFamily: AppFontFamily.custom);
    expect(data.effectiveFontFamily, isNull);
  });

  test('profile export does not select a custom font', () {
    final data = AppData(
      fontFamily: AppFontFamily.custom,
      customFontFamily: 'LmCustomFont42',
      customFontFile: 'custom_42.ttf',
    );
    expect(AppProfile.fromData(data).fontFamily, AppFontFamily.system);
  });

  testWidgets('wide layout uses a permanent sidebar', (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
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

    expect(find.byType(Drawer), findsNothing);
    expect(find.text('Новый чат'), findsOneWidget);
    expect(find.text('Серверы и настройки'), findsOneWidget);
    expect(find.text('Test chat'), findsWidgets);
    expect(tester.takeException(), isNull);

    final widthBefore = state.data.sidebarWidth;
    await tester.drag(
      find.byKey(const ValueKey('sidebar-resizer')),
      const Offset(36, 0),
    );
    await tester.pump();
    expect(state.data.sidebarWidth, greaterThan(widthBefore));
    await tester.pump(const Duration(milliseconds: 700));

    await tester.tap(find.byIcon(Icons.menu_open_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Новый чат'), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Новый чат'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('narrow layout keeps the drawer and composer', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
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

    expect(find.byIcon(Icons.menu), findsOneWidget);
    expect(find.text('Сообщение'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
