import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'l10n.dart';
import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Token usage reported by LM Studio for one answer.
class ChatUsage {
  const ChatUsage({this.promptTokens, this.completionTokens, this.totalTokens});

  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;

  bool get isEmpty =>
      promptTokens == null && completionTokens == null && totalTokens == null;

  factory ChatUsage.fromJson(Map<dynamic, dynamic> json) {
    int? read(String key) => (json[key] as num?)?.toInt();
    return ChatUsage(
      promptTokens: read('prompt_tokens'),
      completionTokens: read('completion_tokens'),
      totalTokens: read('total_tokens'),
    );
  }
}

class ChatChunk {
  const ChatChunk(this.content, this.reasoning, {this.usage, this.elapsedMs});

  final String content;
  final String reasoning;

  /// Set on the final chunk when LM Studio returns token usage.
  final ChatUsage? usage;

  /// Server-side generation time of a bridge job, in milliseconds.
  final int? elapsedMs;
}

class ModelLoadResult {
  const ModelLoadResult({
    this.gpuConfirmed,
    this.warning,
    this.command,
    this.viaBridge = false,
  });

  /// null — GPU-параметр не запрашивался; true — сервер подтвердил его.
  final bool? gpuConfirmed;

  /// Понятное объяснение, если параметр не применился.
  final String? warning;

  /// Готовая команда `lms load` для ручного запуска на сервере.
  final String? command;

  /// true — модель загружена через HTTP-мостик к `lms`.
  final bool viaBridge;
}

class BridgeHealth {
  const BridgeHealth({
    required this.ok,
    this.version,
    this.apiVersion,
    this.features = const [],
    this.error,
  });

  final bool ok;
  final String? version;
  final int? apiVersion;
  final List<String> features;
  final String? error;

  /// Old bridges have no `api` field; assume `/chat` exists and let the 404
  /// fallback decide.
  bool get supportsChat => apiVersion == null || features.contains('chat');
}

class BridgeEstimateResult {
  const BridgeEstimateResult({this.output = '', this.error});

  final String output;
  final String? error;

  bool get ok => error == null;
}

/// The bridge is too old and has no `/chat` endpoint.
class BridgeChatUnsupported implements Exception {
  const BridgeChatUnsupported();
}

class LmClient {
  LmClient({this.idleTimeout = const Duration(seconds: 120)});

  /// How long to wait for the next SSE line before giving up. A server that
  /// stops sending without closing the socket would otherwise hang forever.
  final Duration idleTimeout;

  http.Client? _client;

  http.Client get _http => _client ??= http.Client();

  /// Refuses cleartext API requests to public hosts before any socket is opened.
  void _ensureBaseSafe(ServerConfig server) {
    final error = server.baseSecurityError;
    if (error != null) throw ApiException(error);
  }

  /// Refuses cleartext bridge requests to public hosts.
  void _ensureBridgeSafe(ServerConfig server) {
    final error = server.bridgeSecurityError;
    if (error != null) throw ApiException('Мост: $error');
  }

  bool _cancelled = false;
  String? _activeJob;
  ServerConfig? _activeJobServer;

  /// Aborts the in-flight request, if any.
  void close() {
    _client?.close();
    _client = null;
  }

  /// Stops the running bridge job and closes the connection.
  Future<void> abort() async {
    _cancelled = true;
    final job = _activeJob;
    final server = _activeJobServer;
    _activeJob = null;
    _activeJobServer = null;
    close();
    if (job != null && server != null) {
      try {
        await _cancelBridgeJob(server, job);
      } catch (_) {
        // The job will expire on the server anyway.
      }
    }
  }

