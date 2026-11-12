import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/app_state.dart';
import 'package:lm_chat/models.dart';

void main() {
  test('two chats can generate at the same time', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    server.listen((request) async {
      if (request.uri.path != '/v1/chat/completions') {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      final body =
          jsonDecode(await utf8.decodeStream(request)) as Map<String, dynamic>;
      final messages = (body['messages'] as List).cast<Map>();
      final last = messages.last['content'] as String;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      request.response.write(
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': 'ответ на $last'},
            },
          ],
        })}\n\n',
      );
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });

    final dir = await Directory.systemTemp.createTemp('lm_chat_parallel_');
    addTearDown(() => dir.delete(recursive: true));
    final state = AppState();
    state.dataFileOverride = () async =>
        File('${dir.path}${Platform.pathSeparator}lm_chat_data.json');

    final config = ServerConfig(
      id: 'server',
      name: 'PC',
      baseUrl: 'http://127.0.0.1:${server.port}',
    );
    state.data.servers.add(config);
    state.data.activeServerId = config.id;

    final first = ChatSession(
      id: 'chat-1',
      serverId: config.id,
      model: 'model',
      launch: const LaunchSettings(loadOnDemand: false),
    );
    final second = ChatSession(
      id: 'chat-2',
      serverId: config.id,
      model: 'model',
      launch: const LaunchSettings(loadOnDemand: false),
    );
    state.data.chats.addAll([first, second]);

    state.activeChat = first;
    final firstSend = state.send('первый');
    state.activeChat = second;
    final secondSend = state.send('второй');

    expect(state.isGenerating(first), isTrue);
    expect(state.isGenerating(second), isTrue);

    await Future.wait([firstSend, secondSend]);

    expect(state.isGenerating(first), isFalse);
    expect(state.isGenerating(second), isFalse);
    expect(first.messages.last.content, 'ответ на первый');
    expect(second.messages.last.content, 'ответ на второй');
  });
}
