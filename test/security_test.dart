import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/api.dart';
import 'package:lm_chat/app_state.dart';
import 'package:lm_chat/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('public HTTP base and bridge addresses are rejected', () {
    final base = ServerConfig(
      id: 'base',
      name: 'Public',
      baseUrl: 'http://8.8.8.8:1234',
    );
    expect(base.securityError, isNotNull);

    final bridge = ServerConfig(
      id: 'bridge',
      name: 'Cloud',
      baseUrl: 'https://example.com',
      bridgeUrl: 'http://example.com:1235',
    );
    expect(bridge.securityError, contains('Мост'));

    final local = ServerConfig(
      id: 'local',
      name: 'Home',
      baseUrl: 'http://192.168.1.5:1234',
      bridgeUrl: 'http://192.168.1.5:1235',
    );
    expect(local.securityError, isNull);

    final disabledBridge = ServerConfig(
      id: 'disabled',
      name: 'Cloud',
      baseUrl: 'https://example.com',
      bridgeUrl: 'http://example.com:1235',
      chatViaBridge: false,
    );
    expect(disabledBridge.securityError, isNotNull);
    expect(disabledBridge.generationSecurityError, isNull);
  });

  test('bridge address is not derived for a public base', () {
    expect(ServerConfig.bridgeUrlForBase('https://example.com'), '');
    expect(ServerConfig.bridgeUrlForBase('http://8.8.8.8:1234'), '');
    expect(
      ServerConfig.bridgeUrlForBase('http://192.168.1.5:1234'),
      'http://192.168.1.5:1235',
    );
  });

  test('a single-label hostname is not assumed to be local', () {
    final server = ServerConfig(
      id: 'dns',
      name: 'DNS',
      baseUrl: 'http://ubuntu:1234',
    );
    expect(server.securityError, isNotNull);
    expect(
      ServerConfig(
        id: 'mdns',
        name: 'mDNS',
        baseUrl: 'http://ubuntu.local:1234',
      ).securityError,
      isNull,
    );
  });

  test('client refuses unsafe servers before opening a socket', () async {
    final client = LmClient();
    addTearDown(client.close);

    final unsafeBase = ServerConfig(
      id: 'base',
      name: 'Public',
      baseUrl: 'http://8.8.8.8:1234',
    );
    await expectLater(
      client.fetchModelsInfo(unsafeBase),
      throwsA(isA<ApiException>()),
    );

    final unsafeBridge = ServerConfig(
      id: 'bridge',
      name: 'Cloud',
      baseUrl: 'https://example.com',
      bridgeUrl: 'http://example.com:1235',
    );
    await expectLater(
      client.bridgeHealth(unsafeBridge),
      throwsA(isA<ApiException>()),
    );
  });

  test('history import drops secrets and unsafe servers', () {
    final state = AppState();
    addTearDown(state.dispose);

    final preview = state.parseHistoryJson(
      jsonEncode({
        'servers': [
          {
            'id': 'evil',
            'name': 'Evil',
            'baseUrl': 'http://8.8.8.8:1234',
            'apiKey': 'leaked-api',
            'bridgeToken': 'leaked-bridge',
          },
          {
            'id': 'safe',
            'name': 'Home',
            'baseUrl': '192.168.1.5:1234',
            'apiKey': 'leaked-api',
            'bridgeToken': 'leaked-bridge',
          },
        ],
        'chats': [
          {'id': 'c1', 'title': 'One', 'serverId': 'evil', 'messages': []},
          {'id': 'c2', 'title': 'Two', 'serverId': 'safe', 'messages': []},
        ],
      }),
    );

    expect(preview.ok, isTrue);
    expect(preview.servers.map((server) => server.id), ['safe']);
    expect(preview.servers.single.apiKey, isEmpty);
    expect(preview.servers.single.bridgeToken, isEmpty);

    final result = state.importPreview(preview);
    expect(result.ok, isTrue);
    expect(state.data.servers.map((server) => server.id), ['safe']);
    expect(state.data.servers.single.apiKey, isEmpty);
    expect(state.data.servers.single.bridgeToken, isEmpty);
    expect(
      state.data.chats.firstWhere((chat) => chat.id == 'c1').serverId,
      'safe',
    );
  });

  test('profile import skips unsafe servers', () {
    final state = AppState();
    addTearDown(state.dispose);

    final preview = state.parseProfileJson(
      jsonEncode({
        'kind': 'lm-chat-profile',
        'servers': [
          {'id': 'evil', 'name': 'Evil', 'baseUrl': 'http://8.8.8.8:1234'},
        ],
        'settings': <String, dynamic>{},
      }),
    );

    expect(preview.ok, isTrue);
    expect(preview.profile!.servers, isEmpty);
    final result = state.importProfile(preview);
    expect(result.ok, isTrue);
    expect(state.data.servers, isEmpty);
  });
}