  Map<String, String> _headers(ServerConfig server) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (server.apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${server.apiKey.trim()}';
    }
    return headers;
  }

  // ------------------------------------------------------------------ bridge

  Map<String, String> _bridgeHeaders(ServerConfig server) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = server.bridgeToken.trim();
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Maps a 0..1 offload ratio to the value accepted by `lms load --gpu`.
  String _bridgeGpu(double ratio) {
    if (ratio <= 0) return 'off';
    if (ratio >= 1) return 'max';
    return ratio.toStringAsFixed(2);
  }

  Future<BridgeHealth> bridgeHealth(ServerConfig server) async {
    _ensureBridgeSafe(server);
    final response = await _http
        .get(server.bridgeUri('health'))
        .timeout(const Duration(seconds: 10));
    final decoded = _decodeBridge(response.body);
    if (response.statusCode == 200 && decoded['ok'] == true) {
      final version = decoded['lms']?.toString();
      final apiVersion = (decoded['api'] as num?)?.toInt();
      final features =
          (decoded['features'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const <String>[];
      return BridgeHealth(
        ok: true,
        version: version,
        apiVersion: apiVersion,
        features: features,
      );
    }
    return BridgeHealth(ok: false, error: _bridgeError(response, decoded));
  }

  /// Loads a model on the server through the `lms` bridge. Unlike the REST
  /// endpoint this supports real GPU offload.
  Future<ModelLoadResult> bridgeLoad(
    ServerConfig server,
    String model, {
    int? contextLength,
    int? ttlSeconds,
    double? gpuRatio,
  }) async {
    _ensureBridgeSafe(server);
    final body = <String, dynamic>{
      'model': model,
      if (contextLength != null && contextLength > 0)
        'context_length': contextLength,
      if (ttlSeconds != null && ttlSeconds > 0) 'ttl': ttlSeconds,
      if (gpuRatio != null) 'gpu': _bridgeGpu(gpuRatio),
    };
    final response = await _http
        .post(
          server.bridgeUri('load'),
          headers: _bridgeHeaders(server),
          body: jsonEncode(body),
        )
        .timeout(const Duration(minutes: 15));
    final decoded = _decodeBridge(response.body);
    if (response.statusCode != 200 || decoded['ok'] == false) {
      throw ApiException(_bridgeError(response, decoded));
    }
    return ModelLoadResult(
      viaBridge: true,
      gpuConfirmed: gpuRatio == null ? null : true,
    );
  }

  Future<void> bridgeUnload(
    ServerConfig server, {
    String? model,
    bool all = false,
  }) async {
    _ensureBridgeSafe(server);
    final body = all ? {'all': true} : {'model': model ?? ''};
    final response = await _http
        .post(
          server.bridgeUri('unload'),
          headers: _bridgeHeaders(server),
          body: jsonEncode(body),
        )
        .timeout(const Duration(minutes: 2));
    final decoded = _decodeBridge(response.body);
    if (response.statusCode != 200 || decoded['ok'] == false) {
      throw ApiException(_bridgeError(response, decoded));
    }
  }

  /// Reports estimated memory usage without loading the model.
  Future<BridgeEstimateResult> bridgeEstimate(
    ServerConfig server,
    String model, {
    int? contextLength,
    double? gpuRatio,
  }) async {
    _ensureBridgeSafe(server);
    final body = <String, dynamic>{
      'model': model,
      if (contextLength != null && contextLength > 0)
        'context_length': contextLength,
      if (gpuRatio != null) 'gpu': _bridgeGpu(gpuRatio),
    };
    final response = await _http
        .post(
          server.bridgeUri('estimate'),
          headers: _bridgeHeaders(server),
          body: jsonEncode(body),
        )
        .timeout(const Duration(minutes: 2));
    final decoded = _decodeBridge(response.body);
    if (response.statusCode != 200 || decoded['ok'] == false) {
      return BridgeEstimateResult(error: _bridgeError(response, decoded));
    }
    return BridgeEstimateResult(
      output: (decoded['output'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> _decodeBridge(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Not JSON: the caller falls back to the raw body.
    }
    return const <String, dynamic>{};
  }

  String _bridgeError(http.Response response, Map<String, dynamic> decoded) {
    if (response.statusCode == 401) {
      return L10n.t('Неверный токен мостика (401)');
    }
    if (response.statusCode == 404) {
      return L10n.t(
        'Мостик не найден (404). Проверьте адрес и обновите '
        'lms_gpu_bridge.py.',
      );
    }
    final error = decoded['error'];
    if (error is String && error.trim().isNotEmpty) return error.trim();
    var detail = response.body.trim();
    if (detail.length > 300) detail = '${detail.substring(0, 300)}…';
    return 'Ошибка мостика ${response.statusCode}'
        '${detail.isEmpty ? '' : ': $detail'}';
  }

  /// Lists models with metadata (context size, loaded state) via the native
  /// `/api/v1/models` endpoint and falls back to OpenAI-compatible `/v1/models`
  /// on older LM Studio builds.
  Future<List<LmModelInfo>> fetchModelsInfo(ServerConfig server) async {
    _ensureBaseSafe(server);
    final response = await _http
        .get(server.apiV1('models'), headers: _headers(server))
        .timeout(const Duration(seconds: 20));

    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map && decoded['models'] is List) {
        return _parseModels(decoded['models'] as List);
      }
    } else if (response.statusCode != 404 && response.statusCode != 405) {
      throw ApiException(_httpError(response.statusCode, response.body));
    }

    final compat = await _http
        .get(server.modelsUri, headers: _headers(server))
        .timeout(const Duration(seconds: 20));
    if (compat.statusCode != 200) {
      throw ApiException(_httpError(compat.statusCode, compat.body));
    }
    final decoded = jsonDecode(utf8.decode(compat.bodyBytes));
    final list = decoded is Map ? decoded['data'] : decoded;
    if (list is! List) {
      throw ApiException('Неожиданный ответ от сервера моделей');
    }
    return _parseModels(list);
  }

  List<LmModelInfo> _parseModels(List list) {
    final models = <LmModelInfo>[];
    for (final item in list) {
      if (item is! Map) continue;
      final info = LmModelInfo.fromJson(Map<String, dynamic>.from(item));
      if (info.key.isNotEmpty) models.add(info);
    }
    models.sort((a, b) {
      if (a.isLoaded != b.isLoaded) return a.isLoaded ? -1 : 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return models;
  }

  /// Loads a model with explicit launch configuration.
  ///
  /// GPU offload ratio is sent as `gpu: {ratio}` (the shape used by the LM
  /// Studio SDK). The v1 REST API does not document this field yet, so a 400
  /// triggers a retry without it and a warning with the `lms load` command.
  Future<ModelLoadResult> loadModel(
    ServerConfig server,
    String model, {
    int? contextLength,
    int? evalBatchSize,
    bool? flashAttention,
    bool? offloadKvCache,
    double? gpuRatio,
  }) async {
    _ensureBaseSafe(server);
    final body = <String, dynamic>{
      'model': model,
      if (contextLength != null && contextLength > 0)
        'context_length': contextLength,
      if (evalBatchSize != null && evalBatchSize > 0)
        'eval_batch_size': evalBatchSize,
      'flash_attention': ?flashAttention,
      'offload_kv_cache_to_gpu': ?offloadKvCache,
    };

    if (gpuRatio == null) {
      final response = await _postLoad(server, body);
      _ensureLoadOk(response);
      return const ModelLoadResult();
    }

    final ratio = gpuRatio < 0
        ? 0.0
        : gpuRatio > 1
        ? 1.0
        : gpuRatio;
    final gpuBody = <String, dynamic>{
      ...body,
      'gpu': {'ratio': ratio},
      'echo_load_config': true,
    };

    var response = await _postLoad(server, gpuBody);
    if (response.statusCode == 400 || response.statusCode == 422) {
      // LM Studio 0.4 REST API rejects the SDK-only `gpu` field.
      response = await _postLoad(server, {...body, 'echo_load_config': true});
      _ensureLoadOk(response);
      return ModelLoadResult(
        gpuConfirmed: false,
        warning:
            'LM Studio не принимает передачу на GPU через REST API, '
            'поэтому модель загружена с настройками сервера. '
            'Задайте оффлоад вручную на Ubuntu:',
        command: gpuCommand(model, ratio),
      );
    }

    _ensureLoadOk(response);
    final confirmed = _gpuEchoed(response.body);
    return ModelLoadResult(
      gpuConfirmed: confirmed,
      warning: confirmed
          ? null
          : 'Сервер принял запрос, но не подтвердил передачу на GPU '
                'в ответе. Проверьте настройки модели в LM Studio.',
    );
  }

  Future<http.Response> _postLoad(
    ServerConfig server,
    Map<String, dynamic> body,
  ) {
    return _http
        .post(
          server.apiV1('models/load'),
          headers: _headers(server),
          body: jsonEncode(body),
        )
        .timeout(const Duration(minutes: 10));
  }

  void _ensureLoadOk(http.Response response) {
    if (response.statusCode != 200) {
      throw ApiException(_httpError(response.statusCode, response.body));
    }
  }

  /// Detects a GPU-related field in the echoed `load_config`.
  bool _gpuEchoed(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return false;
      final config = decoded['load_config'];
      if (config is! Map) return false;
      for (final key in config.keys) {
        final name = key.toString().toLowerCase();
        if (name == 'offload_kv_cache_to_gpu') continue;
        if (name.contains('gpu') || name == 'offload_ratio') return true;
      }
    } catch (_) {
      // Body is not JSON.
    }
    return false;
  }

  Future<void> unloadModel(ServerConfig server, String instanceId) async {
    _ensureBaseSafe(server);
    final response = await _http
        .post(
          server.apiV1('models/unload'),
          headers: _headers(server),
          body: jsonEncode({'instance_id': instanceId}),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw ApiException(_httpError(response.statusCode, response.body));
    }
  }

  // ------------------------------------------------------------- bridge chat

  /// Starts a generation on the bridge and streams its events. The answer keeps
  /// being produced on the server even if the app is frozen or killed.
  Stream<ChatChunk> streamChatViaBridge({
    required ServerConfig server,
    required String model,
    required List<Map<String, dynamic>> messages,
    required double temperature,
    required double topP,
    int topK = 0,
    double repeatPenalty = 1.0,
    required int maxTokens,
    ResponseFormat? format,
    int? ttlSeconds,
    String? jobId,
    void Function(String job)? onJob,
    void Function(int next)? onSeq,
  }) async* {
    _ensureBridgeSafe(server);
    _cancelled = false;
    final job = jobId ?? newId();
    final response = await _http
        .post(
          server.bridgeUri('chat'),
          headers: _bridgeHeaders(server),
          body: jsonEncode(
            _chatRequestBody(
              model: model,
              messages: messages,
              temperature: temperature,
              topP: topP,
              topK: topK,
              repeatPenalty: repeatPenalty,
              maxTokens: maxTokens,
              format: format,
              ttlSeconds: ttlSeconds,
              job: job,
            ),
          ),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode == 404 || response.statusCode == 405) {
      throw const BridgeChatUnsupported();
    }
    final decoded = _decodeBridge(response.body);
    if (response.statusCode != 200 || decoded['ok'] == false) {
      throw ApiException(_bridgeError(response, decoded));
    }

    _activeJob = job;
    _activeJobServer = server;
    onJob?.call(job);
    yield* _pollBridgeJob(server, job, since: 0, onSeq: onSeq);
  }

  /// Re-attaches to a job that was started earlier (for example before the
  /// process was killed) and streams the events that have not been seen yet.
  Stream<ChatChunk> streamBridgeJob(
    ServerConfig server,
    String job, {
    int since = 0,
    void Function(int next)? onSeq,
  }) async* {
    _ensureBridgeSafe(server);
    _cancelled = false;
    _activeJob = job;
    _activeJobServer = server;
    yield* _pollBridgeJob(server, job, since: since, onSeq: onSeq);
  }

  Stream<ChatChunk> _pollBridgeJob(
    ServerConfig server,
    String job, {
    required int since,
    void Function(int next)? onSeq,
  }) async* {
    var next = since;
    var failures = 0;
    try {
      while (!_cancelled) {
        http.Response response;
        try {
          response = await _http
              .get(
                server.bridgeUri('chat/$job?since=$next&wait=20'),
                headers: _bridgeHeaders(server),
              )
              .timeout(const Duration(seconds: 40));
          failures = 0;
        } catch (_) {
          if (_cancelled) return;
          failures++;
          if (failures >= 4) rethrow;
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }

        final decoded = _decodeBridge(response.body);
        if (response.statusCode == 404) {
          throw ApiException('Задание на сервере не найдено или истекло');
        }
        if (response.statusCode != 200 || decoded['ok'] == false) {
          throw ApiException(_bridgeError(response, decoded));
        }

        final events = decoded['events'];
        if (events is List) {
          for (final item in events) {
            if (item is! Map) continue;
            final content = item['content']?.toString() ?? '';
            final reasoning = item['reasoning']?.toString() ?? '';
            final seq = (item['seq'] as num?)?.toInt();
            if (content.isNotEmpty || reasoning.isNotEmpty) {
              yield ChatChunk(content, reasoning);
            }
            // The consumer has already appended this event, so it is safe to
            // persist the new position even if the process dies right after.
            if (seq != null && seq > next) next = seq;
            onSeq?.call(next);
          }
        }

        final value = (decoded['next'] as num?)?.toInt();
        if (value != null && value > next) next = value;
        onSeq?.call(next);

        final error = decoded['error'];
        if (error is String && error.trim().isNotEmpty) {
          throw ApiException(error.trim());
        }

        final usage = decoded['usage'];
        final elapsed = (decoded['elapsed_ms'] as num?)?.toInt();
        final isDone = decoded['done'] == true;
        if (usage is Map || (isDone && elapsed != null)) {
          yield ChatChunk(
            '',
            '',
            usage: usage is Map ? ChatUsage.fromJson(usage) : null,
            elapsedMs: elapsed,
          );
        }
        if (isDone) break;
      }
    } finally {
      _activeJob = null;
      _activeJobServer = null;
    }
  }

  Future<void> _cancelBridgeJob(ServerConfig server, String job) async {
    _ensureBridgeSafe(server);
    await _http
        .post(
          server.bridgeUri('chat/$job/cancel'),
          headers: _bridgeHeaders(server),
          body: '{}',
        )
        .timeout(const Duration(seconds: 10));
  }

  Stream<ChatChunk> streamChat({
    required ServerConfig server,
    required String model,
    required List<Map<String, dynamic>> messages,
    required double temperature,
    required double topP,
    int topK = 0,
    double repeatPenalty = 1.0,
    required int maxTokens,
    ResponseFormat? format,
    int? ttlSeconds,
  }) async* {
    _ensureBaseSafe(server);
    Future<http.StreamedResponse> send({required bool withUsage}) {
      final request = http.Request('POST', server.chatUri);
      _headers(server).forEach((key, value) => request.headers[key] = value);
      request.headers['Accept'] = 'text/event-stream';
      request.body = jsonEncode(
        _chatRequestBody(
          model: model,
          messages: messages,
          temperature: temperature,
          topP: topP,
          topK: topK,
          repeatPenalty: repeatPenalty,
          maxTokens: maxTokens,
          format: format,
          ttlSeconds: ttlSeconds,
          includeUsage: withUsage,
        ),
      );
      return _http.send(request).timeout(const Duration(seconds: 60));
    }

    var response = await send(withUsage: true);
    if (response.statusCode == 400 || response.statusCode == 422) {
      final body = await response.stream.bytesToString();
      if (!_mentionsStreamOptions(body)) {
        // The request was rejected for another reason (bad max_tokens,
        // unknown model, …): retrying without usage would only hide it.
        throw ApiException(_httpError(response.statusCode, body));
      }
      // Older LM Studio builds reject stream_options. Retry without it: the
      // answer is more important than exact token statistics.
      response = await send(withUsage: false);
    }
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw ApiException(_httpError(response.statusCode, body));
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(
          idleTimeout,
          onTimeout: (sink) {
            sink.addError(
              ApiException(
                'Сервер перестал присылать токены. '
                'Проверьте LM Studio и подключение к сети.',
              ),
            );
            sink.close();
          },
        );
    await for (final line in lines) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('data:')) continue;
      final payload = trimmed.substring(5).trim();
      if (payload.isEmpty) continue;
      if (payload == '[DONE]') break;

      final Map<String, dynamic> json;
      try {
        json = jsonDecode(payload) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      final error = json['error'];
      if (error != null) {
        final message = error is Map
            ? (error['message']?.toString() ?? 'Ошибка сервера')
            : error.toString();
        throw ApiException(message);
      }

      final usage = json['usage'];
      if (usage is Map) {
        final parsed = ChatUsage.fromJson(usage);
        if (!parsed.isEmpty) yield ChatChunk('', '', usage: parsed);
      }

      final choices = json['choices'];
      if (choices is! List || choices.isEmpty) continue;
      final first = choices.first;
      if (first is! Map) continue;
      final delta = first['delta'];
      if (delta is! Map) continue;

      final content = delta['content'] as String? ?? '';
      final reasoning =
          delta['reasoning_content'] as String? ??
          delta['reasoning'] as String? ??
          '';
      if (content.isNotEmpty || reasoning.isNotEmpty) {
        yield ChatChunk(content, reasoning);
      }
    }
  }
}

/// One place for the OpenAI-compatible request body. Direct LM Studio and the
/// bridge differ only in `stream_options` and the optional job id.
Map<String, dynamic> _chatRequestBody({
  required String model,
  required List<Map<String, dynamic>> messages,
  required double temperature,
  required double topP,
  int topK = 0,
  double repeatPenalty = 1.0,
  required int maxTokens,
  ResponseFormat? format,
  int? ttlSeconds,
  bool includeUsage = true,
  String? job,
}) => {
  'model': model,
  'messages': messages,
  'temperature': temperature,
  'top_p': topP,
  if (topK > 0) 'top_k': topK,
  if (repeatPenalty > 1.0) 'repeat_penalty': repeatPenalty,
  if (maxTokens > 0) 'max_tokens': maxTokens,
  if (ttlSeconds != null && ttlSeconds > 0) 'ttl': ttlSeconds,
  'stream': true,
  if (includeUsage) 'stream_options': {'include_usage': true},
  ...?format?.requestFields(),
  'job': ?job,
};

bool _mentionsStreamOptions(String body) {
  final text = body.toLowerCase();
  return text.contains('stream_options') || text.contains('stream options');
}

String _httpError(int code, String body) {
  var detail = body.trim();
  try {
    final json = jsonDecode(body);
    if (json is Map) {
      final error = json['error'];
      if (error is Map && error['message'] is String) {
        detail = error['message'] as String;
      } else if (error is String) {
        detail = error;
      } else if (json['message'] is String) {
        detail = json['message'] as String;
      }
    }
  } catch (_) {
    // Body is not JSON, keep the raw text.
  }
  if (detail.length > 300) detail = '${detail.substring(0, 300)}…';
  switch (code) {
    case 401:
      return L10n.t('Неверный API-токен (401)');
    case 403:
      return L10n.t('Доступ запрещён (403)');
    case 404:
      return L10n.t('Метод не найден (404). Возможно, LM Studio старше 0.4.0.');
    default:
      return L10n.tf('Ошибка {code}{detail}', {
        'code': code,
        'detail': detail.isEmpty ? '' : ': $detail',
      });
  }
}

/// Builds a ready-to-run `lms load` command for manual GPU offload.
String gpuCommand(String model, double ratio) {
  final value = ratio <= 0
      ? 'off'
      : ratio >= 1
      ? 'max'
      : ratio.toStringAsFixed(2);
  final quoted = "'${model.replaceAll("'", "'\\''")}'";
  return 'lms load $quoted --gpu $value';
}

String friendlyNetworkError(Object error) {
  // Prefer the exception type: string matching breaks as soon as the platform
  // or the http package changes its wording.
  if (error is SocketException) {
    final text = error.toString().toLowerCase();
    if (text.contains('failed host lookup') || text.contains('nodename')) {
      return 'Не удалось найти сервер. Проверьте адрес.';
    }
    return 'Не удалось подключиться. Проверьте, что LM Studio запущен, '
        'включён «Serve on Local Network» и брандмауэр не блокирует порт.';
  }
  if (error is HandshakeException) {
    return 'Не удалось установить защищённое соединение (TLS). '
        'Проверьте сертификат сервера.';
  }
  if (error is TimeoutException) {
    return 'Сервер не ответил вовремя. Возможно, модель ещё загружается.';
  }
  if (error is HttpException) {
    return 'Соединение прервано: ${error.message}';
  }

  final text = error.toString().toLowerCase();
  if (text.contains('failed host lookup') || text.contains('nodename')) {
    return 'Не удалось найти сервер. Проверьте адрес.';
  }
  if (text.contains('connection refused') ||
      text.contains('connection failed') ||
      text.contains('socketexception')) {
    return 'Не удалось подключиться. Проверьте, что LM Studio запущен, '
        'включён «Serve on Local Network» и брандмауэр не блокирует порт.';
  }
  if (text.contains('timed out') || text.contains('timeout')) {
    return 'Сервер не ответил вовремя. Возможно, модель ещё загружается.';
  }
  if (text.contains('connection closed') || text.contains('aborted')) {
    return 'Соединение прервано.';
  }
  return error.toString();
}
