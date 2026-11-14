import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/api.dart';
import 'package:lm_chat/models.dart';

void main() {
  late HttpServer server;
  late ServerConfig config;
  String? receivedChatBody;
  String? receivedLoadBody;
  String? receivedUnloadBody;
  String? receivedBridgeLoadBody;
  String? receivedBridgeUnloadBody;
  String? receivedBridgeChatBody;
  String? receivedBridgeAuth;
  String? chatJobId;
  bool receivedBridgeCancel = false;
  bool rejectGpu = false;
  bool rejectStreamOptions = false;
  bool rejectOtherBadRequest = false;
  bool hangStream = false;
  bool hangMcpStream = false;
  bool trickleMcpEvent = false;
  String? receivedMcpBody;
  int chatRequestCount = 0;

  setUp(() async {
    receivedChatBody = null;
    receivedLoadBody = null;
    receivedUnloadBody = null;
    receivedBridgeLoadBody = null;
    receivedBridgeUnloadBody = null;
    receivedBridgeChatBody = null;
    receivedBridgeAuth = null;
    chatJobId = 'job-test';
    receivedBridgeCancel = false;
    rejectGpu = false;
    rejectStreamOptions = false;
    rejectOtherBadRequest = false;
    hangStream = false;
    hangMcpStream = false;
    trickleMcpEvent = false;
    receivedMcpBody = null;
    chatRequestCount = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    config = ServerConfig(
      id: 'test',
      name: 'local',
      baseUrl: 'http://127.0.0.1:${server.port}',
      bridgeUrl: 'http://127.0.0.1:${server.port}/bridge',
      bridgeToken: 'bridge-token',
    );

    server.listen((request) async {
      try {
        final path = request.uri.path;
        if (path == '/api/v1/models') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'models': [
                {
                  'key': 'qwen3-8b',
                  'display_name': 'Qwen3 8B',
                  'type': 'llm',
                  'max_context_length': 32768,
                  'size_bytes': 5100000000,
                  'params_string': '8B',
                  'quantization': {'name': 'Q4_K_M'},
                  'capabilities': {'vision': false},
                  'loaded_instances': [],
                },
                {
                  'key': 'llama-3.1-8b',
                  'display_name': 'Llama 3.1 8B',
                  'type': 'llm',
                  'max_context_length': 131072,
                  'loaded_instances': [
                    {
                      'id': 'inst-1',
                      'config': {'context_length': 8192},
                    },
                  ],
                },
                {
                  'key': 'embed-model',
                  'display_name': 'Embedding',
                  'type': 'embedding',
                  'loaded_instances': [],
                },
              ],
            }),
          );
          await request.response.close();
          return;
        }
        if (path == '/api/v1/models/load') {
          final body = await utf8.decodeStream(request);
          receivedLoadBody = body;
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          final gpu = decoded['gpu'];
          if (rejectGpu && gpu != null) {
            request.response.statusCode = 400;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              '{"error":{"message":"Unknown field: gpu"}}',
            );
            await request.response.close();
            return;
          }
          request.response.headers.contentType = ContentType.json;
          if (decoded['echo_load_config'] == true) {
            request.response.write(
              jsonEncode({
                'status': 'loaded',
                'load_config': {
                  if (decoded['context_length'] != null)
                    'context_length': decoded['context_length'],
                  'gpu': ?gpu,
                },
              }),
            );
          } else {
            request.response.write('{"status":"loaded"}');
          }
          await request.response.close();
          return;
        }
        if (path == '/api/v1/models/unload') {
          receivedUnloadBody = await utf8.decodeStream(request);
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"status":"unloaded"}');
          await request.response.close();
          return;
        }
        if (path == '/bridge/health') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            '{"ok":true,"lms":"CLI commit: abc123",'
            '"api":2,"features":["chat","estimate"]}',
          );
          await request.response.close();
          return;
        }
        if (path == '/bridge/load' || path == '/bridge/estimate') {
          receivedBridgeAuth = request.headers.value('Authorization');
          final body = await utf8.decodeStream(request);
          if (path == '/bridge/load') {
            receivedBridgeLoadBody = body;
          }
          if (receivedBridgeAuth != 'Bearer bridge-token') {
            request.response.statusCode = 401;
            request.response.headers.contentType = ContentType.json;
            request.response.write('{"ok":false,"error":"unauthorized"}');
            await request.response.close();
            return;
          }
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            path == '/bridge/load'
                ? '{"ok":true,"output":"Model loaded"}'
                : '{"ok":true,"output":"Estimated GPU Memory: 6.20 GB\\n'
                      'Estimated Total Memory: 6.20 GB"}',
          );
          await request.response.close();
          return;
        }
        if (path == '/bridge/unload') {
          receivedBridgeAuth = request.headers.value('Authorization');
          receivedBridgeUnloadBody = await utf8.decodeStream(request);
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"ok":true,"output":"Unloaded"}');
          await request.response.close();
          return;
        }
        if (path == '/bridge/chat' && request.method == 'POST') {
          receivedBridgeAuth = request.headers.value('Authorization');
          receivedBridgeChatBody = await utf8.decodeStream(request);
          final decoded =
              jsonDecode(receivedBridgeChatBody!) as Map<String, dynamic>;
          chatJobId = decoded['job']?.toString() ?? 'job-test';
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'ok': true, 'job': chatJobId}));
          await request.response.close();
          return;
        }
        if (path == '/bridge/chat/$chatJobId/cancel') {
          receivedBridgeCancel = true;
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"ok":true}');
          await request.response.close();
          return;
        }
        if (path == '/bridge/chat/$chatJobId' && request.method == 'GET') {
          final since =
              int.tryParse(request.uri.queryParameters['since'] ?? '') ?? 0;
          final events = switch (since) {
            <= 0 => [
              {'seq': 1, 'content': 'При', 'reasoning': ''},
            ],
            1 => [
              {'seq': 2, 'content': 'вет', 'reasoning': 'думаю'},
            ],
            _ => <Map<String, dynamic>>[],
          };
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'ok': true,
              'events': events,
              'next': since >= 2 ? 2 : since + 1,
              'done': since >= 1,
              'error': null,
              'usage': since >= 1
                  ? {
                      'prompt_tokens': 10,
                      'completion_tokens': 2,
                      'total_tokens': 12,
                    }
                  : null,
              'elapsed_ms': since >= 1 ? 1500 : null,
            }),
          );
          await request.response.close();
          return;
        }
        if (path == '/api/v1/chat' && request.method == 'POST') {
          receivedMcpBody = await utf8.decodeStream(request);
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
            charset: 'utf-8',
          );
          request.response.bufferOutput = false;
          void send(Map<String, dynamic> payload) {
            request.response.write('data: ${jsonEncode(payload)}\n\n');
          }

          if (hangMcpStream) {
            send({'type': 'chat.start'});
            await request.response.flush();
            // Go quiet after the first event: the client must notice.
            await Future<void>.delayed(const Duration(seconds: 3));
            await request.response.close();
            return;
          }
          if (trickleMcpEvent) {
            final line =
                'data: ${jsonEncode({'type': 'message.delta', 'content': 'Готово'})}\n\n';
            // One event arrives in many small pieces, each faster than the
            // idle timeout, but the whole line takes longer than it.
            for (var start = 0; start < line.length; start += 5) {
              final end = start + 5 < line.length ? start + 5 : line.length;
              request.response.write(line.substring(start, end));
              await request.response.flush();
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            send({'type': 'chat.end'});
            await request.response.flush();
            await request.response.close();
            return;
          }

          send({'type': 'chat.start'});
          send({'type': 'tool_call.start'});
          send({'type': 'tool_call.name', 'tool_name': 'fs_mkdir'});
          send({
            'type': 'tool_call.arguments',
            'tool': 'fs_mkdir',
            'arguments': {'path': 'lmchat-test'},
          });
          send({
            'type': 'tool_call.success',
            'tool': 'fs_mkdir',
            'arguments': {'path': 'lmchat-test'},
            'output': '[{"type":"text","text":"created"}]',
          });
          send({'type': 'message.delta', 'content': 'Готово'});
          send({
            'type': 'chat.end',
            'result': {
              'stats': {'input_tokens': 10, 'total_output_tokens': 5},
            },
          });
          await request.response.flush();
          await request.response.close();
          return;
        }
        if (path == '/v1/models' || path == '/compat/v1/models') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            '{"object":"list","data":[{"id":"qwen3-8b"},{"id":"llama-3.1-8b"}]}',
          );
          await request.response.close();
          return;
        }
        if (path == '/v1/chat/completions') {
          receivedChatBody = await utf8.decodeStream(request);
          chatRequestCount++;
          final decoded = jsonDecode(receivedChatBody!) as Map<String, dynamic>;
          if (rejectOtherBadRequest) {
            request.response.statusCode = 400;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              '{"error":{"message":"max_tokens must be positive"}}',
            );
            await request.response.close();
            return;
          }
          if (rejectStreamOptions && decoded.containsKey('stream_options')) {
            request.response.statusCode = 400;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              '{"error":{"message":"unknown field stream_options"}}',
            );
            await request.response.close();
            return;
          }
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
            charset: 'utf-8',
          );
          request.response.bufferOutput = false;
          request.response.write(
            'data: {"choices":[{"delta":{"content":"При"}}]}\n\n',
          );
          if (hangStream) {
            await request.response.flush();
            // Keep the connection open without sending more events: the
            // client must notice the idle timeout.
            await Future<void>.delayed(const Duration(seconds: 3));
            await request.response.close();
            return;
          }
          request.response.write(
            'data: {"choices":[{"delta":{"content":"вет"}}]}\n\n',
          );
          request.response.write(
            'data: {"choices":[{"delta":{"reasoning_content":"думаю"}}]}\n\n',
          );
          request.response.write(
            'data: {"choices":[],"usage":{"prompt_tokens":12,'
            '"completion_tokens":3,"total_tokens":15}}\n\n',
          );
          request.response.write('data: [DONE]\n\n');
          await request.response.flush();
          await request.response.close();
          return;
        }
        request.response.statusCode = 404;
        await request.response.close();
      } catch (error, stack) {
        // Make failures visible instead of silently dropping the connection.
        stderr.writeln('test server error: $error\n$stack');
        try {
          request.response.statusCode = 500;
          await request.response.close();
        } catch (_) {}
      }
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('fetchModelsInfo reads native metadata and loaded state', () async {
    final client = LmClient();
    addTearDown(client.close);
    final models = await client.fetchModelsInfo(config);

    expect(models, hasLength(3));
    // Loaded models are sorted first.
    expect(models.first.key, 'llama-3.1-8b');
    expect(models.first.isLoaded, isTrue);
    expect(models.first.instance!.contextLength, 8192);

    final qwen = models.firstWhere((m) => m.key == 'qwen3-8b');
    expect(qwen.displayName, 'Qwen3 8B');
    expect(qwen.maxContextLength, 32768);
    expect(qwen.parameters, '8B');
    expect(qwen.quantization, 'Q4_K_M');
    expect(qwen.isLoaded, isFalse);
    expect(qwen.isLlm, isTrue);

    final embedding = models.firstWhere((m) => m.key == 'embed-model');
    expect(embedding.isLlm, isFalse);
  });

  test('fetchModelsInfo falls back to the OpenAI-compatible list', () async {
    final client = LmClient();
    addTearDown(client.close);
    final compatConfig = ServerConfig(
      id: 'compat',
      name: 'old lm studio',
      baseUrl: 'http://127.0.0.1:${server.port}/compat',
    );
    final models = await client.fetchModelsInfo(compatConfig);

    expect(models.map((m) => m.key), containsAll(['qwen3-8b', 'llama-3.1-8b']));
    expect(models.every((m) => !m.isLoaded), isTrue);
    expect(models.first.maxContextLength, isNull);
  });

  test('loadModel sends the launch configuration', () async {
    final client = LmClient();
    addTearDown(client.close);
    await client.loadModel(
      config,
      'qwen3-8b',
      contextLength: 8192,
      evalBatchSize: 512,
      flashAttention: true,
      offloadKvCache: false,
    );

    final body = jsonDecode(receivedLoadBody!) as Map<String, dynamic>;
    expect(body['model'], 'qwen3-8b');
    expect(body['context_length'], 8192);
    expect(body['eval_batch_size'], 512);
    expect(body['flash_attention'], true);
    expect(body['offload_kv_cache_to_gpu'], false);
  });

  test('loadModel omits automatic values', () async {
    final client = LmClient();
    addTearDown(client.close);
    final result = await client.loadModel(config, 'qwen3-8b');

    final body = jsonDecode(receivedLoadBody!) as Map<String, dynamic>;
    expect(body.keys, ['model']);
    expect(result.gpuConfirmed, isNull);
    expect(result.warning, isNull);
  });

  test('loadModel sends the GPU ratio and confirms it', () async {
    final client = LmClient();
    addTearDown(client.close);
    final result = await client.loadModel(
      config,
      'qwen3-8b',
      contextLength: 8192,
      gpuRatio: 0.75,
    );

    final body = jsonDecode(receivedLoadBody!) as Map<String, dynamic>;
    expect(body['gpu'], {'ratio': 0.75});
    expect(body['echo_load_config'], true);
    expect(result.gpuConfirmed, isTrue);
    expect(result.warning, isNull);
    expect(result.command, isNull);
  });

  test('loadModel retries without GPU when the server rejects it', () async {
    rejectGpu = true;
    final client = LmClient();
    addTearDown(client.close);
    final result = await client.loadModel(
      config,
      'qwen3-8b',
      contextLength: 8192,
      gpuRatio: 0.5,
    );

    // The last request is the retry without the unsupported field.
    final body = jsonDecode(receivedLoadBody!) as Map<String, dynamic>;
    expect(body.containsKey('gpu'), isFalse);
    expect(body['context_length'], 8192);
    expect(result.gpuConfirmed, isFalse);
    expect(result.warning, contains('REST API'));
    expect(result.command, contains("lms load 'qwen3-8b' --gpu 0.50"));
  });

  test('unloadModel sends the instance id', () async {
    final client = LmClient();
    addTearDown(client.close);
    await client.unloadModel(config, 'inst-1');

    final body = jsonDecode(receivedUnloadBody!) as Map<String, dynamic>;
    expect(body['instance_id'], 'inst-1');
  });

  test('streamChat parses SSE chunks, usage and sends ttl', () async {
    final client = LmClient();
    addTearDown(client.close);
    final chunks = await client
        .streamChat(
          server: config,
          model: 'qwen3-8b',
          messages: [
            {'role': 'user', 'content': 'привет'},
          ],
          temperature: 0.7,
          topP: 0.9,
          maxTokens: -1,
          ttlSeconds: 900,
        )
        .toList();

    final body = jsonDecode(receivedChatBody!) as Map<String, dynamic>;
    expect(body['stream'], true);
    expect(body['ttl'], 900);
    expect(body['max_tokens'], isNull);
    expect(body['stream_options'], {'include_usage': true});
    expect(chunks.map((c) => c.content).join(), 'Привет');
    expect(chunks.map((c) => c.reasoning).join(), 'думаю');

    final usage = chunks.singleWhere((c) => c.usage != null).usage!;
    expect(usage.promptTokens, 12);
    expect(usage.completionTokens, 3);
    expect(usage.totalTokens, 15);
  });

  test('streamChat sends image content parts unchanged', () async {
    final client = LmClient();
    addTearDown(client.close);
    final messages = <Map<String, dynamic>>[
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'что на картинке?'},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,AQID'},
          },
        ],
      },
    ];

    await client
        .streamChat(
          server: config,
          model: 'qwen3-8b',
          messages: messages,
          temperature: 0.7,
          topP: 0.9,
          maxTokens: -1,
        )
        .toList();

    final body = jsonDecode(receivedChatBody!) as Map<String, dynamic>;
    final sent = (body['messages'] as List).single as Map<String, dynamic>;
    final parts = sent['content'] as List;
    expect(parts, hasLength(2));
    expect(parts[1]['type'], 'image_url');
  });

  test('streamChat sends top_k and repeat_penalty when set', () async {
    final client = LmClient();
    addTearDown(client.close);

    await client
        .streamChat(
          server: config,
          model: 'qwen3-8b',
          messages: [
            {'role': 'user', 'content': 'hi'},
          ],
          temperature: 0.7,
          topP: 0.95,
          topK: 64,
          repeatPenalty: 1.1,
          maxTokens: -1,
        )
        .toList();

    final body = jsonDecode(receivedChatBody!) as Map<String, dynamic>;
    expect(body['top_k'], 64);
    expect(body['repeat_penalty'], 1.1);
  });

  test('streamChat omits automatic top_k and repeat_penalty', () async {
    final client = LmClient();
    addTearDown(client.close);

    await client
        .streamChat(
          server: config,
          model: 'qwen3-8b',
          messages: [
            {'role': 'user', 'content': 'hi'},
          ],
          temperature: 0.7,
          topP: 0.95,
          maxTokens: -1,
        )
        .toList();

    final body = jsonDecode(receivedChatBody!) as Map<String, dynamic>;
    expect(body.containsKey('top_k'), isFalse);
    expect(body.containsKey('repeat_penalty'), isFalse);
  });

  test('streamChat sends a JSON schema response format', () async {
    final client = LmClient();
    addTearDown(client.close);
    const format = ResponseFormat(
      mode: ResponseFormatMode.jsonSchema,
      schema:
          '{"type":"object","properties":{"answer":{"type":"string"}},'
          '"required":["answer"]}',
    );

    await client
        .streamChat(
          server: config,
          model: 'qwen3-8b',
          messages: [
            {'role': 'user', 'content': 'ответь JSON'},
          ],
          temperature: 0.7,
          topP: 0.9,
          maxTokens: -1,
          format: format,
        )
        .toList();

    final body = jsonDecode(receivedChatBody!) as Map<String, dynamic>;
    final responseFormat = body['response_format'] as Map<String, dynamic>;
    expect(responseFormat['type'], 'json_schema');
    final schema = responseFormat['json_schema'] as Map<String, dynamic>;
    expect(schema['schema'], {
      'type': 'object',
      'properties': {
        'answer': {'type': 'string'},
      },
      'required': ['answer'],
    });
  });

  test('streamChat sends a GBNF grammar', () async {
    final client = LmClient();
    addTearDown(client.close);

    await client
        .streamChat(
          server: config,
          model: 'qwen3-8b',
          messages: [
            {'role': 'user', 'content': 'да или нет'},
          ],
          temperature: 0.7,
          topP: 0.9,
          maxTokens: -1,
          format: const ResponseFormat(
            mode: ResponseFormatMode.grammar,
            grammar: 'root ::= "да" | "нет"',
          ),
        )
        .toList();

    final body = jsonDecode(receivedChatBody!) as Map<String, dynamic>;
    expect(body['grammar'], 'root ::= "да" | "нет"');
    expect(body.containsKey('response_format'), isFalse);
  });

  test('bridge chat forwards the response format', () async {
    final client = LmClient();
    addTearDown(client.close);
    await client
        .streamChatViaBridge(
          server: config,
          model: 'qwen3-8b',
          messages: [
            {'role': 'user', 'content': 'ответь JSON'},
          ],
          temperature: 0.7,
          topP: 0.9,
          maxTokens: -1,
          format: const ResponseFormat(mode: ResponseFormatMode.json),
        )
        .toList();

    final body = jsonDecode(receivedBridgeChatBody!) as Map<String, dynamic>;
    final responseFormat = body['response_format'] as Map<String, dynamic>;
    expect(responseFormat['type'], 'json_schema');
    expect(responseFormat['json_schema'], isA<Map<String, dynamic>>());
  });

  test('streamChat retries without stream_options when rejected', () async {
    rejectStreamOptions = true;
    final client = LmClient();
    addTearDown(client.close);
    final chunks = await client
        .streamChat(
          server: config,
          model: 'qwen3-8b',
          messages: [
            {'role': 'user', 'content': 'привет'},
          ],
          temperature: 0.7,
          topP: 0.9,
          maxTokens: -1,
        )
        .toList();

    expect(chatRequestCount, 2);
    expect(chunks.map((c) => c.content).join(), 'Привет');
    final body = jsonDecode(receivedChatBody!) as Map<String, dynamic>;
    expect(body.containsKey('stream_options'), isFalse);
  });

  test('streamChat does not retry unrelated 400 errors', () async {
    rejectOtherBadRequest = true;
    final client = LmClient();
    addTearDown(client.close);

    await expectLater(
      client
          .streamChat(
            server: config,
            model: 'qwen3-8b',
            messages: [
              {'role': 'user', 'content': 'привет'},
            ],
            temperature: 0.7,
            topP: 0.9,
            maxTokens: -1,
          )
          .toList(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('max_tokens'),
        ),
      ),
    );
    expect(chatRequestCount, 1);
  });

  test('streamChat times out when the server stops sending tokens', () async {
    hangStream = true;
    final client = LmClient(idleTimeout: const Duration(milliseconds: 150));
    addTearDown(client.close);

    await expectLater(
      client
          .streamChat(
            server: config,
            model: 'qwen3-8b',
            messages: [
              {'role': 'user', 'content': 'привет'},
            ],
            temperature: 0.7,
            topP: 0.9,
            maxTokens: -1,
          )
          .toList(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('не присылал данных'),
        ),
      ),
    );
  });

  test('streamChatWithMcp forwards tool events and usage', () async {
    final client = LmClient();
    addTearDown(client.close);

    final chunks = await client
        .streamChatWithMcp(
          server: config,
          model: 'qwen3-8b',
          messages: [
            {'role': 'user', 'content': 'создай папку'},
          ],
          integrationId: 'mcp/lm-computer',
          temperature: 0,
          topP: 1,
          maxTokens: 0,
        )
        .toList();

    final body = jsonDecode(receivedMcpBody!) as Map<String, dynamic>;
    expect(body['integrations'], [
      {'type': 'plugin', 'id': 'mcp/lm-computer'},
    ]);
    final calls = chunks
        .map((chunk) => chunk.toolCall)
        .whereType<ToolCallEvent>()
        .toList();
    expect(calls.map((call) => call.kind), [
      ToolCallEventKind.start,
      ToolCallEventKind.name,
      ToolCallEventKind.arguments,
      ToolCallEventKind.success,
    ]);
    expect(calls.last.name, 'fs_mkdir');
    expect(calls.last.output, contains('created'));
    expect(chunks.map((chunk) => chunk.content).join(), 'Готово');
    expect(chunks.last.usage?.totalTokens, 15);
  });

  test('streamChatWithMcp times out when the server goes quiet', () async {
    hangMcpStream = true;
    final client = LmClient(idleTimeout: const Duration(milliseconds: 200));
    addTearDown(client.close);

    await expectLater(
      client
          .streamChatWithMcp(
            server: config,
            model: 'qwen3-8b',
            messages: [
              {'role': 'user', 'content': 'привет'},
            ],
            integrationId: 'mcp/lm-computer',
            temperature: 0,
            topP: 1,
            maxTokens: 0,
          )
          .toList(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('не присылал событий'),
        ),
      ),
    );
  });

  test('a slowly arriving event does not trip the idle timeout', () async {
    trickleMcpEvent = true;
    final client = LmClient(idleTimeout: const Duration(milliseconds: 400));
    addTearDown(client.close);

    final chunks = await client
        .streamChatWithMcp(
          server: config,
          model: 'qwen3-8b',
          messages: [
            {'role': 'user', 'content': 'привет'},
          ],
          integrationId: 'mcp/lm-computer',
          temperature: 0,
          topP: 1,
          maxTokens: 0,
        )
        .toList();

    expect(chunks.map((chunk) => chunk.content).join(), 'Готово');
  });

  test('http errors are reported with a readable message', () async {
    final client = LmClient();
    addTearDown(client.close);
    final badConfig = ServerConfig(
      id: 'bad',
      name: 'bad',
      baseUrl: 'http://127.0.0.1:${server.port}/nope',
    );
    expect(
      () => client.fetchModelsInfo(badConfig),
      throwsA(isA<ApiException>()),
    );
  });

  test('network exceptions are explained by type', () {
    expect(
      friendlyNetworkError(SocketException('connection refused')),
      contains('Не удалось подключиться'),
    );
    expect(
      friendlyNetworkError(TimeoutException('slow')),
      contains('не ответил вовремя'),
    );
    expect(
      friendlyNetworkError(const HandshakeException('bad certificate')),
      contains('TLS'),
    );
  });

  // ------------------------------------------------------------------ bridge

  test('bridgeHealth reports the CLI version', () async {
    final client = LmClient();
    addTearDown(client.close);
    final health = await client.bridgeHealth(config);

    expect(health.ok, isTrue);
    expect(health.version, contains('abc123'));
    expect(health.apiVersion, 2);
    expect(health.features, containsAll(['chat', 'estimate']));
    expect(health.supportsChat, isTrue);
  });

  test('bridgeLoad maps 100% to --gpu max and sends limits', () async {
    final client = LmClient();
    addTearDown(client.close);
    final result = await client.bridgeLoad(
      config,
      'qwen3-8b',
      contextLength: 8192,
      ttlSeconds: 3600,
      gpuRatio: 1.0,
    );

    final body = jsonDecode(receivedBridgeLoadBody!) as Map<String, dynamic>;
    expect(body['model'], 'qwen3-8b');
    expect(body['gpu'], 'max');
    expect(body['context_length'], 8192);
    expect(body['ttl'], 3600);
    expect(receivedBridgeAuth, 'Bearer bridge-token');
    expect(result.viaBridge, isTrue);
    expect(result.gpuConfirmed, isTrue);
  });

  test('bridgeLoad maps CPU to off and keeps a partial ratio', () async {
    final client = LmClient();
    addTearDown(client.close);

    await client.bridgeLoad(config, 'qwen3-8b', gpuRatio: 0.0);
    expect(
      (jsonDecode(receivedBridgeLoadBody!) as Map<String, dynamic>)['gpu'],
      'off',
    );

    await client.bridgeLoad(config, 'qwen3-8b', gpuRatio: 0.5);
    expect(
      (jsonDecode(receivedBridgeLoadBody!) as Map<String, dynamic>)['gpu'],
      '0.50',
    );
  });

  test('bridgeLoad omits the GPU flag when automatic', () async {
    final client = LmClient();
    addTearDown(client.close);
    final result = await client.bridgeLoad(config, 'qwen3-8b');

    final body = jsonDecode(receivedBridgeLoadBody!) as Map<String, dynamic>;
    expect(body.containsKey('gpu'), isFalse);
    expect(result.gpuConfirmed, isNull);
  });

  test('bridgeUnload sends the model key', () async {
    final client = LmClient();
    addTearDown(client.close);
    await client.bridgeUnload(config, model: 'qwen3-8b');

    final body = jsonDecode(receivedBridgeUnloadBody!) as Map<String, dynamic>;
    expect(body['model'], 'qwen3-8b');
    expect(body.containsKey('all'), isFalse);
  });

  test('bridgeEstimate returns raw CLI output', () async {
    final client = LmClient();
    addTearDown(client.close);
    final result = await client.bridgeEstimate(
      config,
      'qwen3-8b',
      contextLength: 8192,
      gpuRatio: 1.0,
    );

    expect(result.ok, isTrue);
    expect(result.output, contains('Estimated GPU Memory'));
  });

  test('bridge errors are readable', () async {
    final client = LmClient();
    addTearDown(client.close);
    final wrongToken = ServerConfig(
      id: 'test',
      name: 'local',
      baseUrl: config.baseUrl,
      bridgeUrl: config.bridgeUrl,
      bridgeToken: 'wrong',
    );

    expect(
      () => client.bridgeLoad(wrongToken, 'qwen3-8b'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('токен'),
        ),
      ),
    );
  });

  test('bridge chat streams events and reports the job', () async {
    final client = LmClient();
    addTearDown(client.close);
    String? job;
    var nextSeq = 0;
    final chunks = await client
        .streamChatViaBridge(
          server: config,
          model: 'qwen3-8b',
          messages: [
            {'role': 'user', 'content': 'привет'},
          ],
          temperature: 0.7,
          topP: 0.9,
          maxTokens: -1,
          ttlSeconds: 900,
          onJob: (value) => job = value,
          onSeq: (value) => nextSeq = value,
        )
        .toList();

    final body = jsonDecode(receivedBridgeChatBody!) as Map<String, dynamic>;
    expect(body['model'], 'qwen3-8b');
    expect(body['stream'], true);
    expect(body['ttl'], 900);
    expect(body['job'], job);
    expect(body['stream_options'], {'include_usage': true});
    expect(receivedBridgeAuth, 'Bearer bridge-token');
    expect(job, isNotEmpty);
    expect(chunks.map((c) => c.content).join(), 'Привет');
    expect(chunks.map((c) => c.reasoning).join(), 'думаю');
    expect(nextSeq, 2);

    final usage = chunks.singleWhere((c) => c.usage != null).usage!;
    expect(usage.promptTokens, 10);
    expect(usage.completionTokens, 2);
    expect(usage.totalTokens, 12);
    expect(chunks.singleWhere((c) => c.elapsedMs != null).elapsedMs, 1500);
  });

  test('bridge job can be resumed from a sequence number', () async {
    final client = LmClient();
    addTearDown(client.close);
    final chunks = await client
        .streamBridgeJob(config, 'job-test', since: 1)
        .toList();

    final content = chunks.singleWhere((c) => c.content.isNotEmpty);
    expect(content.content, 'вет');
    expect(content.reasoning, 'думаю');
    final usage = chunks.singleWhere((c) => c.usage != null);
    expect(usage.usage!.totalTokens, 12);
    expect(usage.elapsedMs, 1500);
  });

  test('missing /chat endpoint is reported as unsupported', () async {
    final client = LmClient();
    addTearDown(client.close);
    final oldBridge = ServerConfig(
      id: 'old',
      name: 'old',
      baseUrl: config.baseUrl,
      bridgeUrl: 'http://127.0.0.1:${server.port}/oldbridge',
    );

    expect(
      () => client
          .streamChatViaBridge(
            server: oldBridge,
            model: 'qwen3-8b',
            messages: [
              {'role': 'user', 'content': 'привет'},
            ],
            temperature: 0.7,
            topP: 0.9,
            maxTokens: -1,
          )
          .toList(),
      throwsA(isA<BridgeChatUnsupported>()),
    );
  });

  test('abort cancels the running bridge job', () async {
    final client = LmClient();
    addTearDown(client.close);
    final iterator = StreamIterator(
      client.streamChatViaBridge(
        server: config,
        model: 'qwen3-8b',
        messages: [
          {'role': 'user', 'content': 'привет'},
        ],
        temperature: 0.7,
        topP: 0.9,
        maxTokens: -1,
      ),
    );

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.content, 'При');

    await client.abort();
    expect(receivedBridgeCancel, isTrue);

    await iterator.cancel();
  });
}
