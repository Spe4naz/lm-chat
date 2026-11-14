import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(0x7fffffff)}';

/// Short chat title from the first user message.
///
/// Truncates by runes, not UTF-16 code units, so an emoji is never cut in
/// half. Grapheme clusters (flags, ZWJ sequences) may still be split, which is
/// acceptable for a title.
enum AppThemeMode { system, light, dark }

/// Vertical rhythm of the interface. Compact saves space on laptops and small
/// windows; normal keeps the roomier touch-friendly spacing.
enum UiDensity { normal, compact }

enum AppLanguage { system, ru, en }

enum AppFontFamily {
  system,
  inter,
  manrope,
  custom;

  String? get family => switch (this) {
    AppFontFamily.system => null,
    AppFontFamily.inter => 'Inter',
    AppFontFamily.manrope => 'Manrope',
    AppFontFamily.custom => null,
  };
}

/// How the model is asked to format its answer.
enum ResponseFormatMode { text, json, jsonSchema, grammar }

/// State of a tool the model invoked through LM Studio.
enum ToolCallStatus {
  running,
  success,
  failure;

  static ToolCallStatus fromName(String? name) => switch (name) {
    'success' => ToolCallStatus.success,
    'failure' => ToolCallStatus.failure,
    _ => ToolCallStatus.running,
  };
}

/// Boundary events of one `tool_call.*` from `/api/v1/chat`.
///
/// LM Studio 0.4.28 sends `tool_call.start` without a name and then a separate,
/// undocumented `tool_call.name` with `tool_name`. Older builds put the name
/// into `start` directly, so both orders have to work.
enum ToolCallEventKind { start, name, arguments, success, failure }

/// A tool call reported while an answer is streamed. LM Studio executes the
/// tool itself, so this is informational: the app shows what the model did and
/// never runs anything.
class ToolCallEvent {
  const ToolCallEvent({
    required this.kind,
    required this.name,
    this.arguments = '',
    this.output = '',
    this.error = '',
  });

  final ToolCallEventKind kind;
  final String name;
  final String arguments;
  final String output;
  final String error;

  bool get opensCall => kind == ToolCallEventKind.start;
}

