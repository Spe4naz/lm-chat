import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/app_state.dart';
import 'package:lm_chat/models.dart';

void main() {
  test('resumeMessage continues a bridge job after a restart', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var since = -1;

    server.listen((request) async {
      if (request.uri.path == '/bridge/chat/job-1') {
        since = int.parse(request.uri.queryParameters['since'] ?? '0');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'ok': true,
            'events': [
              {'seq': 1, 'content': ' продолжение', 'reasoning': ''},
              {'seq': 2, 'content': ' ещё', 'reasoning': ''},
            ],
            'next': 2,
            'done': true,
            'error': null,
            'usage': {
              'prompt_tokens': 20,
              'completion_tokens': 2,
              'total_tokens': 22,
            },
            'elapsed_ms': 2500,
          }),
        );
        await request.response.close();
        return;
      }
      request.response.statusCode = 404;
      await request.response.close();
    });

    final dir = await Directory.systemTemp.createTemp('lm_chat_resume_');
    addTearDown(() => dir.delete(recursive: true));
    final state = AppState();
    state.dataFileOverride = () async =>
        File('${dir.path}${Platform.pathSeparator}lm_chat_data.json');

    final config = ServerConfig(
      id: 'server',
      name: 'PC',
      baseUrl: 'http://127.0.0.1:1234',
      bridgeUrl: 'http://127.0.0.1:${server.port}/bridge',
    );
    final message = ChatMessage(
      id: 'a1',
      role: 'assistant',
      content: 'начало',
      jobId: 'job-1',
      jobServerId: 'server',
      jobSeq: 0,
    );
    final chat = ChatSession(
      id: 'chat',
      serverId: 'server',
      model: 'model',
      messages: [
        ChatMessage(id: 'u1', role: 'user', content: 'вопрос'),
        message,
      ],
    );
    state.data.servers.add(config);
    state.data.chats.add(chat);

    await state.resumeMessage(chat, message);

    expect(since, 0);
    expect(message.content, 'начало продолжение ещё');
    expect(message.completionTokens, 2);
    expect(message.generationMs, 2500);
    expect(message.hasPendingJob, isFalse);
  });
}
