import 'api.dart';
import 'models.dart';

/// Owns per-chat transport clients, cancellation and the direct-vs-bridge
/// stream selection. Message/state bookkeeping stays in `AppState`.
class GenerationController {
  GenerationController({LmClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? LmClient.new;

  final LmClient Function() _clientFactory;
  final Map<String, LmClient> _clients = {};
  final Set<String> _generating = {};
  final Set<String> _aborted = {};

  /// Servers whose bridge does not support `/chat` (older bridge versions).
  final Set<String> _bridgeChatDisabled = {};

  /// Servers whose `/health` capabilities have already been checked.
  final Set<String> _bridgeChecked = {};

  bool isGenerating(String chatId) => _generating.contains(chatId);

  bool isAborted(String chatId) => _aborted.contains(chatId);

  void resetBridgeForServer(String serverId) {
    _bridgeChatDisabled.remove(serverId);
    _bridgeChecked.remove(serverId);
  }

  /// Registers a generation and returns its stream. Registration is
  /// synchronous, so a second send sees the chat as busy immediately.
  Stream<ChatChunk> begin({
    required ServerConfig server,
    required ChatSession chat,
    required ChatMessage placeholder,
    required List<Map<String, dynamic>> history,
    required void Function(String message) onBridgeUnsupported,
    void Function()? onJobChanged,
  }) {
    final client = _clientFactory();
    _clients[chat.id] = client;
    _generating.add(chat.id);
    _aborted.remove(chat.id);
    return _stream(
      client: client,
      server: server,
      chat: chat,
      placeholder: placeholder,
      history: history,
      onBridgeUnsupported: onBridgeUnsupported,
      onJobChanged: onJobChanged,
    );
  }

  /// Re-attaches to a bridge job after a network drop or restart.
  Stream<ChatChunk> attachBridgeJob({
    required ServerConfig server,
    required ChatSession chat,
    required ChatMessage message,
    required int since,
    required void Function(int next) onSeq,
  }) {
    final client = _clientFactory();
    _clients[chat.id] = client;
    _generating.add(chat.id);
    _aborted.remove(chat.id);
    return client.streamBridgeJob(
      server,
      message.jobId!,
      since: since,
      onSeq: onSeq,
    );
  }

  void finish(String chatId) {
    _generating.remove(chatId);
    _aborted.remove(chatId);
    final client = _clients.remove(chatId);
    client?.close();
  }

  void stop(String chatId) {
    _aborted.add(chatId);
    final client = _clients[chatId];
    if (client != null) client.abort();
  }

  void dispose() {
    for (final client in _clients.values) {
      client.close();
    }
    _clients.clear();
    _generating.clear();
    _aborted.clear();
  }

  Stream<ChatChunk> _stream({
    required LmClient client,
    required ServerConfig server,
    required ChatSession chat,
    required ChatMessage placeholder,
    required List<Map<String, dynamic>> history,
    required void Function(String message) onBridgeUnsupported,
    void Function()? onJobChanged,
  }) async* {
    var useBridge =
        server.hasBridge &&
        server.chatViaBridge &&
        !_bridgeChatDisabled.contains(server.id);
    if (useBridge && !_bridgeChecked.contains(server.id)) {
      _bridgeChecked.add(server.id);
      try {
        final health = await client.bridgeHealth(server);
        if (!health.supportsChat) {
          _bridgeChatDisabled.add(server.id);
          useBridge = false;
          onBridgeUnsupported(
            'Мостик не поддерживает чат — обновите lms_gpu_bridge.py, '
            'чтобы ответ готовился в фоне.',
          );
        }
      } catch (_) {
        // Old/unreachable /health: try /chat and keep the 404 fallback.
      }
    }
    if (useBridge) {
      var started = false;
      try {
        await for (final chunk in client.streamChatViaBridge(
          server: server,
          model: chat.model,
          messages: history,
          temperature: chat.temperature,
          topP: chat.topP,
          topK: chat.topK,
          repeatPenalty: chat.repeatPenalty,
          maxTokens: chat.maxTokens,
          format: chat.responseFormat,
          ttlSeconds: chat.launch.ttlSeconds,
          onJob: (job) {
            placeholder.jobId = job;
            placeholder.jobServerId = server.id;
            placeholder.jobSeq = 0;
            onJobChanged?.call();
          },
          onSeq: (next) => placeholder.jobSeq = next,
        )) {
          started = true;
          yield chunk;
        }
        return;
      } on BridgeChatUnsupported {
        if (started) rethrow;
        _bridgeChatDisabled.add(server.id);
        onBridgeUnsupported(
          'Мостик не поддерживает чат — обновите lms_gpu_bridge.py, '
          'чтобы ответ готовился в фоне.',
        );
      }
    }
    yield* client.streamChat(
      server: server,
      model: chat.model,
      messages: history,
      temperature: chat.temperature,
      topP: chat.topP,
      topK: chat.topK,
      repeatPenalty: chat.repeatPenalty,
      maxTokens: chat.maxTokens,
      format: chat.responseFormat,
      ttlSeconds: chat.launch.ttlSeconds,
    );
  }
}