/// One tool invocation, kept with the answer so the history shows what the
/// model did (created folders, read files, ran commands…) and not just the
/// reply text.
class ToolCallRecord {
  ToolCallRecord({
    required this.name,
    this.arguments = '',
    this.output = '',
    this.error = '',
    this.status = ToolCallStatus.running,
    DateTime? startedAt,
    this.finishedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  String name;

  /// Pretty-printed JSON arguments, or the raw string when it is not JSON.
  String arguments;
  String output;
  String error;
  ToolCallStatus status;
  final DateTime startedAt;
  DateTime? finishedAt;

  bool get isRunning => status == ToolCallStatus.running;

  bool get isFailure => status == ToolCallStatus.failure;

  /// Short argument value used as a one-line hint in the collapsed row.
  ///
  /// File paths and queries are more useful than the content of a write, so
  /// known argument names win over the first key in the JSON object.
  String get summary {
    final source = arguments.trim();
    if (source.isEmpty) return '';
    try {
      final value = jsonDecode(source);
      if (value is Map) {
        const preferred = ['path', 'name', 'query', 'url', 'command'];
        for (final key in preferred) {
          final item = value[key];
          if (item is String || item is num || item is bool) {
            return _shorten('$key: $item');
          }
        }
        for (final entry in value.entries) {
          if (entry.key == 'content' || entry.key == 'data') continue;
          final item = entry.value;
          if (item is String || item is num || item is bool) {
            return _shorten('${entry.key}: $item');
          }
          if (item is List && item.isNotEmpty) {
            return _shorten('${entry.key}: ${item.first}');
          }
        }
      } else if (value is String) {
        return _shorten(value);
      }
    } catch (_) {
      // Not JSON: fall through and show the raw text.
    }
    return _shorten(source.replaceAll(RegExp(r'\s+'), ' '));
  }

  static String _shorten(String text) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 90 ? flat : '${flat.substring(0, 90)}…';
  }

  /// Milliseconds between the start and the result, or null while running.
  int? get durationMs {
    final end = finishedAt;
    if (end == null) return null;
    final millis = end.difference(startedAt).inMilliseconds;
    return millis < 0 ? 0 : millis;
  }

  /// Human-readable result: MCP wraps text in a JSON envelope like
  /// `[{"type":"text","text":"…"}]`, which is noisy to show verbatim.
  String get readableOutput {
    final source = output.trim();
    if (source.isEmpty) return '';
    try {
      final texts = <String>[];
      void collect(Object? item) {
        if (item is String) {
          texts.add(item);
        } else if (item is List) {
          item.forEach(collect);
        } else if (item is Map) {
          final text = item['text'] ?? item['content'];
          if (text is String) texts.add(text);
        }
      }

      collect(jsonDecode(source));
      if (texts.isNotEmpty) return texts.join('\n');
    } catch (_) {
      // Not JSON: show the raw output.
    }
    return source;
  }

  bool get isSuccess => status == ToolCallStatus.success;

  /// Stored arguments decoded back into an object, or null when they are not a
  /// JSON object (for example, when the text was cut at the size limit).
  Map<String, dynamic>? get argumentValues {
    final source = arguments.trim();
    if (source.isEmpty) return null;
    try {
      final value = jsonDecode(source);
      if (value is Map) {
        return value.map((key, item) => MapEntry(key.toString(), item));
      }
    } catch (_) {
      // Not JSON or truncated.
    }
    return null;
  }

  /// Path reported by `fs_write`.
  String get filePath => argumentValues?['path']?.toString() ?? '';

  /// Full content reported by `fs_write`; JSON escapes are already decoded.
  String get fileContent => argumentValues?['content']?.toString() ?? '';

  /// File name suggested in the save dialog, safe for Windows and Android.
  String get fileName {
    final parts = filePath
        .split(RegExp(r'[\\/]'))
        .where((part) => part.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    final name = parts.last.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    return name == '.' || name == '..' ? '' : name;
  }

  /// Write mode reported by `fs_write`; the default is `overwrite`.
  String get fileMode => argumentValues?['mode']?.toString() ?? 'overwrite';

  /// True when the app can reconstruct the written file locally. Only
  /// `fs_write` carries the complete content; `fs_append` and
  /// `fs_write` with `mode: append` have a fragment, and a failed call must
  /// not offer a half-written file.
  bool get canSaveFile =>
      isSuccess &&
      name == 'fs_write' &&
      fileMode != 'append' &&
      fileContent.isNotEmpty &&
      fileName.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'name': name,
    if (arguments.isNotEmpty) 'arguments': arguments,
    if (output.isNotEmpty) 'output': output,
    if (error.isNotEmpty) 'error': error,
    'status': status.name,
    'startedAt': startedAt.toIso8601String(),
    if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
  };

  factory ToolCallRecord.fromJson(Map<String, dynamic> json) {
    final status = json['status'] as String?;
    return ToolCallRecord(
      name: json['name'] as String? ?? 'tool',
      arguments: json['arguments'] as String? ?? '',
      output: json['output'] as String? ?? '',
      error: json['error'] as String? ?? '',
      // Records written before `status` existed were finished, never running.
      status: status == null
          ? ToolCallStatus.success
          : ToolCallStatus.fromName(status),
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
      finishedAt: DateTime.tryParse(json['finishedAt'] as String? ?? ''),
    );
  }
}

/// Folds one streamed [event] into [calls]. A `success`/`failure` event without
/// a preceding `start` still creates a visible record, because older LM Studio
/// builds occasionally skip the start event.
void applyToolCallEvent(List<ToolCallRecord> calls, ToolCallEvent event) {
  ToolCallRecord? pending() {
    // A call that already carries this name keeps its record: `arguments`,
    // `success` and `failure` must update the row created by `start`/`name`.
    if (event.name.isNotEmpty) {
      for (final call in calls.reversed) {
        if (call.isRunning && call.name == event.name) return call;
      }
    }
    // Otherwise adopt the oldest placeholder created by `tool_call.start`.
    // LM Studio 0.4.28 names the call in a separate `tool_call.name` event.
    for (final call in calls) {
      if (call.isRunning && call.name.isEmpty) return call;
    }
    return null;
  }

  void attach(ToolCallRecord call) {
    if (call.name.isEmpty) call.name = event.name;
    if (event.arguments.isNotEmpty) call.arguments = event.arguments;
  }

  switch (event.kind) {
    case ToolCallEventKind.start:
      calls.add(ToolCallRecord(name: event.name));
    case ToolCallEventKind.name:
      final call = pending() ?? ToolCallRecord(name: event.name);
      if (!calls.contains(call)) calls.add(call);
      call.name = event.name;
    case ToolCallEventKind.arguments:
      final call = pending() ?? ToolCallRecord(name: event.name);
      if (!calls.contains(call)) calls.add(call);
      attach(call);
    case ToolCallEventKind.success:
      final call = pending() ?? ToolCallRecord(name: event.name);
      if (!calls.contains(call)) calls.add(call);
      attach(call);
      call.output = event.output;
      call.error = '';
      call.status = ToolCallStatus.success;
      call.finishedAt = DateTime.now();
    case ToolCallEventKind.failure:
      final call = pending() ?? ToolCallRecord(name: event.name);
      if (!calls.contains(call)) calls.add(call);
      attach(call);
      call.error = event.error;
      call.status = ToolCallStatus.failure;
      call.finishedAt = DateTime.now();
  }
}

/// Human-readable label for a tool name reported by LM Studio. The raw name
/// stays available in the expanded card; tools from other servers keep it as
/// the label because the app cannot know what they do.
String toolDisplayName(String name) => switch (name) {
  'computer_status' => 'Состояние',
  'system_info' => 'Система',
  'fs_list' => 'Просмотр',
  'fs_read' => 'Чтение',
  'fs_write' => 'Написание',
  'fs_append' => 'Дополнение',
  'fs_mkdir' => 'Создание',
  'fs_move' => 'Перемещение',
  'fs_delete' => 'Удаление',
  'fs_search' => 'Поиск',
  'open_path' => 'Открытие',
  'shell_run' => 'Команда',
  _ => name,
};

String titleFromPrompt(String text, {int maxLength = 48}) {
  final runes = text.runes.toList(growable: false);
  if (runes.length <= maxLength) return text;
  return '${String.fromCharCodes(runes.take(maxLength))}…';
}

/// Rough token estimate used when the server does not return `usage`.
/// About 3.5 characters per token for mixed Latin/Cyrillic text.
int estimateTokens(String text) {
  final length = text.trim().runes.length;
  if (length == 0) return 0;
  return (length / 3.5).ceil();
}

class ServerConfig {
  ServerConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.apiKey = '',
    this.bridgeUrl = '',
    this.bridgeToken = '',
    this.chatViaBridge = true,
    this.mcpEnabled = false,
    this.mcpIntegrationId = defaultMcpIntegrationId,
  });

  final String id;
  String name;
  String baseUrl;
  String apiKey;

  /// Optional HTTP bridge running `lms load --gpu` on the server machine.
  /// Needed because the LM Studio REST API has no GPU offload parameter.
  String bridgeUrl;
  String bridgeToken;

  /// Send chat requests through the bridge so the answer is generated on the
  /// server and survives the app being backgrounded or killed.
  bool chatViaBridge;

  /// Let the model call LM Studio tools (plugins/MCP) during a chat.
  ///
  /// Tools are only executable through the native `/api/v1/chat` endpoint: the
  /// OpenAI-compatible endpoint ignores `integrations` and the model then
  /// invents tool results. Enabling this switches chat traffic to the native
  /// endpoint, so bridge jobs and structured output are unavailable.
  bool mcpEnabled;

  /// Integration id shown in LM Studio: `mcp/<server>` for a server declared in
  /// `mcp.json` (works through the API) or `lmchat/lm-computer` for the native
  /// plugin, which LM Studio currently refuses to run on API requests.
  String mcpIntegrationId;

  /// A `mcp.json` server is the only integration LM Studio currently allows
  /// over the REST API; the native plugin id is rejected with 403.
  static const String defaultMcpIntegrationId = 'mcp/lm-computer';

  bool get hasMcp => mcpEnabled && mcpIntegrationId.trim().isNotEmpty;

  /// Accepts `192.168.1.5:1234`, `http://host:1234/` or `http://host:1234/v1`.
  String get normalizedBase {
    var value = baseUrl.trim();
    if (value.isEmpty) return value;
    if (!value.contains('://')) value = 'http://$value';
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.toLowerCase().endsWith('/v1')) {
      value = value.substring(0, value.length - 3);
    }
    return value;
  }

  /// Accepts `192.168.1.5:1235` or `http://host:1235/`.
  String get normalizedBridge {
    var value = bridgeUrl.trim();
    if (value.isEmpty) return value;
    if (!value.contains('://')) value = 'http://$value';
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// Default port of the bundled `lms_gpu_bridge.py` HTTP bridge.
  static const int defaultBridgePort = 1235;

  /// The bridge runs on the same machine as LM Studio, so its address is the
  /// server host with [defaultBridgePort]. Returns an empty string when
  /// [baseUrl] has no usable host or points to a public network: the bridge is
  /// plain HTTP, so a public address would leak its token.
  static String bridgeUrlForBase(String baseUrl) {
    final value = _normalizedUrl(baseUrl);
    if (value == null) return '';
    final uri = Uri.tryParse(value);
    final host = uri?.host;
    if (host == null || host.isEmpty) return '';
    final scheme = uri!.scheme.isEmpty ? 'http' : uri.scheme;
    if (!isPrivateUrl(Uri(scheme: scheme, host: host).toString())) return '';
    return Uri(scheme: 'http', host: host, port: defaultBridgePort).toString();
  }

  static String? _normalizedUrl(String value) {
    var normalized = value.trim();
    if (normalized.isEmpty) return null;
    if (!normalized.contains('://')) normalized = 'http://$normalized';
    return normalized;
  }

  bool get hasBridge => normalizedBridge.isNotEmpty;

  bool get isCleartext => normalizedBase.toLowerCase().startsWith('http://');

  /// True for loopback, RFC1918, link-local, CGNAT/Tailscale and `.local`
  /// names. Public HTTP endpoints are rejected by [securityError].
  bool get isPrivateHost => isPrivateUrl(normalizedBase);

  /// True when [value] points to a loopback, private or local-network host.
  static bool isPrivateUrl(String value) {
    final normalized = _normalizedUrl(value);
    if (normalized == null) return false;
    final host = Uri.tryParse(normalized)?.host.toLowerCase();
    if (host == null || host.isEmpty) return false;
    if (host == 'localhost' || host.endsWith('.local')) return true;
    final address = InternetAddress.tryParse(host);
    if (address != null) {
      final bytes = address.rawAddress;
      if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
        return _isPrivateIpv4(bytes);
      }
      if (bytes.length == 16) {
        final loopback = bytes.take(15).every((b) => b == 0) && bytes[15] == 1;
        final uniqueLocal = (bytes[0] & 0xfe) == 0xfc; // fc00::/7
        final linkLocal =
            bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80; // fe80::/10
        return loopback || uniqueLocal || linkLocal;
      }
    }
    // A single-label name such as "ubuntu" is not provably local: it can
    // resolve to a public address through DNS search domains. Require an
    // explicit private name (`.local`) or a private IP literal.
    return false;
  }

  static bool _isPrivateIpv4(List<int> b) {
    if (b[0] == 10 || b[0] == 127) return true; // 10/8, 127/8
    if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true; // 172.16/12
    if (b[0] == 192 && b[1] == 168) return true; // 192.168/16
    if (b[0] == 169 && b[1] == 254) return true; // link-local
    if (b[0] == 100 && b[1] >= 64 && b[1] <= 127) return true; // CGNAT
    return false;
  }

  static String? _securityErrorFor(String value) {
    final normalized = _normalizedUrl(value);
    if (normalized == null) return null;
    if (!normalized.toLowerCase().startsWith('http://')) return null;
    if (isPrivateUrl(normalized)) return null;
    return 'HTTP разрешён только для локальной сети. '
        'Для внешнего сервера используйте HTTPS или Tailscale.';
  }

  /// Null when both the API and bridge addresses are safe, otherwise a
  /// user-facing explanation.
  String? get securityError {
    final base = baseSecurityError;
    if (base != null) return base;
    final bridge = bridgeSecurityError;
    if (bridge != null) return 'Мост: $bridge';
    return null;
  }

  /// Error for the API address only.
  String? get baseSecurityError => _securityErrorFor(normalizedBase);

  /// Error for the bridge address only.
  String? get bridgeSecurityError => _securityErrorFor(normalizedBridge);

  /// Error that should block the next generation. A configured but disabled
  /// bridge does not block direct API requests.
  String? get generationSecurityError {
    final base = baseSecurityError;
    if (base != null) return base;
    if (!chatViaBridge) return null;
    final bridge = bridgeSecurityError;
    return bridge == null ? null : 'Мост: $bridge';
  }

  Uri get modelsUri => Uri.parse('$normalizedBase/v1/models');
  Uri get chatUri => Uri.parse('$normalizedBase/v1/chat/completions');
  Uri apiV1(String path) => Uri.parse('$normalizedBase/api/v1/$path');
  Uri bridgeUri(String path) => Uri.parse('$normalizedBridge/$path');

  bool get isValid => normalizedBase.isNotEmpty;

  /// Secrets are included only when [includeSecrets] is true. The default is
  /// false so persistence, export, sharing and logs cannot leak credentials by
  /// accident; pass true only for an explicit secure-store migration.
  Map<String, dynamic> toJson({bool includeSecrets = false}) => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    if (includeSecrets && apiKey.isNotEmpty) 'apiKey': apiKey,
    if (bridgeUrl.isNotEmpty) 'bridgeUrl': bridgeUrl,
    if (includeSecrets && bridgeToken.isNotEmpty) 'bridgeToken': bridgeToken,
    if (!chatViaBridge) 'chatViaBridge': false,
    if (mcpEnabled) 'mcpEnabled': true,
    if (mcpEnabled && mcpIntegrationId != defaultMcpIntegrationId)
      'mcpIntegrationId': mcpIntegrationId,
  };

  factory ServerConfig.fromJson(Map<String, dynamic> json) => ServerConfig(
    id: json['id'] as String? ?? newId(),
    name: json['name'] as String? ?? 'LM Studio',
    baseUrl: json['baseUrl'] as String? ?? '',
    apiKey: json['apiKey'] as String? ?? '',
    bridgeUrl: json['bridgeUrl'] as String? ?? '',
    bridgeToken: json['bridgeToken'] as String? ?? '',
    chatViaBridge: json['chatViaBridge'] as bool? ?? true,
    mcpEnabled: json['mcpEnabled'] as bool? ?? false,
    mcpIntegrationId:
        json['mcpIntegrationId'] as String? ?? defaultMcpIntegrationId,
  );

  ServerConfig clone() => ServerConfig(
    id: id,
    name: name,
    baseUrl: baseUrl,
    apiKey: apiKey,
    bridgeUrl: bridgeUrl,
    bridgeToken: bridgeToken,
    chatViaBridge: chatViaBridge,
    mcpEnabled: mcpEnabled,
    mcpIntegrationId: mcpIntegrationId,
  );
}

