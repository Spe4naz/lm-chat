import 'models.dart';

/// Portable subset of [AppData] used to move settings between devices.
///
/// The profile never contains API keys or bridge tokens: servers are encoded
/// with `includeSecrets: false`, and [AppProfile.fromJson] clears any secrets
/// that a hand-edited file may contain. Tokens stay in the platform keystore
/// and are entered again on the new device.
class AppProfile {
  AppProfile({
    required this.servers,
    required this.promptTemplates,
    required this.themeMode,
    required this.appLanguage,
    required this.fontFamily,
    required this.fontScale,
    this.uiDensity = UiDensity.normal,
    required this.defaultTemperature,
    required this.defaultTopP,
    this.defaultTopK = 0,
    this.defaultRepeatPenalty = 1.0,
    required this.defaultMaxTokens,
    required this.defaultSystemPrompt,
    required this.defaultResponseFormat,
    required this.defaultLaunch,
  });

  static const String kind = 'lm-chat-profile';
  static const int formatVersion = 1;

  final List<ServerConfig> servers;
  final List<PromptTemplate> promptTemplates;
  final AppThemeMode themeMode;
  final AppLanguage appLanguage;
  final AppFontFamily fontFamily;
  final double fontScale;
  final UiDensity uiDensity;
  final double defaultTemperature;
  final double defaultTopP;
  final int defaultTopK;
  final double defaultRepeatPenalty;
  final int defaultMaxTokens;
  final String defaultSystemPrompt;
  final ResponseFormat defaultResponseFormat;
  final LaunchSettings defaultLaunch;

  factory AppProfile.fromData(AppData data) {
    final publicServers = data.servers
        .map(
          (server) =>
              ServerConfig.fromJson(server.toJson(includeSecrets: false)),
        )
        .toList(growable: false);
    final customTemplates = data.promptTemplates
        .where((template) => !template.builtIn)
        .map(
          (template) => PromptTemplate(
            id: template.id,
            name: template.name,
            content: template.content,
          ),
        )
        .toList(growable: false);

    return AppProfile(
      servers: publicServers,
      promptTemplates: customTemplates,
      themeMode: data.themeMode,
      appLanguage: data.appLanguage,
      fontFamily: data.fontFamily == AppFontFamily.custom
          ? AppFontFamily.system
          : data.fontFamily,
      fontScale: data.fontScale,
      uiDensity: data.uiDensity,
      defaultTemperature: data.defaultTemperature,
      defaultTopP: data.defaultTopP,
      defaultTopK: data.defaultTopK,
      defaultRepeatPenalty: data.defaultRepeatPenalty,
      defaultMaxTokens: data.defaultMaxTokens,
      defaultSystemPrompt: data.defaultSystemPrompt,
      defaultResponseFormat: data.defaultResponseFormat,
      defaultLaunch: data.defaultLaunch,
    );
  }

  Map<String, dynamic> toJson() => {
    'app': 'LM Chat',
    'kind': kind,
    'formatVersion': formatVersion,
    'exportedAt': DateTime.now().toIso8601String(),
    'servers': servers
        .map((server) => server.toJson(includeSecrets: false))
        .toList(),
    'promptTemplates': promptTemplates
        .map((template) => template.toJson())
        .toList(),
    'settings': {
      'themeMode': themeMode.name,
      'appLanguage': appLanguage.name,
      'fontFamily': fontFamily.name,
      'fontScale': fontScale,
      'uiDensity': uiDensity.name,
      'defaultTemperature': defaultTemperature,
      'defaultTopP': defaultTopP,
      'defaultTopK': defaultTopK,
      'defaultRepeatPenalty': defaultRepeatPenalty,
      'defaultMaxTokens': defaultMaxTokens,
      'defaultSystemPrompt': defaultSystemPrompt,
      if (defaultResponseFormat.isStructured)
        'defaultResponseFormat': defaultResponseFormat.toJson(),
      'defaultLaunch': defaultLaunch.toJson(),
    },
  };

