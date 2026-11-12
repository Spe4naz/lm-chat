import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/app_state.dart';
import 'package:lm_chat/models.dart';

void main() {
  test('continueGeneration appends text and keeps the answer', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    Map<String, dynamic>? received;

    server.listen((request) async {
      if (request.uri.path == '/v1/chat/completions') {
        received = jsonDecode(
          await utf8.decodeStream(request),
        ) as Map<String, dynamic>;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.write(
          'data: {"choices":[{"delta":{"content":" ещё"}}]}\n\n',
        );
        request.response.write(
          'data: {"choices":[],"usage":{"prompt_tokens":10,'
          '"completion_tokens":2,"total_tokens":12}}\n\n',
        );
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
        return;
      }
      request.response.statusCode = 404;
      await request.response.close();
    });

    final dir = await Directory.systemTemp.createTemp('lm_chat_continue_');
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

    final answer = ChatMessage(
      id: 'a1',
      role: 'assistant',
      content: 'ответ',
      completionTokens: 5,
      generationMs: 1000,
    );
    final chat = ChatSession(
      id: 'chat',
      serverId: config.id,
      model: 'model',
      launch: const LaunchSettings(loadOnDemand: false),
      messages: [
        ChatMessage(id: 'u1', role: 'user', content: 'вопрос'),
        answer,
      ],
    );
    state.data.chats.add(chat);
    state.activeChat = chat;

    await state.continueGeneration();

    expect(answer.content, 'ответ ещё');
    expect(answer.versionCount, 1);
    expect(answer.completionTokens, 2);
    expect(answer.firstTokenMs, isNotNull);

    final messages = (received!['messages'] as List).cast<Map>();
    expect(messages.last['role'], 'assistant');
    expect(messages.last['content'], 'ответ');
  });
}