class LoadedInstance {
  const LoadedInstance({
    required this.id,
    this.contextLength,
    this.flashAttention,
    this.offloadKvCache,
    this.evalBatchSize,
    this.parallel,
  });

  final String id;
  final int? contextLength;
  final bool? flashAttention;
  final bool? offloadKvCache;
  final int? evalBatchSize;
  final int? parallel;

  factory LoadedInstance.fromJson(Map<String, dynamic> json) {
    final config = json['config'] is Map
        ? Map<String, dynamic>.from(json['config'] as Map)
        : const <String, dynamic>{};
    return LoadedInstance(
      id: json['id']?.toString() ?? '',
      contextLength: (config['context_length'] as num?)?.toInt(),
      flashAttention: config['flash_attention'] as bool?,
      offloadKvCache: config['offload_kv_cache_to_gpu'] as bool?,
      evalBatchSize: (config['eval_batch_size'] as num?)?.toInt(),
      parallel: (config['parallel'] as num?)?.toInt(),
    );
  }
}

class LmModelInfo {
  const LmModelInfo({
    required this.key,
    required this.displayName,
    this.type = 'llm',
    this.maxContextLength,
    this.sizeBytes,
    this.parameters,
    this.quantization,
    this.vision = false,
    this.loadedInstances = const [],
  });

  final String key;
  final String displayName;
  final String type; // llm | embedding | decision
  final int? maxContextLength;
  final int? sizeBytes;
  final String? parameters;
  final String? quantization;
  final bool vision;
  final List<LoadedInstance> loadedInstances;

  bool get isLlm => type == 'llm' || type.isEmpty;
  bool get isLoaded => loadedInstances.isNotEmpty;
  LoadedInstance? get instance =>
      loadedInstances.isEmpty ? null : loadedInstances.first;

