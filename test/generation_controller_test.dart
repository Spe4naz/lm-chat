import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/generation_controller.dart';
import 'package:lm_chat/models.dart';

void main() {
  test('health capabilities skip the bridge chat endpoint', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var bridgeChatCalls = 0;
    var directCalls = 0;

    server.listen((request) async {
      final path = request.uri.path;
      if (path == '/bridge/health') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          '{"ok":true,"api":2,"features":["load","estimate"]}',
        );
        await request.response.close();
        return;
      }
      if (path == '/bridge/chat') {
        bridgeChatCalls++;
        request.response.statusCode = 500;
        await request.response.close();
        return;
      }
      if (path == '/v1/chat/completions') {
        directCalls++;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.write(
          'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n',
        );
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
        return;
      }
      request.response.statusCode = 404;
      await request.response.close();
    });

    final config = ServerConfig(
      id: 'server',
      name: 'PC',
      baseUrl: 'http://127.0.0.1:${server.port}',
      bridgeUrl: 'http://127.0.0.1:${server.port}/bridge',
      chatViaBridge: true,
    );
    final chat = ChatSession(
      id: 'chat',
      serverId: config.id,
      model: 'model',
      launch: const LaunchSettings(loadOnDemand: false),
    );
    final message = ChatMessage(id: 'a1', role: 'assistant');

    final controller = GenerationController();
    addTearDown(controller.dispose);
    final chunks = await controller
        .begin(
          server: config,
          chat: chat,
          placeholder: message,
          history: [
            {'role': 'user', 'content': 'hi'},
          ],
          onBridgeUnsupported: (_) {},
        )
        .toList();

    expect(chunks.map((chunk) => chunk.content).join(), 'ok');
    expect(bridgeChatCalls, 0);
    expect(directCalls, 1);
  });
}
