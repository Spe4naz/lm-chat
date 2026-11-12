import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/app_state.dart';
import 'package:lm_chat/models.dart';

void main() {
  test('failed reload restores the previously loaded instance', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final loadBodies = <Map<String, dynamic>>[];
    var loadAttempt = 0;

    server.listen((request) async {
      final path = request.uri.path;
      if (path == '/api/v1/models') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'models': [
              {
                'key': 'model',
                'display_name': 'Model',
                'type': 'llm',
                'max_context_length': 32768,
                'loaded_instances': [
                  {
                    'id': 'inst-1',
                    'config': {
                      'context_length': 4096,
                      'flash_attention': true,
                      'offload_kv_cache_to_gpu': false,
                      'eval_batch_size': 512,
                    },
                  },
                ],
              },
            ],
          }),
        );
        await request.response.close();
        return;
      }
      if (path == '/api/v1/models/unload') {
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"status":"unloaded"}');
        await request.response.close();
        return;
      }
      if (path == '/api/v1/models/load') {
        final body = jsonDecode(
          await utf8.decodeStream(request),
        ) as Map<String, dynamic>;
        loadBodies.add(body);
        loadAttempt++;
        if (loadAttempt == 1) {
          request.response.statusCode = 500;
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"error":{"message":"out of memory"}}');
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"status":"loaded"}');
        }
        await request.response.close();
        return;
      }
      request.response.statusCode = 404;
      await request.response.close();
    });

    final dir = await Directory.systemTemp.createTemp('lm_chat_rollback_');
    addTearDown(() => dir.delete(recursive: true));
    final state = AppState();
    state.dataFileOverride = () async =>
        File('${dir.path}${Platform.pathSeparator}lm_chat_data.json');

    final config = ServerConfig(
      id: 'server',
      name: 'PC',
      baseUrl: 'http://127.0.0.1:${server.port}',
    );
    final chat = ChatSession(
      id: 'chat',
      serverId: 'server',
      model: 'model',
      launch: const LaunchSettings(contextLength: 8192, loadOnDemand: false),
    );
    state.data.servers.add(config);
    state.data.chats.add(chat);
    state.activeChat = chat;

    final result = await state.applyLaunchSettings(chat);

    expect(result.error, isNotNull);
    expect(loadBodies, hasLength(2));
    expect(loadBodies.first['context_length'], 8192);
    // The rollback reloads the context that was active before the failure.
    expect(loadBodies.last['context_length'], 4096);
    expect(loadBodies.last['eval_batch_size'], 512);
    expect(loadBodies.last['flash_attention'], true);
    expect(loadBodies.last['offload_kv_cache_to_gpu'], false);
  });
}