  factory LmModelInfo.fromJson(Map<String, dynamic> json) {
    final key = (json['key'] ?? json['id'] ?? '').toString();
    final capabilities = json['capabilities'] is Map
        ? Map<String, dynamic>.from(json['capabilities'] as Map)
        : const <String, dynamic>{};
    final quantization = json['quantization'] is Map
        ? Map<String, dynamic>.from(json['quantization'] as Map)
        : null;
    final loaded = <LoadedInstance>[];
    final instances = json['loaded_instances'];
    if (instances is List) {
      for (final item in instances) {
        if (item is Map) {
          loaded.add(LoadedInstance.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return LmModelInfo(
      key: key,
      displayName: (json['display_name'] ?? json['id'] ?? key).toString(),
      type: (json['type'] ?? 'llm').toString(),
      maxContextLength: (json['max_context_length'] as num?)?.toInt(),
      sizeBytes: (json['size_bytes'] as num?)?.toInt(),
      parameters: json['params_string']?.toString(),
      quantization: quantization?['name']?.toString(),
      vision: capabilities['vision'] == true,
      loadedInstances: loaded,
    );
  }
}

class LaunchSettings {
  const LaunchSettings({
    this.contextLength,
    this.loadOnDemand = true,
    this.ttlSeconds,
    this.flashAttention,
    this.offloadKvCache,
    this.evalBatchSize,
    this.gpuRatio,
  });

  /// null — использовать значение модели по умолчанию.
  final int? contextLength;

  /// Загружать модель при первом сообщении, а не заранее.
  final bool loadOnDemand;

  /// Автовыгрузка простоя, в секундах. null — настройка сервера.
  final int? ttlSeconds;

  /// null — авто, true — включено, false — выключено.
  final bool? flashAttention;
  final bool? offloadKvCache;
  final int? evalBatchSize;

  /// Доля модели, выгружаемая в видеопамять: 0.0 — только CPU,
  /// 1.0 — максимум. null — настройка LM Studio.
  final double? gpuRatio;

  static const Object _unset = Object();

  /// [copyWith] needs a sentinel for nullable fields: passing `null` must mean
  /// "reset to automatic", while omitting the argument keeps the old value.
  LaunchSettings copyWith({
    Object? contextLength = _unset,
    bool? loadOnDemand,
    Object? ttlSeconds = _unset,
    Object? flashAttention = _unset,
    Object? offloadKvCache = _unset,
    Object? evalBatchSize = _unset,
    Object? gpuRatio = _unset,
  }) => LaunchSettings(
    contextLength: identical(contextLength, _unset)
        ? this.contextLength
        : contextLength as int?,
    loadOnDemand: loadOnDemand ?? this.loadOnDemand,
    ttlSeconds: identical(ttlSeconds, _unset)
        ? this.ttlSeconds
        : ttlSeconds as int?,
    flashAttention: identical(flashAttention, _unset)
        ? this.flashAttention
        : flashAttention as bool?,
    offloadKvCache: identical(offloadKvCache, _unset)
        ? this.offloadKvCache
        : offloadKvCache as bool?,
    evalBatchSize: identical(evalBatchSize, _unset)
        ? this.evalBatchSize
        : evalBatchSize as int?,
    gpuRatio: identical(gpuRatio, _unset) ? this.gpuRatio : gpuRatio as double?,
  );

  Map<String, dynamic> toJson() => {
    if (contextLength != null) 'contextLength': contextLength,
    'loadOnDemand': loadOnDemand,
    if (ttlSeconds != null) 'ttlSeconds': ttlSeconds,
    if (flashAttention != null) 'flashAttention': flashAttention,
    if (offloadKvCache != null) 'offloadKvCache': offloadKvCache,
    if (evalBatchSize != null) 'evalBatchSize': evalBatchSize,
    if (gpuRatio != null) 'gpuRatio': gpuRatio,
  };

  factory LaunchSettings.fromJson(Map<String, dynamic> json) => LaunchSettings(
    contextLength: (json['contextLength'] as num?)?.toInt(),
    loadOnDemand: json['loadOnDemand'] as bool? ?? true,
    ttlSeconds: (json['ttlSeconds'] as num?)?.toInt(),
    flashAttention: json['flashAttention'] as bool?,
    offloadKvCache: json['offloadKvCache'] as bool?,
    evalBatchSize: (json['evalBatchSize'] as num?)?.toInt(),
    gpuRatio: (json['gpuRatio'] as num?)?.toDouble(),
  );
}

/// Structured output settings for one chat.
///
/// JSON modes use the OpenAI-compatible `response_format` field, which LM
/// Studio converts into a grammar for GGUF models. The GBNF mode sends a raw
/// `grammar` field and is meant for llama.cpp-compatible servers.
class ResponseFormat {
  const ResponseFormat({
    this.mode = ResponseFormatMode.text,
    this.schema = '',
    this.grammar = '',
  });

  final ResponseFormatMode mode;

  /// Bare JSON Schema object (not the whole `response_format` wrapper).
  final String schema;

  /// GBNF grammar text, used only by [ResponseFormatMode.grammar].
  final String grammar;

  bool get isText => mode == ResponseFormatMode.text;

  bool get isStructured => !isText;

  static const Object _unset = Object();

  ResponseFormat copyWith({
    ResponseFormatMode? mode,
    Object? schema = _unset,
    Object? grammar = _unset,
  }) => ResponseFormat(
    mode: mode ?? this.mode,
    schema: identical(schema, _unset) ? this.schema : schema as String,
    grammar: identical(grammar, _unset) ? this.grammar : grammar as String,
  );

  Map<String, dynamic>? _schemaValue() {
    final raw = schema.trim();
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Invalid JSON is reported by [validationError].
    }
    return null;
  }

  /// A user-facing reason why this format cannot be sent, or null when valid.
  String? get validationError {
    switch (mode) {
      case ResponseFormatMode.text:
      case ResponseFormatMode.json:
        return null;
      case ResponseFormatMode.jsonSchema:
        if (schema.trim().isEmpty) return 'Введите JSON-схему ответа';
        return _schemaValue() == null
            ? 'Схема ответа — некорректный JSON'
            : null;
      case ResponseFormatMode.grammar:
        return grammar.trim().isEmpty ? 'Введите GBNF-грамматику' : null;
    }
  }

  /// Extra fields for `/v1/chat/completions`, or null for plain text.
  ///
  /// Invalid configurations return null: callers must check
  /// [validationError] before starting a generation.
  Map<String, dynamic>? requestFields() {
    switch (mode) {
      case ResponseFormatMode.text:
        return null;
      case ResponseFormatMode.json:
        return {
          'response_format': {
            'type': 'json_schema',
            'json_schema': {
              'name': 'json_object',
              // A permissive object schema is the most compatible way to ask
              // for JSON: LM Studio documents json_schema, not json_object.
              'strict': false,
              'schema': const {'type': 'object'},
            },
          },
        };
      case ResponseFormatMode.jsonSchema:
        final value = _schemaValue();
        if (value == null) return null;
        return {
          'response_format': {
            'type': 'json_schema',
            'json_schema': {
              'name': 'response',
              'strict': true,
              'schema': value,
            },
          },
        };
      case ResponseFormatMode.grammar:
        final value = grammar.trim();
        if (value.isEmpty) return null;
        return {'grammar': value};
    }
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    if (schema.trim().isNotEmpty) 'schema': schema,
    if (grammar.trim().isNotEmpty) 'grammar': grammar,
  };

  factory ResponseFormat.fromJson(Map<String, dynamic> json) => ResponseFormat(
    mode: ResponseFormatMode.values.firstWhere(
      (mode) => mode.name == json['mode'],
      orElse: () => ResponseFormatMode.text,
    ),
    schema: json['schema'] as String? ?? '',
    grammar: json['grammar'] as String? ?? '',
  );

  @override
  bool operator ==(Object other) =>
      other is ResponseFormat &&
      other.mode == mode &&
      other.schema == schema &&
      other.grammar == grammar;

  @override
  int get hashCode => Object.hash(mode, schema, grammar);
}

/// One answer that was replaced by a newer generation.
///
/// Versions are stored oldest first: `versions.last` is the answer that was
/// visible right before the current one.
class ChatMessageVersion {
  ChatMessageVersion({
    required this.id,
    required this.content,
    this.reasoning = '',
    this.model = '',
    this.error,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
    this.generationMs,
    this.firstTokenMs,
    this.tokensEstimated = false,
    this.editedAt,
    List<ToolCallRecord>? toolCalls,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       toolCalls = toolCalls ?? [];

  final String id;
  final String content;
  final String reasoning;
  final String model;
  final String? error;
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
  final int? generationMs;

  /// Tool calls that produced this answer, in the order the model made them.
  final List<ToolCallRecord> toolCalls;

  /// Time to first token, in milliseconds.
  final int? firstTokenMs;

  /// true — токены посчитаны приблизительно, без `usage` от сервера.
  final bool tokensEstimated;

  /// Когда текст был изменён вручную; null — сгенерирован моделью.
  final DateTime? editedAt;
  final DateTime createdAt;

  bool get isEmpty =>
      content.trim().isEmpty && reasoning.trim().isEmpty && toolCalls.isEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    if (reasoning.isNotEmpty) 'reasoning': reasoning,
    if (model.isNotEmpty) 'model': model,
    if (error != null) 'error': error,
    if (promptTokens != null) 'promptTokens': promptTokens,
    if (completionTokens != null) 'completionTokens': completionTokens,
    if (totalTokens != null) 'totalTokens': totalTokens,
    if (generationMs != null) 'generationMs': generationMs,
    if (firstTokenMs != null) 'firstTokenMs': firstTokenMs,
    if (tokensEstimated) 'tokensEstimated': true,
    if (toolCalls.isNotEmpty)
      'toolCalls': toolCalls.map((call) => call.toJson()).toList(),
    if (editedAt != null) 'editedAt': editedAt!.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory ChatMessageVersion.fromJson(Map<String, dynamic> json) =>
      ChatMessageVersion(
        id: json['id'] as String? ?? newId(),
        content: json['content'] as String? ?? '',
        reasoning: json['reasoning'] as String? ?? '',
        model: json['model'] as String? ?? '',
        error: json['error'] as String?,
        promptTokens: (json['promptTokens'] as num?)?.toInt(),
        completionTokens: (json['completionTokens'] as num?)?.toInt(),
        totalTokens: (json['totalTokens'] as num?)?.toInt(),
        generationMs: (json['generationMs'] as num?)?.toInt(),
        firstTokenMs: (json['firstTokenMs'] as num?)?.toInt(),
        tokensEstimated: json['tokensEstimated'] as bool? ?? false,
        toolCalls:
            (json['toolCalls'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(ToolCallRecord.fromJson)
                .toList() ??
            [],
        editedAt: DateTime.tryParse(json['editedAt'] as String? ?? ''),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
}

class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.mimeType,
    required this.data,
    this.name = '',
  });

  final String id;
  final String mimeType;

  /// Base64-encoded bytes, stored with the message in `lm_chat_data.json`.
  final String data;
  final String name;

  Uint8List get bytes {
    try {
      return base64Decode(data);
    } catch (_) {
      return Uint8List(0);
    }
  }

  String get dataUrl => 'data:$mimeType;base64,$data';

  Map<String, dynamic> toJson() => {
    'id': id,
    'mimeType': mimeType,
    'data': data,
    if (name.isNotEmpty) 'name': name,
  };

  factory ChatAttachment.fromJson(Map<String, dynamic> json) => ChatAttachment(
    id: json['id'] as String? ?? newId(),
    mimeType: json['mimeType'] as String? ?? 'image/jpeg',
    data: json['data'] as String? ?? '',
    name: json['name'] as String? ?? '',
  );
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    this.content = '',
    this.reasoning = '',
    this.model = '',
    List<ChatAttachment>? attachments,
    DateTime? createdAt,
    this.error,
    this.jobId,
    this.jobServerId,
    this.jobSeq = 0,
    List<ChatMessageVersion>? versions,
    this.activeVersion = 0,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
    this.generationMs,
    this.firstTokenMs,
    this.tokensEstimated = false,
    this.generationStartedAt,
    this.editedAt,
    this.notice,
    List<ToolCallRecord>? toolCalls,
  }) : versions = versions ?? [],
       attachments = attachments ?? [],
       toolCalls = toolCalls ?? [],
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String role; // user | assistant
  String content;
  String reasoning;

  /// Images attached to a user message.
  final List<ChatAttachment> attachments;

  /// Model that produced the current answer.
  String model;

  final DateTime createdAt;
  String? error;

  /// Bridge job that is still generating this answer. Persisted so the app can
  /// pick the answer up again after being closed in the background.
  String? jobId;
  String? jobServerId;

  /// Number of the next bridge event to fetch.
  int jobSeq;

  /// Answers that were replaced by a regenerated one. The current answer lives
  /// in [content]/[reasoning]; this list keeps everything that came before it.
  final List<ChatMessageVersion> versions;

  /// Which answer is shown: 0 — the current (newest) one, 1..[versions].length —
  /// an archived version (1 is the oldest).
  int activeVersion;

  /// Statistics of the current answer, persisted with the chat.
  int? promptTokens;
  int? completionTokens;
  int? totalTokens;
  int? generationMs;

  /// Time to first token of the current answer, in milliseconds.
  int? firstTokenMs;

  /// true — токены посчитаны приблизительно, без `usage` от сервера.
  bool tokensEstimated;

  /// Wall-clock start of the generation, kept so a bridge job resumed after a
  /// restart can still report a plausible duration.
  DateTime? generationStartedAt;

  /// When the answer was edited by hand; null — generated by the model.
  DateTime? editedAt;

  /// A non-fatal problem with this answer, for example that the server could
  /// not apply the requested context window or GPU offload. Persisted so the
  /// warning is still visible after a restart.
  String? notice;

  /// Tools the model invoked while producing the current answer. Persisted so
  /// the chat shows what happened to files and commands, not only the text.
  final List<ToolCallRecord> toolCalls;

  /// Transient flags: never persisted.
  bool streaming = false;
  String? status;

  bool get isUser => role == 'user';

  bool get hasPendingJob => jobId != null && jobId!.isNotEmpty;

  bool get hasVersions => versions.isNotEmpty;

  /// Total number of answers, including the current one.
  int get versionCount => versions.length + 1;

  /// 1-based number of the answer currently shown.
  int get displayedVersionNumber =>
      activeVersion <= 0 || activeVersion >= versionCount
      ? versionCount
      : activeVersion;

  bool get viewingLatest => displayedVersionNumber == versionCount;

  ChatMessageVersion? get _displayedVersion =>
      viewingLatest ? null : versions[displayedVersionNumber - 1];

  String get displayContent => _displayedVersion?.content ?? content;

  String get displayReasoning => _displayedVersion?.reasoning ?? reasoning;

  /// Tool calls of the answer currently on screen.
  List<ToolCallRecord> get displayToolCalls =>
      _displayedVersion?.toolCalls ?? toolCalls;

  String? get displayError => viewingLatest ? error : _displayedVersion?.error;

  /// Notices belong to the current answer; archived variants have none.
  String? get displayNotice => viewingLatest ? notice : null;

  String get displayModel =>
      viewingLatest ? model : (_displayedVersion?.model ?? '');

  DateTime get displayCreatedAt => _displayedVersion?.createdAt ?? createdAt;

  int? get displayPromptTokens =>
      viewingLatest ? promptTokens : _displayedVersion?.promptTokens;

  int? get displayCompletionTokens =>
      viewingLatest ? completionTokens : _displayedVersion?.completionTokens;

  int? get displayTotalTokens =>
      viewingLatest ? totalTokens : _displayedVersion?.totalTokens;

  int? get displayGenerationMs =>
      viewingLatest ? generationMs : _displayedVersion?.generationMs;

  int? get displayFirstTokenMs =>
      viewingLatest ? firstTokenMs : _displayedVersion?.firstTokenMs;

  bool get displayTokensEstimated => viewingLatest
      ? tokensEstimated
      : (_displayedVersion?.tokensEstimated ?? false);

  DateTime? get displayEditedAt =>
      viewingLatest ? editedAt : _displayedVersion?.editedAt;

  bool get hasStats =>
      displayGenerationMs != null || displayCompletionTokens != null;

  /// Average generation speed of the displayed answer.
  double? get displayTokensPerSecond {
    final tokens = displayCompletionTokens;
    final millis = displayGenerationMs;
    if (tokens == null || tokens <= 0 || millis == null || millis <= 0) {
      return null;
    }
    return tokens * 1000 / millis;
  }

  /// Snapshot of any answer by its 1-based number, without changing selection.
  ChatMessageVersion variantAt(int ordinal) {
    final number = ordinal.clamp(1, versionCount);
    if (number == versionCount) {
      return ChatMessageVersion(
        id: id,
        content: content,
        reasoning: reasoning,
        model: model,
        error: error,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        totalTokens: totalTokens,
        generationMs: generationMs,
        firstTokenMs: firstTokenMs,
        tokensEstimated: tokensEstimated,
        editedAt: editedAt,
        toolCalls: [...toolCalls],
        createdAt: createdAt,
      );
    }
    return versions[number - 1];
  }

  /// Shows the answer with the given 1-based number. [versionCount] means the
  /// current one.
  void selectVersion(int ordinal) {
    if (ordinal <= 1) {
      activeVersion = versionCount == 1 ? 0 : 1;
    } else if (ordinal >= versionCount) {
      activeVersion = 0;
    } else {
      activeVersion = ordinal;
    }
  }

  /// Moves the current answer into [versions] and clears the fields for a new
  /// generation. Returns null when there is nothing worth keeping.
  ChatMessageVersion? archiveCurrent({String? model}) {
    if (content.trim().isEmpty &&
        reasoning.trim().isEmpty &&
        toolCalls.isEmpty) {
      return null;
    }
    final version = ChatMessageVersion(
      id: newId(),
      content: content,
      reasoning: reasoning,
      model: model ?? this.model,
      error: error,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: totalTokens,
      generationMs: generationMs,
      firstTokenMs: firstTokenMs,
      tokensEstimated: tokensEstimated,
      editedAt: editedAt,
      toolCalls: [...toolCalls],
      // Keep the time the answer was actually produced. Falling back to
      // `createdAt` covers messages restored from an older file.
      createdAt: generationStartedAt ?? createdAt,
    );
    versions.add(version);
    content = '';
    reasoning = '';
    toolCalls.clear();
    error = null;
    jobId = null;
    jobServerId = null;
    jobSeq = 0;
    promptTokens = null;
    completionTokens = null;
    totalTokens = null;
    generationMs = null;
    firstTokenMs = null;
    tokensEstimated = false;
    generationStartedAt = null;
    editedAt = null;
    activeVersion = 0;
    return version;
  }

  /// Puts the last archived answer back as the current one. Used when a
  /// regeneration fails without producing any text.
  bool restoreLatestArchived() {
    if (versions.isEmpty) return false;
    final last = versions.removeLast();
    content = last.content;
    reasoning = last.reasoning;
    toolCalls
      ..clear()
      ..addAll(last.toolCalls);
    error = last.error;
    model = last.model;
    promptTokens = last.promptTokens;
    completionTokens = last.completionTokens;
    totalTokens = last.totalTokens;
    generationMs = last.generationMs;
    firstTokenMs = last.firstTokenMs;
    tokensEstimated = last.tokensEstimated;
    editedAt = last.editedAt;
    generationStartedAt = null;
    activeVersion = 0;
    return true;
  }

  /// Deletes an archived answer. The current (newest) answer cannot be deleted
  /// this way.
  void deleteVersion(int ordinal) {
    if (ordinal < 1 || ordinal >= versionCount) return;
    versions.removeAt(ordinal - 1);
    if (activeVersion == ordinal) {
      activeVersion = 0;
    } else if (activeVersion > ordinal) {
      activeVersion -= 1;
    }
    if (activeVersion >= versionCount) activeVersion = 0;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    if (reasoning.isNotEmpty) 'reasoning': reasoning,
    if (model.isNotEmpty) 'model': model,
    if (attachments.isNotEmpty)
      'attachments': attachments.map((a) => a.toJson()).toList(),
    if (toolCalls.isNotEmpty)
      'toolCalls': toolCalls.map((call) => call.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    if (error != null) 'error': error,
    if (notice != null && notice!.isNotEmpty) 'notice': notice,
    if (jobId != null) 'jobId': jobId,
    if (jobServerId != null) 'jobServerId': jobServerId,
    if (jobSeq > 0) 'jobSeq': jobSeq,
    if (promptTokens != null) 'promptTokens': promptTokens,
    if (completionTokens != null) 'completionTokens': completionTokens,
    if (totalTokens != null) 'totalTokens': totalTokens,
    if (generationMs != null) 'generationMs': generationMs,
    if (firstTokenMs != null) 'firstTokenMs': firstTokenMs,
    if (tokensEstimated) 'tokensEstimated': true,
    if (generationStartedAt != null)
      'generationStartedAt': generationStartedAt!.toIso8601String(),
    if (editedAt != null) 'editedAt': editedAt!.toIso8601String(),
    if (versions.isNotEmpty)
      'versions': versions.map((v) => v.toJson()).toList(),
    if (activeVersion > 0) 'activeVersion': activeVersion,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final versions =
        (json['versions'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(ChatMessageVersion.fromJson)
            .toList() ??
        [];
    var active = (json['activeVersion'] as num?)?.toInt() ?? 0;
    if (active < 0 || active > versions.length) active = 0;
    final message = ChatMessage(
      id: json['id'] as String? ?? newId(),
      role: json['role'] as String? ?? 'assistant',
      content: json['content'] as String? ?? '',
      reasoning: json['reasoning'] as String? ?? '',
      model: json['model'] as String? ?? '',
      attachments:
          (json['attachments'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(ChatAttachment.fromJson)
              .toList() ??
          [],
      toolCalls:
          (json['toolCalls'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(ToolCallRecord.fromJson)
              .toList() ??
          [],
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      error: json['error'] as String?,
      notice: json['notice'] as String?,
      jobId: json['jobId'] as String?,
      jobServerId: json['jobServerId'] as String?,
      jobSeq: (json['jobSeq'] as num?)?.toInt() ?? 0,
      versions: versions,
      activeVersion: active,
      promptTokens: (json['promptTokens'] as num?)?.toInt(),
      completionTokens: (json['completionTokens'] as num?)?.toInt(),
      totalTokens: (json['totalTokens'] as num?)?.toInt(),
      generationMs: (json['generationMs'] as num?)?.toInt(),
      firstTokenMs: (json['firstTokenMs'] as num?)?.toInt(),
      tokensEstimated: json['tokensEstimated'] as bool? ?? false,
      generationStartedAt: DateTime.tryParse(
        json['generationStartedAt'] as String? ?? '',
      ),
      editedAt: DateTime.tryParse(json['editedAt'] as String? ?? ''),
    );
    // Versions up to 1.8.5 created a placeholder for `tool_call.start`, but
    // LM Studio names the call in a separate `tool_call.name` event that the
    // app ignored. Those rows had no name (or were called "tool") and stayed
    // running forever; drop them so old chats stop showing ghosts.
    message.toolCalls.removeWhere(
      (call) =>
          call.isRunning &&
          (call.name.trim().isEmpty ||
              (call.name == 'tool' && call.arguments.trim().isEmpty)),
    );
    // A tool that was running when the app was closed never finishes: mark it
    // as interrupted instead of spinning forever in the history.
    for (final call in message.toolCalls) {
      if (!call.isRunning) continue;
      call.status = ToolCallStatus.failure;
      call.error = 'Вызов прерван';
      call.finishedAt = DateTime.now();
    }
    return message;
  }
}

class ChatSession {
  ChatSession({
    required this.id,
    this.title = 'Новый чат',
    required this.serverId,
    this.model = '',
    List<ChatMessage>? messages,
    this.temperature = 0.7,
    this.topP = 0.95,
    this.topK = 0,
    this.repeatPenalty = 1.0,
    this.maxTokens = -1,
    this.systemPrompt = '',
    this.responseFormat = const ResponseFormat(),
    this.launch = const LaunchSettings(),
    this.pinned = false,
    this.archived = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : messages = messages ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  String serverId;
  String model;
  final List<ChatMessage> messages;
  double temperature;
  double topP;

  /// 0 means "use the server/model default"; LM Studio accepts `top_k` as an
  /// OpenAI-compatible extension.
  int topK;

  /// 1.0 means "no penalty". Values above 1.0 make repeated tokens less likely.
  double repeatPenalty;

  int maxTokens;
  String systemPrompt;
  ResponseFormat responseFormat;
  LaunchSettings launch;
  bool pinned;
  bool archived;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Copy used when an imported chat collides with an existing id.
  ChatSession clone({String? id, String? serverId}) => ChatSession(
    id: id ?? this.id,
    title: title,
    serverId: serverId ?? this.serverId,
    model: model,
    messages: messages,
    temperature: temperature,
    topP: topP,
    topK: topK,
    repeatPenalty: repeatPenalty,
    maxTokens: maxTokens,
    systemPrompt: systemPrompt,
    responseFormat: responseFormat,
    launch: launch,
    pinned: pinned,
    archived: archived,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'serverId': serverId,
    'model': model,
    'messages': messages.map((m) => m.toJson()).toList(),
    'temperature': temperature,
    'topP': topP,
    if (topK > 0) 'topK': topK,
    if (repeatPenalty != 1.0) 'repeatPenalty': repeatPenalty,
    'maxTokens': maxTokens,
    'systemPrompt': systemPrompt,
    if (responseFormat.isStructured) 'responseFormat': responseFormat.toJson(),
    'launch': launch.toJson(),
    if (pinned) 'pinned': true,
    if (archived) 'archived': true,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
    id: json['id'] as String? ?? newId(),
    title: json['title'] as String? ?? 'Новый чат',
    serverId: json['serverId'] as String? ?? '',
    model: json['model'] as String? ?? '',
    messages:
        (json['messages'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(ChatMessage.fromJson)
            .toList() ??
        [],
    temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
    topP: (json['topP'] as num?)?.toDouble() ?? 0.95,
    topK: ((json['topK'] as num?)?.toInt() ?? 0).clamp(0, 1000),
    repeatPenalty: ((json['repeatPenalty'] as num?)?.toDouble() ?? 1.0)
        .clamp(0.5, 2.0)
        .toDouble(),
    maxTokens: (json['maxTokens'] as num?)?.toInt() ?? -1,
    systemPrompt: json['systemPrompt'] as String? ?? '',
    responseFormat: json['responseFormat'] is Map
        ? ResponseFormat.fromJson(
            Map<String, dynamic>.from(json['responseFormat'] as Map),
          )
        : const ResponseFormat(),
    launch: json['launch'] is Map
        ? LaunchSettings.fromJson(
            Map<String, dynamic>.from(json['launch'] as Map),
          )
        : const LaunchSettings(),
    pinned: json['pinned'] as bool? ?? false,
    archived: json['archived'] as bool? ?? false,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
  );
}

class PromptTemplate {
  const PromptTemplate({
    required this.id,
    required this.name,
    required this.content,
    this.builtIn = false,
  });

  final String id;
  final String name;
  final String content;
  final bool builtIn;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'content': content};

  factory PromptTemplate.fromJson(Map<String, dynamic> json) => PromptTemplate(
    id: json['id'] as String? ?? newId(),
    name: json['name'] as String? ?? 'Без названия',
    content: json['content'] as String? ?? '',
  );
}

const builtInPromptTemplates = <PromptTemplate>[
  PromptTemplate(
    id: 'builtin-concise',
    name: 'Кратко и по делу',
    content:
        'Отвечай кратко и по существу. Не повторяй вопрос, не добавляй '
        'вступлений и извинений. Если нужен список — используй короткие пункты.',
    builtIn: true,
  ),
  PromptTemplate(
    id: 'builtin-teacher',
    name: 'Подробный наставник',
    content:
        'Объясняй пошагово и простыми словами. Сначала дай короткий ответ, '
        'затем разбор с примерами. Отмечай типичные ошибки и важные нюансы.',
    builtIn: true,
  ),
  PromptTemplate(
    id: 'builtin-code',
    name: 'Опытный разработчик',
    content:
        'Ты опытный разработчик. Предлагай рабочий код, объясняй ключевые '
        'решения и компромиссы. Учитывай обработку ошибок и граничные случаи. '
        'Не выдумывай API, которых нет.',
    builtIn: true,
  ),
  PromptTemplate(
    id: 'builtin-structured',
    name: 'Структурированный ответ',
    content:
        'Отвечай в структурированном виде: краткое резюме, затем разделы с '
        'заголовками, таблицами или списками, если это уместно. В конце — '
        'один практический следующий шаг.',
    builtIn: true,
  ),
  PromptTemplate(
    id: 'builtin-translator',
    name: 'Переводчик',
    content:
        'Переводи текст на указанный язык, сохраняя смысл, тон и форматирование. '
        'Если термин неоднозначен, предложи короткий вариант перевода в скобках. '
        'Не добавляй пояснений, если пользователь не просил.',
    builtIn: true,
  ),
];

class AppData {
  /// Increment when the on-disk shape changes in a way that needs migration.
  static const int currentSchemaVersion = 15;

  AppData({
    List<ServerConfig>? servers,
    List<ChatSession>? chats,
    this.activeServerId,
    this.defaultTemperature = 0.7,
    this.defaultTopP = 0.95,
    this.defaultTopK = 0,
    this.defaultRepeatPenalty = 1.0,
    this.defaultMaxTokens = -1,
    this.defaultSystemPrompt = '',
    this.defaultResponseFormat = const ResponseFormat(),
    this.defaultLaunch = const LaunchSettings(
      flashAttention: true,
      offloadKvCache: true,
      evalBatchSize: 2048,
    ),
    this.setupDone = false,
    this.backgroundGeneration = true,
    this.autoCheckUpdates = true,
    this.skippedUpdateTag = '',
    this.lastUpdateCheck,
    this.themeMode = AppThemeMode.dark,
    this.appLanguage = AppLanguage.ru,
    this.fontFamily = AppFontFamily.system,
    this.fontScale = 1.0,
    this.customFontName = '',
    this.customFontFamily = '',
    this.customFontFile = '',
    this.uiDensity = UiDensity.normal,
    this.sidebarWidth = 320,
    this.sidebarCollapsed = false,
    List<PromptTemplate>? promptTemplates,
    this.schemaVersion = currentSchemaVersion,
  }) : servers = servers ?? [],
       chats = chats ?? [],
       promptTemplates = promptTemplates ?? [];

  int schemaVersion;
  AppThemeMode themeMode;
  AppLanguage appLanguage;
  AppFontFamily fontFamily;
  double fontScale;

  /// Display name and runtime family of a font imported from a local TTF file.
  /// [customFontFile] is a file name inside the app's documents folder, not an
  /// absolute path, so it survives reinstalls and moved profiles.
  String customFontName;
  String customFontFamily;
  String customFontFile;

  /// Resolves the font family that should be passed to [ThemeData].
  String? get effectiveFontFamily => switch (fontFamily) {
    AppFontFamily.system => null,
    AppFontFamily.inter => 'Inter',
    AppFontFamily.manrope => 'Manrope',
    AppFontFamily.custom => customFontFamily.isEmpty ? null : customFontFamily,
  };
  UiDensity uiDensity;

  /// Desktop chat-list width in logical pixels. Persisted so the window keeps
  /// its layout between launches.
  double sidebarWidth;
  bool sidebarCollapsed;
  final List<ServerConfig> servers;
  final List<ChatSession> chats;
  final List<PromptTemplate> promptTemplates;
  String? activeServerId;
  double defaultTemperature;
  double defaultTopP;
  int defaultTopK;
  double defaultRepeatPenalty;
  int defaultMaxTokens;
  String defaultSystemPrompt;
  ResponseFormat defaultResponseFormat;
  LaunchSettings defaultLaunch;
  bool setupDone;

  /// Keep the process awake with a foreground service while an answer is being
  /// generated, so Android does not freeze the connection.
  bool backgroundGeneration;

  /// Check GitHub Releases on startup (at most once every few hours).
  bool autoCheckUpdates;

  /// Release tag the user chose to postpone.
  String skippedUpdateTag;

  /// Last successful or attempted GitHub release check.
  DateTime? lastUpdateCheck;

  static LaunchSettings _defaultLaunchFromJson(Object? value) {
    final launch = value is Map
        ? LaunchSettings.fromJson(Map<String, dynamic>.from(value))
        : const LaunchSettings();
    return launch.copyWith(
      flashAttention: launch.flashAttention ?? true,
      offloadKvCache: launch.offloadKvCache ?? true,
      evalBatchSize: launch.evalBatchSize ?? 2048,
    );
  }

  /// Secrets are excluded by default. The history writer never enables them;
  /// credentials are stored separately in the platform keystore.
  Map<String, dynamic> toJson({bool includeSecrets = false}) => {
    'schemaVersion': schemaVersion,
    'servers': servers
        .map((s) => s.toJson(includeSecrets: includeSecrets))
        .toList(),
    'chats': chats.map((c) => c.toJson()).toList(),
    'promptTemplates': promptTemplates.map((t) => t.toJson()).toList(),
    'activeServerId': activeServerId,
    'defaultTemperature': defaultTemperature,
    'defaultTopP': defaultTopP,
    if (defaultTopK > 0) 'defaultTopK': defaultTopK,
    if (defaultRepeatPenalty != 1.0)
      'defaultRepeatPenalty': defaultRepeatPenalty,
    'defaultMaxTokens': defaultMaxTokens,
    'defaultSystemPrompt': defaultSystemPrompt,
    if (defaultResponseFormat.isStructured)
      'defaultResponseFormat': defaultResponseFormat.toJson(),
    'defaultLaunch': defaultLaunch.toJson(),
    'setupDone': setupDone,
    'backgroundGeneration': backgroundGeneration,
    'autoCheckUpdates': autoCheckUpdates,
    if (skippedUpdateTag.isNotEmpty) 'skippedUpdateTag': skippedUpdateTag,
    if (lastUpdateCheck != null)
      'lastUpdateCheck': lastUpdateCheck!.toIso8601String(),
    'themeMode': themeMode.name,
    'appLanguage': appLanguage.name,
    'fontFamily': fontFamily.name,
    'fontScale': fontScale,
    'customFontName': customFontName,
    'customFontFamily': customFontFamily,
    'customFontFile': customFontFile,
    'uiDensity': uiDensity.name,
    'sidebarWidth': sidebarWidth,
    'sidebarCollapsed': sidebarCollapsed,
  };

  factory AppData.fromJson(Map<String, dynamic> json) => AppData(
    schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
    servers:
        (json['servers'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(ServerConfig.fromJson)
            .toList() ??
        [],
    chats:
        (json['chats'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(ChatSession.fromJson)
            .toList() ??
        [],
    promptTemplates:
        (json['promptTemplates'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(PromptTemplate.fromJson)
            .toList() ??
        [],
    activeServerId: json['activeServerId'] as String?,
    defaultTemperature: (json['defaultTemperature'] as num?)?.toDouble() ?? 0.7,
    defaultTopP: (json['defaultTopP'] as num?)?.toDouble() ?? 0.95,
    defaultTopK: ((json['defaultTopK'] as num?)?.toInt() ?? 0).clamp(0, 1000),
    defaultRepeatPenalty:
        ((json['defaultRepeatPenalty'] as num?)?.toDouble() ?? 1.0)
            .clamp(0.5, 2.0)
            .toDouble(),
    defaultMaxTokens: (json['defaultMaxTokens'] as num?)?.toInt() ?? -1,
    defaultSystemPrompt: json['defaultSystemPrompt'] as String? ?? '',
    defaultResponseFormat: json['defaultResponseFormat'] is Map
        ? ResponseFormat.fromJson(
            Map<String, dynamic>.from(json['defaultResponseFormat'] as Map),
          )
        : const ResponseFormat(),
    defaultLaunch: _defaultLaunchFromJson(json['defaultLaunch']),
    setupDone: json['setupDone'] as bool? ?? false,
    backgroundGeneration: json['backgroundGeneration'] as bool? ?? true,
    autoCheckUpdates: json['autoCheckUpdates'] as bool? ?? true,
    skippedUpdateTag: json['skippedUpdateTag'] as String? ?? '',
    lastUpdateCheck: DateTime.tryParse(
      json['lastUpdateCheck'] as String? ?? '',
    ),
    themeMode: AppThemeMode.values.firstWhere(
      (mode) => mode.name == json['themeMode'],
      orElse: () => AppThemeMode.dark,
    ),
    appLanguage: AppLanguage.values.firstWhere(
      (language) => language.name == json['appLanguage'],
      orElse: () => AppLanguage.ru,
    ),
    fontFamily: AppFontFamily.values.firstWhere(
      (font) => font.name == json['fontFamily'],
      orElse: () => AppFontFamily.system,
    ),
    fontScale: ((json['fontScale'] as num?)?.toDouble() ?? 1.0).clamp(
      0.85,
      1.3,
    ),
    customFontName: json['customFontName'] as String? ?? '',
    customFontFamily: json['customFontFamily'] as String? ?? '',
    customFontFile: json['customFontFile'] as String? ?? '',
    uiDensity: UiDensity.values.firstWhere(
      (density) => density.name == json['uiDensity'],
      orElse: () => UiDensity.normal,
    ),
    sidebarWidth: ((json['sidebarWidth'] as num?)?.toDouble() ?? 320).clamp(
      240,
      480,
    ),
    sidebarCollapsed: json['sidebarCollapsed'] as bool? ?? false,
  );
}
