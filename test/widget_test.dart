import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/app_state.dart';
import 'package:lm_chat/models.dart';

void main() {
  test('server address is normalised', () {
    expect(
      ServerConfig(
        id: '1',
        name: 'PC',
        baseUrl: '192.168.1.5:1234',
      ).normalizedBase,
      'http://192.168.1.5:1234',
    );
    expect(
      ServerConfig(
        id: '1',
        name: 'PC',
        baseUrl: 'http://192.168.1.5:1234/v1/',
      ).normalizedBase,
      'http://192.168.1.5:1234',
    );
  });

  test('bridge settings survive json round trip', () {
    final server = ServerConfig(
      id: '1',
      name: 'PC',
      baseUrl: '192.168.1.5:1234',
      bridgeUrl: '192.168.1.5:1235/',
      bridgeToken: 'secret',
    );
    expect(server.normalizedBridge, 'http://192.168.1.5:1235');
    expect(server.hasBridge, isTrue);
    expect(server.bridgeUri('load').toString(), 'http://192.168.1.5:1235/load');

    expect(server.toJson().containsKey('bridgeToken'), isFalse);
    final restored = ServerConfig.fromJson(server.toJson(includeSecrets: true));
    expect(restored.bridgeUrl, '192.168.1.5:1235/');
    expect(restored.bridgeToken, 'secret');
    expect(restored.hasBridge, isTrue);
    expect(restored.chatViaBridge, isTrue);
  });

  test('bridge chat can be disabled per server', () {
    final server = ServerConfig(
      id: '1',
      name: 'PC',
      baseUrl: '192.168.1.5:1234',
      bridgeUrl: '192.168.1.5:1235',
      chatViaBridge: false,
    );
    expect(server.toJson()['chatViaBridge'], isFalse);
    expect(ServerConfig.fromJson(server.toJson()).chatViaBridge, isFalse);
  });

  test('servers without a bridge stay bridge-free', () {
    final server = ServerConfig(
      id: '1',
      name: 'PC',
      baseUrl: '192.168.1.5:1234',
    );
    expect(server.hasBridge, isFalse);
    final restored = ServerConfig.fromJson(server.toJson());
    expect(restored.hasBridge, isFalse);
    expect(restored.bridgeToken, isEmpty);
  });

  test('chat survives json round trip', () {
    final chat = ChatSession(
      id: 'chat',
      serverId: 'server',
      model: 'test-model',
      messages: [ChatMessage(id: 'm1', role: 'user', content: 'привет')],
      systemPrompt: 'будь краток',
    );
    final restored = ChatSession.fromJson(chat.toJson());
    expect(restored.model, 'test-model');
    expect(restored.messages.single.content, 'привет');
    expect(restored.systemPrompt, 'будь краток');
  });

  test('launch settings survive json round trip', () {
    final chat = ChatSession(
      id: 'chat',
      serverId: 'server',
      model: 'test-model',
      launch: const LaunchSettings(
        contextLength: 16384,
        loadOnDemand: false,
        ttlSeconds: 3600,
        flashAttention: true,
        offloadKvCache: false,
        evalBatchSize: 512,
        gpuRatio: 0.75,
      ),
    );
    final restored = ChatSession.fromJson(chat.toJson()).launch;
    expect(restored.contextLength, 16384);
    expect(restored.loadOnDemand, isFalse);
    expect(restored.ttlSeconds, 3600);
    expect(restored.flashAttention, isTrue);
    expect(restored.offloadKvCache, isFalse);
    expect(restored.evalBatchSize, 512);
    expect(restored.gpuRatio, 0.75);
  });

  test('default launch enables Flash Attention, KV cache and batch 2048', () {
    final data = AppData();
    expect(data.defaultLaunch.flashAttention, isTrue);
    expect(data.defaultLaunch.offloadKvCache, isTrue);
    expect(data.defaultLaunch.evalBatchSize, 2048);

    // Old files with automatic values are upgraded to the new defaults.
    final old = AppData.fromJson({
      'schemaVersion': 7,
      'defaultLaunch': {'loadOnDemand': true},
    });
    expect(old.defaultLaunch.flashAttention, isTrue);
    expect(old.defaultLaunch.offloadKvCache, isTrue);
    expect(old.defaultLaunch.evalBatchSize, 2048);

    // Explicit user choices are preserved.
    final explicit = AppData.fromJson({
      'defaultLaunch': {
        'flashAttention': false,
        'offloadKvCache': false,
        'evalBatchSize': 512,
      },
    });
    expect(explicit.defaultLaunch.flashAttention, isFalse);
    expect(explicit.defaultLaunch.offloadKvCache, isFalse);
    expect(explicit.defaultLaunch.evalBatchSize, 512);
  });

  test('launch settings copyWith can reset nullable values', () {
    const source = LaunchSettings(
      contextLength: 8192,
      loadOnDemand: false,
      ttlSeconds: 3600,
      flashAttention: true,
      offloadKvCache: false,
      evalBatchSize: 512,
      gpuRatio: 0.5,
    );

    final changed = source.copyWith(
      contextLength: null,
      loadOnDemand: true,
      ttlSeconds: null,
      flashAttention: null,
      offloadKvCache: true,
      evalBatchSize: null,
      gpuRatio: null,
    );

    expect(changed.contextLength, isNull);
    expect(changed.loadOnDemand, isTrue);
    expect(changed.ttlSeconds, isNull);
    expect(changed.flashAttention, isNull);
    expect(changed.offloadKvCache, isTrue);
    expect(changed.evalBatchSize, isNull);
    expect(changed.gpuRatio, isNull);

    final untouched = source.copyWith(loadOnDemand: true);
    expect(untouched.contextLength, 8192);
    expect(untouched.ttlSeconds, 3600);
    expect(untouched.gpuRatio, 0.5);
  });

  test('automatic launch values are not persisted as zeros', () {
    final restored = LaunchSettings.fromJson(const LaunchSettings().toJson());
    expect(restored.contextLength, isNull);
    expect(restored.ttlSeconds, isNull);
    expect(restored.flashAttention, isNull);
    expect(restored.offloadKvCache, isNull);
    expect(restored.evalBatchSize, isNull);
    expect(restored.gpuRatio, isNull);
    expect(restored.loadOnDemand, isTrue);
  });

  test('pending bridge job survives a restart', () {
    final chat = ChatSession(
      id: 'chat',
      serverId: 'server',
      model: 'test-model',
      messages: [
        ChatMessage(
          id: 'a1',
          role: 'assistant',
          content: 'частичный',
          jobId: 'job-1',
          jobServerId: 'server',
          jobSeq: 7,
        ),
      ],
    );
    final restored = ChatSession.fromJson(chat.toJson()).messages.single;
    expect(restored.hasPendingJob, isTrue);
    expect(restored.jobId, 'job-1');
    expect(restored.jobServerId, 'server');
    expect(restored.jobSeq, 7);
    expect(restored.content, 'частичный');
  });

  test('answer notices survive a restart', () {
    final message = ChatMessage(
      id: 'a1',
      role: 'assistant',
      content: 'ответ',
      notice: 'Контекст не применился',
    );
    final restored = ChatSession.fromJson(
      ChatSession(id: 'chat', serverId: 'server', messages: [message]).toJson(),
    ).messages.single;

    expect(restored.notice, 'Контекст не применился');
    expect(restored.displayNotice, 'Контекст не применился');

    restored.versions.add(ChatMessageVersion(id: 'v1', content: 'старый'));
    restored.selectVersion(1);
    expect(restored.displayNotice, isNull);
  });

  test('theme and pinned chat survive json round trip', () {
    final chat = ChatSession(id: 'chat', serverId: 'server', pinned: true);
    final data = AppData(
      chats: [chat],
      themeMode: AppThemeMode.light,
      appLanguage: AppLanguage.en,
    );
    final restored = AppData.fromJson(data.toJson());

    expect(restored.themeMode, AppThemeMode.light);
    expect(restored.appLanguage, AppLanguage.en);
    expect(restored.chats.single.pinned, isTrue);
    expect(AppData.fromJson(const {}).themeMode, AppThemeMode.dark);
    expect(AppData.fromJson(const {}).appLanguage, AppLanguage.ru);
  });

  test('archiving hides a chat and moves the active selection', () {
    final state = AppState();
    final first = ChatSession(id: 'c1', serverId: 'server', title: 'first');
    final second = ChatSession(id: 'c2', serverId: 'server', title: 'second');
    state.data.chats.addAll([first, second]);
    state.activeChat = first;

    state.archiveChat(first);

    expect(first.archived, isTrue);
    expect(state.activeChats.map((c) => c.id), isNot(contains('c1')));
    expect(state.archivedChats.map((c) => c.id), contains('c1'));
    expect(state.activeChat?.id, 'c2');

    state.unarchiveChat(first);
    expect(state.activeChats.map((c) => c.id), contains('c1'));
  });

  test('offline state follows the active server', () {
    final state = AppState();
    state.data.servers.add(
      ServerConfig(id: 'server', name: 'PC', baseUrl: '127.0.0.1:1234'),
    );
    state.data.activeServerId = 'server';

    expect(state.isOffline, isFalse);
    state.setServerOnlineForTest('server', false);
    expect(state.isOffline, isTrue);
    state.setServerOnlineForTest('server', true);
    expect(state.isOffline, isFalse);
  });

  test('import merges chats and avoids id collisions', () {
    final state = AppState();
    state.data.servers.add(
      ServerConfig(id: 'server', name: 'PC', baseUrl: '127.0.0.1:1234'),
    );
    state.data.activeServerId = 'server';

    final exported = jsonEncode({
      'servers': [
        {'id': 'server', 'name': 'PC', 'baseUrl': '127.0.0.1:1234'},
      ],
      'chats': [
        {
          'id': 'chat-1',
          'title': 'Импортированный',
          'serverId': 'server',
          'messages': [
            {'id': 'm1', 'role': 'user', 'content': 'привет'},
          ],
        },
      ],
      'promptTemplates': [
        {'id': 't1', 'name': 'Мой', 'content': 'Отвечай кратко'},
      ],
    });

    final first = state.importHistoryJson(exported);
    expect(first.ok, isTrue);
    expect(first.chats, 1);
    expect(first.servers, 0);
    expect(first.templates, 1);
    expect(state.data.promptTemplates.single.name, 'Мой');
    expect(state.data.chats.single.title, 'Импортированный');

    final second = state.importHistoryJson(exported);
    expect(second.ok, isTrue);
    expect(state.data.chats, hasLength(2));
    expect(state.data.chats.map((c) => c.id).toSet(), hasLength(2));
    expect(state.data.servers, hasLength(1));
  });

  test('import preview lets the user select only some chats', () {
    final state = AppState();
    state.data.servers.add(
      ServerConfig(id: 'server', name: 'PC', baseUrl: '127.0.0.1:1234'),
    );
    state.data.activeServerId = 'server';

    final preview = state.parseHistoryJson(
      jsonEncode({
        'chats': [
          {
            'id': 'one',
            'title': 'Первый',
            'serverId': 'server',
            'messages': [],
          },
          {
            'id': 'two',
            'title': 'Второй',
            'serverId': 'server',
            'messages': [],
          },
        ],
      }),
    );

    expect(preview.ok, isTrue);
    expect(preview.chats, hasLength(2));

    final result = state.importPreview(preview, selectedChats: {1});
    expect(result.ok, isTrue);
    expect(state.data.chats.single.title, 'Второй');
  });

  test('whole history can be rendered as markdown', () {
    final state = AppState();
    state.data.chats.addAll([
      ChatSession(
        id: 'c1',
        serverId: 'server',
        title: 'Первый чат',
        messages: [ChatMessage(id: 'm1', role: 'user', content: 'привет')],
      ),
      ChatSession(
        id: 'c2',
        serverId: 'server',
        title: 'Архивный чат',
        archived: true,
        messages: [ChatMessage(id: 'm2', role: 'user', content: 'старое')],
      ),
    ]);

    final markdown = state.allChatsToMarkdown();
    expect(markdown, contains('# LM Chat — история'));
    expect(markdown, contains('Первый чат'));
    expect(markdown, contains('Архивный чат'));
    expect(markdown, contains('_Архив_'));
  });

  test('single chat import maps an unknown server to the active one', () {
    final state = AppState();
    state.data.servers.add(
      ServerConfig(id: 'server', name: 'PC', baseUrl: '127.0.0.1:1234'),
    );
    state.data.activeServerId = 'server';

    final result = state.importHistoryJson(
      jsonEncode({
        'id': 'single',
        'title': 'Один чат',
        'serverId': 'unknown',
        'messages': [
          {'id': 'm1', 'role': 'user', 'content': 'текст'},
        ],
      }),
    );

    expect(result.ok, isTrue);
    expect(state.data.chats.single.serverId, 'server');
  });

  test('HTTP is allowed only for local addresses', () {
    expect(
      ServerConfig(
        id: '1',
        name: 'PC',
        baseUrl: 'http://192.168.1.5:1234',
      ).securityError,
      isNull,
    );
    expect(
      ServerConfig(
        id: '1',
        name: 'PC',
        baseUrl: 'http://10.0.0.10:1234',
      ).securityError,
      isNull,
    );
    expect(
      ServerConfig(
        id: '1',
        name: 'PC',
        baseUrl: 'http://100.100.1.1:1234',
      ).securityError,
      isNull,
    );
    expect(
      ServerConfig(
        id: '1',
        name: 'PC',
        baseUrl: 'http://my-pc.local:1234',
      ).securityError,
      isNull,
    );
    expect(
      ServerConfig(
        id: '1',
        name: 'PC',
        baseUrl: 'http://8.8.8.8:1234',
      ).securityError,
      isNotNull,
    );
    expect(
      ServerConfig(
        id: '1',
        name: 'Cloud',
        baseUrl: 'https://example.com',
      ).securityError,
      isNull,
    );
  });

  test('prompt templates survive json and can be managed', () {
    final state = AppState();
    final template = PromptTemplate(
      id: 't1',
      name: 'Мой промпт',
      content: 'Отвечай по-русски',
    );

    state.addPromptTemplate(template);
    expect(state.allPromptTemplates.map((t) => t.id), contains('t1'));

    final restored = AppData.fromJson(state.data.toJson());
    expect(restored.promptTemplates.single.name, 'Мой промпт');

    final updated = PromptTemplate(
      id: 't1',
      name: 'Обновлённый',
      content: 'Отвечай кратко',
    );
    state.updatePromptTemplate(updated);
    expect(state.data.promptTemplates.single.name, 'Обновлённый');

    state.deletePromptTemplate('t1');
    expect(state.data.promptTemplates, isEmpty);

    expect(builtInPromptTemplates, isNotEmpty);
    expect(builtInPromptTemplates.every((t) => t.builtIn), isTrue);
    expect(builtInPromptTemplates.every((t) => t.content.isNotEmpty), isTrue);
  });

  test('image attachments survive json and keep their bytes', () {
    final attachment = ChatAttachment(
      id: 'img1',
      mimeType: 'image/png',
      data: base64Encode([1, 2, 3, 4]),
      name: 'pixel.png',
    );
    final message = ChatMessage(
      id: 'u1',
      role: 'user',
      content: 'что на картинке?',
      attachments: [attachment],
    );
    final restored = ChatMessage.fromJson(message.toJson());

    expect(restored.attachments, hasLength(1));
    expect(restored.attachments.single.mimeType, 'image/png');
    expect(restored.attachments.single.bytes, [1, 2, 3, 4]);
    expect(
      restored.attachments.single.dataUrl,
      startsWith('data:image/png;base64,'),
    );
  });

  test('first token time survives archiving and json', () {
    final message = ChatMessage(
      id: 'a1',
      role: 'assistant',
      content: 'ответ',
      firstTokenMs: 420,
      generationMs: 2000,
    );

    expect(message.displayFirstTokenMs, 420);
    final archived = message.archiveCurrent();
    expect(archived!.firstTokenMs, 420);
    expect(message.displayFirstTokenMs, isNull);

    final restored = ChatMessage.fromJson(
      ChatMessage(
        id: 'a2',
        role: 'assistant',
        content: 'ответ',
        firstTokenMs: 300,
      ).toJson(),
    );
    expect(restored.displayFirstTokenMs, 300);
  });

  test('editing a user message can drop the following answer', () {
    final state = AppState();
    final user = ChatMessage(id: 'u1', role: 'user', content: 'старый');
    final answer = ChatMessage(id: 'a1', role: 'assistant', content: 'ответ');
    final chat = ChatSession(
      id: 'chat',
      serverId: 'server',
      messages: [user, answer],
    );

    state.editUserMessage(chat, user, 'новый');
    expect(user.content, 'новый');
    expect(chat.messages, hasLength(2));

    state.editUserMessage(chat, user, 'ещё новее', dropFollowing: true);
    expect(chat.messages, hasLength(1));
    expect(chat.messages.single.content, 'ещё новее');
  });

  test('context warning detects a message that does not fit', () {
    final state = AppState();
    state.setModelsForTest('server', [
      const LmModelInfo(
        key: 'model',
        displayName: 'Model',
        maxContextLength: 100,
      ),
    ]);
    final chat = ChatSession(
      id: 'chat',
      serverId: 'server',
      model: 'model',
      launch: const LaunchSettings(contextLength: 100),
    );

    expect(state.exceedsContext(chat, 'коротко'), isFalse);
    expect(state.exceedsContext(chat, 'x' * 1000), isTrue);
  });

  test('chat can be exported as markdown and csv', () {
    final state = AppState();
    final chat = ChatSession(
      id: 'chat',
      title: 'Тестовый чат',
      serverId: 'server',
      model: 'model',
      messages: [
        ChatMessage(id: 'u1', role: 'user', content: 'привет'),
        ChatMessage(
          id: 'a1',
          role: 'assistant',
          content: 'здравствуйте',
          model: 'model',
          completionTokens: 10,
          totalTokens: 12,
          generationMs: 1000,
          firstTokenMs: 200,
        ),
      ],
    );

    final markdown = state.chatToMarkdown(chat);
    expect(markdown, contains('# Тестовый чат'));
    expect(markdown, contains('**Вы**'));
    expect(markdown, contains('здравствуйте'));
    expect(markdown, contains('первый токен'));

    final csv = state.chatStatsCsv(chat);
    expect(csv, contains('created_at'));
    expect(csv, contains('model'));
    expect(csv, contains('1/1'));
    expect(csv, contains('10.00'));
  });

  test('background generation defaults to on and can be turned off', () {
    expect(AppData().backgroundGeneration, isTrue);
    final data = AppData(backgroundGeneration: false);
    final restored = AppData.fromJson(data.toJson());
    expect(restored.backgroundGeneration, isFalse);
  });

  test('regeneration keeps the previous answer as a version', () {
    final message = ChatMessage(
      id: 'a1',
      role: 'assistant',
      content: 'первый ответ',
      reasoning: 'рассуждение',
      model: 'model-a',
    );

    final archived = message.archiveCurrent();
    expect(archived, isNotNull);
    expect(message.versionCount, 2);
    expect(message.content, isEmpty);
    expect(message.displayedVersionNumber, 2);

    message.content = 'второй ответ';
    expect(message.displayContent, 'второй ответ');

    message.selectVersion(1);
    expect(message.viewingLatest, isFalse);
    expect(message.displayContent, 'первый ответ');
    expect(message.displayReasoning, 'рассуждение');
    expect(message.displayModel, 'model-a');

    message.selectVersion(2);
    expect(message.viewingLatest, isTrue);
    expect(message.displayContent, 'второй ответ');
  });

  test('versions and the selected variant survive json round trip', () {
    final message = ChatMessage(
      id: 'a1',
      role: 'assistant',
      content: 'новый',
      model: 'model-b',
    );
    message.versions.add(
      ChatMessageVersion(
        id: 'v1',
        content: 'старый',
        reasoning: 'r',
        model: 'model-a',
      ),
    );
    message.selectVersion(1);

    final restored = ChatSession.fromJson(
      ChatSession(id: 'chat', serverId: 'server', messages: [message]).toJson(),
    ).messages.single;

    expect(restored.versionCount, 2);
    expect(restored.viewingLatest, isFalse);
    expect(restored.displayContent, 'старый');
    expect(restored.displayReasoning, 'r');
    expect(restored.displayModel, 'model-a');
    expect(restored.variantAt(2).content, 'новый');
  });

  test('old messages without versions still load', () {
    final message = ChatMessage.fromJson({
      'id': 'a1',
      'role': 'assistant',
      'content': 'старый формат',
      'createdAt': DateTime(2026, 1, 1).toIso8601String(),
    });
    expect(message.versionCount, 1);
    expect(message.displayedVersionNumber, 1);
    expect(message.viewingLatest, isTrue);
    expect(message.displayContent, 'старый формат');
  });

  test('failed regeneration restores the previous answer', () {
    final message = ChatMessage(
      id: 'a1',
      role: 'assistant',
      content: 'первый ответ',
    );
    message.archiveCurrent();
    message.error = 'таймаут';

    expect(message.hasVersions, isTrue);
    expect(message.restoreLatestArchived(), isTrue);
    expect(message.content, 'первый ответ');
    expect(message.error, isNull);
    expect(message.versionCount, 1);
    expect(message.viewingLatest, isTrue);
  });

  test('deleting a version keeps the selection on the same answer', () {
    final message = ChatMessage(
      id: 'a1',
      role: 'assistant',
      content: 'третий',
      versions: [
        ChatMessageVersion(id: 'v1', content: 'первый'),
        ChatMessageVersion(id: 'v2', content: 'второй'),
      ],
    );

    message.selectVersion(2);
    expect(message.displayContent, 'второй');

    message.deleteVersion(1);
    expect(message.versionCount, 2);
    expect(message.displayContent, 'второй');
    expect(message.viewingLatest, isFalse);
  });

  test('generation stats stay with the archived answer', () {
    final message = ChatMessage(
      id: 'a1',
      role: 'assistant',
      content: 'ответ',
      promptTokens: 100,
      completionTokens: 20,
      totalTokens: 120,
      generationMs: 2000,
    );

    message.archiveCurrent();
    expect(message.promptTokens, isNull);
    expect(message.completionTokens, isNull);
    expect(message.generationMs, isNull);

    final restored = ChatMessage.fromJson(message.toJson());
    final archived = restored.variantAt(1);
    expect(archived.promptTokens, 100);
    expect(archived.completionTokens, 20);
    expect(archived.totalTokens, 120);
    expect(archived.generationMs, 2000);

    restored.selectVersion(1);
    expect(restored.displayCompletionTokens, 20);
    expect(restored.displayTokensPerSecond, closeTo(10, 0.001));
  });

  test('context usage uses the loaded window and exact usage', () {
    final state = AppState();
    state.setModelsForTest('server', [
      LmModelInfo(
        key: 'model',
        displayName: 'Model',
        maxContextLength: 32768,
        loadedInstances: const [
          LoadedInstance(id: 'instance', contextLength: 8192),
        ],
      ),
    ]);
    final chat = ChatSession(
      id: 'chat',
      serverId: 'server',
      model: 'model',
      messages: [
        ChatMessage(id: 'u1', role: 'user', content: 'привет'),
        ChatMessage(
          id: 'a1',
          role: 'assistant',
          content: 'ответ',
          promptTokens: 100,
          completionTokens: 50,
          totalTokens: 150,
          generationMs: 1000,
        ),
      ],
    );

    final usage = state.contextUsage(chat);
    expect(usage, isNotNull);
    expect(usage!.limit, 8192);
    expect(usage.used, 150);
    expect(usage.remaining, 8042);
    expect(usage.estimated, isFalse);
  });

  test('context usage estimates missing tokens and new messages', () {
    final state = AppState();
    state.setModelsForTest('server', [
      const LmModelInfo(
        key: 'model',
        displayName: 'Model',
        maxContextLength: 4096,
      ),
    ]);
    final chat = ChatSession(
      id: 'chat',
      serverId: 'server',
      model: 'model',
      launch: const LaunchSettings(contextLength: 2048),
      messages: [
        ChatMessage(id: 'u1', role: 'user', content: 'x' * 350),
        ChatMessage(
          id: 'a1',
          role: 'assistant',
          content: 'ответ',
          promptTokens: 10,
          completionTokens: 5,
          totalTokens: 15,
          generationMs: 100,
        ),
        ChatMessage(id: 'u2', role: 'user', content: 'y' * 350),
      ],
    );

    final usage = state.contextUsage(chat)!;
    expect(usage.limit, 2048);
    expect(usage.used, greaterThan(15));
    expect(usage.estimated, isTrue);
  });

  test('context usage is unknown until model metadata is loaded', () {
    final state = AppState();
    final chat = ChatSession(id: 'chat', serverId: 'server', model: 'model');
    expect(state.contextUsage(chat), isNull);
  });

  test('token estimation ignores empty text', () {
    expect(estimateTokens(''), 0);
    expect(estimateTokens('   '), 0);
    expect(estimateTokens('a' * 35), 10);
  });

  test('editing an answer keeps the previous text as a version', () {
    final state = AppState();
    final message = ChatMessage(
      id: 'a1',
      role: 'assistant',
      content: 'старый ответ',
      model: 'model',
      promptTokens: 10,
      completionTokens: 5,
      totalTokens: 15,
      generationMs: 1000,
    );
    final chat = ChatSession(
      id: 'chat',
      serverId: 'server',
      model: 'model',
      messages: [message],
    );

    state.editMessage(chat, message, 'новый текст');

    expect(message.content, 'новый текст');
    expect(message.displayContent, 'новый текст');
    expect(message.versionCount, 2);
    expect(message.viewingLatest, isTrue);
    expect(message.editedAt, isNotNull);
    expect(message.completionTokens, isNull);
    expect(message.generationMs, isNull);

    message.selectVersion(1);
    expect(message.displayContent, 'старый ответ');
    expect(message.displayCompletionTokens, 5);
    expect(message.displayEditedAt, isNull);
  });

  test('editing an archived variant makes the edited text current', () {
    final state = AppState();
    final message = ChatMessage(
      id: 'a1',
      role: 'assistant',
      content: 'новый ответ',
      versions: [ChatMessageVersion(id: 'v1', content: 'старый ответ')],
    );
    final chat = ChatSession(
      id: 'chat',
      serverId: 'server',
      messages: [message],
    );
    message.selectVersion(1);

    state.editMessage(chat, message, 'исправленный старый');

    expect(message.displayContent, 'исправленный старый');
    expect(message.viewingLatest, isTrue);
    expect(message.versionCount, 3);
    expect(message.variantAt(1).content, 'старый ответ');
    expect(message.variantAt(2).content, 'новый ответ');
  });

  test('empty edits are ignored', () {
    final state = AppState();
    final message = ChatMessage(id: 'a1', role: 'assistant', content: 'ответ');
    final chat = ChatSession(
      id: 'chat',
      serverId: 'server',
      messages: [message],
    );

    state.editMessage(chat, message, '   ');

    expect(message.content, 'ответ');
    expect(message.versionCount, 1);
    expect(message.editedAt, isNull);
  });

  test('server export leaves out api keys and bridge tokens', () {
    final server = ServerConfig(
      id: '1',
      name: 'PC',
      baseUrl: '127.0.0.1:1234',
      apiKey: 'api-secret',
      bridgeUrl: '127.0.0.1:1235',
      bridgeToken: 'bridge-secret',
    );

    final persisted = server.toJson(includeSecrets: true);
    expect(persisted['apiKey'], 'api-secret');
    expect(persisted['bridgeToken'], 'bridge-secret');

    final exported = server.toJson();
    expect(exported.containsKey('apiKey'), isFalse);
    expect(exported.containsKey('bridgeToken'), isFalse);
    expect(exported['baseUrl'], '127.0.0.1:1234');

    final restored = ServerConfig.fromJson(exported);
    expect(restored.apiKey, isEmpty);
    expect(restored.bridgeToken, isEmpty);
  });

  test('app data carries a schema version', () {
    final data = AppData();
    expect(data.toJson()['schemaVersion'], AppData.currentSchemaVersion);
    expect(
      AppData.fromJson(data.toJson()).schemaVersion,
      AppData.currentSchemaVersion,
    );
    // Files written before the field existed are schema version 1.
    expect(AppData.fromJson(const {}).schemaVersion, 1);
  });

  test('chat title is truncated without breaking an emoji', () {
    final text = '${'а' * 47}😀хвост';
    final title = titleFromPrompt(text);
    expect(title.runes.length, 49); // 48 runes + ellipsis
    expect(title.endsWith('😀…'), isTrue);
  });

  test('archived answer keeps the generation start time', () {
    final started = DateTime(2026, 1, 2, 3, 4, 5);
    final message = ChatMessage(
      id: 'a1',
      role: 'assistant',
      content: 'ответ',
      createdAt: DateTime(2026, 1, 1),
      generationStartedAt: started,
    );

    final archived = message.archiveCurrent();
    expect(archived, isNotNull);
    expect(archived!.createdAt, started);
  });
}
