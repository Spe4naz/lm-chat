import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/api.dart';
import 'package:lm_chat/models.dart';

void main() {
  group('buildMcpChatBody', () {
    test(
      'uses the last user turn as input and folds history into the prompt',
      () {
        final body = buildMcpChatBody(
          model: 'qwen',
          messages: [
            {'role': 'system', 'content': 'Ты помощник.'},
            {'role': 'user', 'content': 'Привет'},
            {'role': 'assistant', 'content': 'Здравствуйте'},
            {'role': 'user', 'content': 'Создай папку'},
          ],
          integrationId: 'lmchat/lm-computer',
          temperature: 0.2,
          topP: 0.9,
          maxTokens: 512,
          contextLength: 8192,
        );

        expect(body['input'], 'Создай папку');
        final prompt = body['system_prompt'] as String;
        expect(prompt, contains('Ты помощник.'));
        expect(prompt, contains('История диалога:'));
        expect(prompt, contains('Пользователь: Привет'));
        expect(prompt, contains('Ассистент: Здравствуйте'));
        expect(prompt, isNot(contains('Создай папку')));
      },
    );

    test('requests the plugin integration and streaming', () {
      final body = buildMcpChatBody(
        model: 'qwen',
        messages: [
          {'role': 'user', 'content': 'hi'},
        ],
        integrationId: 'mcp/lm-computer',
        temperature: 0,
        topP: 1,
        maxTokens: 0,
      );

      expect(body['model'], 'qwen');
      expect(body['stream'], isTrue);
      expect(body['store'], isFalse);
      expect(body['integrations'], [
        {'type': 'plugin', 'id': 'mcp/lm-computer'},
      ]);
      expect(body.containsKey('max_output_tokens'), isFalse);
      expect(body.containsKey('context_length'), isFalse);
      expect(body.containsKey('system_prompt'), isFalse);
    });

    test('keeps a trailing assistant turn as transcript', () {
      final body = buildMcpChatBody(
        model: 'qwen',
        messages: [
          {'role': 'user', 'content': 'Первый'},
          {'role': 'assistant', 'content': 'Ответ'},
        ],
        integrationId: 'lmchat/lm-computer',
        temperature: 0,
        topP: 1,
        maxTokens: 100,
      );

      expect(body['input'], 'Продолжи диалог.');
      expect(body['system_prompt'], contains('Ассистент: Ответ'));
    });

    test('ignores empty messages', () {
      final body = buildMcpChatBody(
        model: 'qwen',
        messages: [
          {'role': 'system', 'content': '   '},
          {'role': 'user', 'content': 'Запрос'},
        ],
        integrationId: 'lmchat/lm-computer',
        temperature: 0,
        topP: 1,
        maxTokens: 10,
      );

      expect(body['input'], 'Запрос');
      expect(body.containsKey('system_prompt'), isFalse);
    });
  });

  group('mcpChunkFromEvent', () {
    test('maps message and reasoning deltas', () {
      final message = mcpChunkFromEvent({
        'type': 'message.delta',
        'content': 'ok',
      });
      expect(message?.content, 'ok');
      expect(message?.reasoning, '');

      final reasoning = mcpChunkFromEvent({
        'type': 'reasoning.delta',
        'content': 'думаю',
      });
      expect(reasoning?.content, '');
      expect(reasoning?.reasoning, 'думаю');
    });

    test('reports tool calls', () {
      final chunk = mcpChunkFromEvent({
        'type': 'tool_call.start',
        'tool': 'fs_mkdir',
      });
      expect(chunk?.tool, 'fs_mkdir');
      expect(chunk?.content, '');
    });

    test('converts chat.end stats into usage', () {
      final chunk = mcpChunkFromEvent({
        'type': 'chat.end',
        'result': {
          'stats': {'input_tokens': 10, 'total_output_tokens': 5},
        },
      });
      expect(chunk?.usage?.promptTokens, 10);
      expect(chunk?.usage?.completionTokens, 5);
      expect(chunk?.usage?.totalTokens, 15);
    });

    test('ignores events without payload', () {
      expect(mcpChunkFromEvent({'type': 'chat.start'}), isNull);
      expect(mcpChunkFromEvent({'type': 'message.start'}), isNull);
      expect(
        mcpChunkFromEvent({
          'type': 'chat.end',
          'result': {'stats': <String, dynamic>{}},
        }),
        isNull,
      );
    });

    test('raises server errors', () {
      expect(
        () => mcpChunkFromEvent({
          'type': 'error',
          'error': {'message': 'Permission denied'},
        }),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            contains('Permission denied'),
          ),
        ),
      );
    });
  });

  group('ServerConfig MCP fields', () {
    test('are off by default and survive a JSON round trip', () {
      final server = ServerConfig(
        id: 's1',
        name: 'LM Studio',
        baseUrl: 'http://192.168.0.183:1234',
      );
      expect(server.hasMcp, isFalse);
      expect(server.mcpIntegrationId, ServerConfig.defaultMcpIntegrationId);

      final json = server.toJson();
      expect(json.containsKey('mcpEnabled'), isFalse);

      final restored = ServerConfig.fromJson({
        ...json,
        'mcpEnabled': true,
        'mcpIntegrationId': 'mcp/lm-computer',
      });
      expect(restored.mcpEnabled, isTrue);
      expect(restored.hasMcp, isTrue);
      expect(restored.mcpIntegrationId, 'mcp/lm-computer');
    });

    test('blank integration id disables MCP even when the switch is on', () {
      final server = ServerConfig(
        id: 's1',
        name: 'LM Studio',
        baseUrl: 'http://192.168.0.183:1234',
        mcpEnabled: true,
        mcpIntegrationId: '   ',
      );
      expect(server.hasMcp, isFalse);
    });
  });
}
