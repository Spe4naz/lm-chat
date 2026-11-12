import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/app_state.dart';
import 'package:lm_chat/models.dart';
import 'package:lm_chat/secret_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('overlapping saves are serialised and leave no temp file', () async {
    final dir = await Directory.systemTemp.createTemp('lm_chat_save_');
    addTearDown(() => dir.delete(recursive: true));
    final target = File(
      '${dir.path}${Platform.pathSeparator}lm_chat_data.json',
    );

    final state = AppState();
    state.dataFileOverride = () async => target;
    state.data.chats.add(
      ChatSession(
        id: 'chat',
        serverId: 'server',
        messages: [ChatMessage(id: 'm1', role: 'user', content: 'привет')],
      ),
    );

    // Before the fix these three saves shared one .tmp file and the second
    // rename failed with PathNotFoundException.
    await Future.wait([
      state.saveForTest(),
      state.saveForTest(),
      state.saveForTest(),
    ]);

    expect(target.existsSync(), isTrue);
    final decoded =
        jsonDecode(await target.readAsString()) as Map<String, dynamic>;
    expect(decoded['chats'], isA<List<dynamic>>());
    expect((decoded['chats'] as List<dynamic>), isNotEmpty);
    expect(File('${target.path}.tmp').existsSync(), isFalse);

    // The queue keeps working after the burst.
    state.data.defaultTemperature = 0.5;
    await state.saveForTest();
    final again =
        jsonDecode(await target.readAsString()) as Map<String, dynamic>;
    expect(again['defaultTemperature'], 0.5);
    expect(again['schemaVersion'], AppData.currentSchemaVersion);
  });

  test('save keeps a backup of the previous history', () async {
    final dir = await Directory.systemTemp.createTemp('lm_chat_backup_');
    addTearDown(() => dir.delete(recursive: true));
    final target = File(
      '${dir.path}${Platform.pathSeparator}lm_chat_data.json',
    );
    await target.writeAsString('{"chats":[],"marker":"old"}');

    final state = AppState();
    state.dataFileOverride = () async => target;
    state.data.chats.add(ChatSession(id: 'chat', serverId: 'server'));
    await state.saveForTest();

    final backup = File('${target.path}.bak');
    expect(backup.existsSync(), isTrue);
    expect(await backup.readAsString(), contains('"marker":"old"'));
    expect(await target.readAsString(), contains('"chat"'));
  });

  test('damaged history is restored from the backup', () async {
    final dir = await Directory.systemTemp.createTemp('lm_chat_restore_');
    addTearDown(() => dir.delete(recursive: true));
    final target = File(
      '${dir.path}${Platform.pathSeparator}lm_chat_data.json',
    );
    await target.writeAsString('{not json');
    await File('${target.path}.bak').writeAsString(
      jsonEncode(
        AppData(
          chats: [ChatSession(id: 'restored', serverId: 'server')],
          setupDone: true,
        ).toJson(),
      ),
    );

    final state = AppState();
    state.dataFileOverride = () async => target;
    await state.init();

    expect(state.data.chats.single.id, 'restored');
    expect(state.data.setupDone, isTrue);
    expect(state.statusMessage, contains('резервной копии'));
  });

  test('secrets move to the secure store and leave the JSON', () async {
    final dir = await Directory.systemTemp.createTemp('lm_chat_secrets_');
    addTearDown(() => dir.delete(recursive: true));
    final target = File(
      '${dir.path}${Platform.pathSeparator}lm_chat_data.json',
    );
    final store = MemorySecretStore();
    final state = AppState(secretStore: store);
    state.dataFileOverride = () async => target;
    state.data.servers.add(
      ServerConfig(
        id: 'server',
        name: 'PC',
        baseUrl: 'http://192.168.1.5:1234',
        apiKey: 'api-secret',
        bridgeUrl: 'http://192.168.1.5:1235',
        bridgeToken: 'bridge-secret',
      ),
    );

    await state.init();
    await state.saveForTest();

    final stored = await store.read('server');
    expect(stored.apiKey, 'api-secret');
    expect(stored.bridgeToken, 'bridge-secret');

    final json = await target.readAsString();
    expect(json, isNot(contains('api-secret')));
    expect(json, isNot(contains('bridge-secret')));
  });

  test(
    'tokens never reach JSON when the secure store is unavailable',
    () async {
      final dir = await Directory.systemTemp.createTemp('lm_chat_no_keystore_');
      addTearDown(() => dir.delete(recursive: true));
      final target = File(
        '${dir.path}${Platform.pathSeparator}lm_chat_data.json',
      );
      final state = AppState(secretStore: _UnavailableSecretStore());
      state.dataFileOverride = () async => target;
      state.data.servers.add(
        ServerConfig(
          id: 'server',
          name: 'PC',
          baseUrl: 'http://192.168.1.5:1234',
          apiKey: 'api-secret',
          bridgeUrl: 'http://192.168.1.5:1235',
          bridgeToken: 'bridge-secret',
        ),
      );

      await state.init();
      await state.saveForTest();

      final json = await target.readAsString();
      expect(json, isNot(contains('api-secret')));
      expect(json, isNot(contains('bridge-secret')));
    },
  );

  test('legacy plaintext history and backup are scrubbed', () async {
    final dir = await Directory.systemTemp.createTemp('lm_chat_legacy_');
    addTearDown(() => dir.delete(recursive: true));
    final target = File(
      '${dir.path}${Platform.pathSeparator}lm_chat_data.json',
    );
    final legacy = jsonEncode({
      'schemaVersion': AppData.currentSchemaVersion,
      'servers': [
        ServerConfig(
          id: 'server',
          name: 'PC',
          baseUrl: 'http://192.168.1.5:1234',
          apiKey: 'api-secret',
          bridgeUrl: 'http://192.168.1.5:1235',
          bridgeToken: 'bridge-secret',
        ).toJson(includeSecrets: true),
      ],
      'chats': <dynamic>[],
    });
    await target.writeAsString(legacy);
    await File('${target.path}.bak').writeAsString(legacy);

    final state = AppState(secretStore: _UnavailableSecretStore());
    state.dataFileOverride = () async => target;
    await state.init();

    final main = await target.readAsString();
    final backup = await File('${target.path}.bak').readAsString();
    for (final text in [main, backup]) {
      expect(text, isNot(contains('api-secret')));
      expect(text, isNot(contains('bridge-secret')));
    }
  });
}

class _UnavailableSecretStore implements SecretStore {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<ServerSecrets> read(String serverId) async => const ServerSecrets();

  @override
  Future<void> write(String serverId, ServerSecrets secrets) async {}

  @override
  Future<void> delete(String serverId) async {}
}