  factory AppProfile.fromJson(Map<String, dynamic> json) {
    final defaults = AppData();
    final settings = json['settings'] is Map
        ? Map<String, dynamic>.from(json['settings'] as Map)
        : const <String, dynamic>{};
    var fontFamily = _enumByName(
      AppFontFamily.values,
      settings['fontFamily'],
      defaults.fontFamily,
    );
    // The TTF file itself is never part of the profile, so a profile that was
    // exported with a custom font falls back to the system font.
    if (fontFamily == AppFontFamily.custom) fontFamily = AppFontFamily.system;

    final servers = <ServerConfig>[];
    final rawServers = json['servers'];
    if (rawServers is List) {
      for (final item in rawServers) {
        if (item is! Map) continue;
        final server = ServerConfig.fromJson(Map<String, dynamic>.from(item));
        // A profile must never carry credentials, even if the file was edited
        // by hand. The new device asks for them again.
        server.apiKey = '';
        server.bridgeToken = '';
        if (server.generationSecurityError != null) continue;
        servers.add(server);
      }
    }

    final templates = <PromptTemplate>[];
    final rawTemplates = json['promptTemplates'];
    if (rawTemplates is List) {
      for (final item in rawTemplates) {
        if (item is! Map) continue;
        final template = PromptTemplate.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (template.content.trim().isEmpty) continue;
        templates.add(
          PromptTemplate(
            id: template.id,
            name: template.name,
            content: template.content,
          ),
        );
      }
    }

    final launch = settings['defaultLaunch'] is Map
        ? LaunchSettings.fromJson(
            Map<String, dynamic>.from(settings['defaultLaunch'] as Map),
          )
        : defaults.defaultLaunch;

    return AppProfile(
      servers: servers,
      promptTemplates: templates,
      themeMode: _enumByName(
        AppThemeMode.values,
        settings['themeMode'],
        defaults.themeMode,
      ),
      appLanguage: _enumByName(
        AppLanguage.values,
        settings['appLanguage'],
        defaults.appLanguage,
      ),
      fontFamily: fontFamily,
      fontScale:
          ((settings['fontScale'] as num?)?.toDouble() ?? defaults.fontScale)
              .clamp(0.85, 1.3)
              .toDouble(),
      uiDensity: _enumByName(
        UiDensity.values,
        settings['uiDensity'],
        defaults.uiDensity,
      ),
      defaultTemperature:
          ((settings['defaultTemperature'] as num?)?.toDouble() ??
                  defaults.defaultTemperature)
              .clamp(0.0, 2.0)
              .toDouble(),
      defaultTopP:
          ((settings['defaultTopP'] as num?)?.toDouble() ??
                  defaults.defaultTopP)
              .clamp(0.0, 1.0)
              .toDouble(),
      defaultTopK:
          ((settings['defaultTopK'] as num?)?.toInt() ?? defaults.defaultTopK)
              .clamp(0, 1000),
      defaultRepeatPenalty:
          ((settings['defaultRepeatPenalty'] as num?)?.toDouble() ??
                  defaults.defaultRepeatPenalty)
              .clamp(0.5, 2.0)
              .toDouble(),
      defaultMaxTokens:
          (settings['defaultMaxTokens'] as num?)?.toInt() ??
          defaults.defaultMaxTokens,
      defaultSystemPrompt:
          settings['defaultSystemPrompt'] as String? ??
          defaults.defaultSystemPrompt,
      defaultResponseFormat: settings['defaultResponseFormat'] is Map
          ? ResponseFormat.fromJson(
              Map<String, dynamic>.from(
                settings['defaultResponseFormat'] as Map,
              ),
            )
          : const ResponseFormat(),
      defaultLaunch: launch.copyWith(
        flashAttention: launch.flashAttention ?? true,
        offloadKvCache: launch.offloadKvCache ?? true,
        evalBatchSize: launch.evalBatchSize ?? 2048,
      ),
    );
  }
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

/// A profile read from a file, without changing the current settings yet.
class ProfilePreview {
  const ProfilePreview({
    this.profile,
    this.sourceName,
    this.cancelled = false,
    this.error,
  });

  final AppProfile? profile;
  final String? sourceName;
  final bool cancelled;
  final String? error;

  bool get ok => error == null && !cancelled && profile != null;

  int get serverCount => profile?.servers.length ?? 0;
  int get promptCount => profile?.promptTemplates.length ?? 0;
}

/// Which parts of a profile should be applied.
class ProfileImportOptions {
  const ProfileImportOptions({
    this.servers = true,
    this.generation = true,
    this.appearance = true,
    this.prompts = true,
  });

  final bool servers;
  final bool generation;
  final bool appearance;
  final bool prompts;

  bool get any => servers || generation || appearance || prompts;
}

class ProfileImportResult {
  const ProfileImportResult({
    this.serversAdded = 0,
    this.serversUpdated = 0,
    this.templates = 0,
    this.cancelled = false,
    this.error,
  });

  final int serversAdded;
  final int serversUpdated;
  final int templates;
  final bool cancelled;
  final String? error;

  bool get ok => error == null && !cancelled;
}

class ProfileExportResult {
  const ProfileExportResult({this.path, this.cancelled = false, this.error});

  final String? path;
  final bool cancelled;
  final String? error;

  bool get ok => error == null && !cancelled;
}
