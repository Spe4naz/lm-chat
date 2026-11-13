import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/app_state.dart';
import 'package:lm_chat/models.dart';
import 'package:lm_chat/profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('profile export drops secrets and built-in prompts', () {
    final data = AppData(
      servers: [
        ServerConfig(
          id: 'server',
          name: 'PC',
          baseUrl: '192.168.1.5:1234',
          apiKey: 'api-secret',
          bridgeUrl: 'http://192.168.1.5:1235',
          bridgeToken: 'bridge-secret',
        ),
      ],
      promptTemplates: const [
        PromptTemplate(id: 'custom', name: 'Custom', content: 'Be nice'),
        PromptTemplate(
          id: 'builtin-code',
          name: 'Built-in',
          content: 'ignored',
          builtIn: true,
        ),
      ],
    );

    final profile = AppProfile.fromData(data);
    final json = jsonEncode(profile.toJson());

    expect(json, isNot(contains('api-secret')));
    expect(json, isNot(contains('bridge-secret')));
    expect(profile.servers.single.apiKey, isEmpty);
    expect(profile.servers.single.bridgeToken, isEmpty);
    expect(profile.promptTemplates.map((template) => template.id), ['custom']);
  });

  test('hand-edited profile cannot inject credentials', () {
    final data = AppData(
      servers: [
        ServerConfig(id: 'server', name: 'PC', baseUrl: '192.168.1.5:1234'),
      ],
    );
    final json = AppProfile.fromData(data).toJson();
    final server = (json['servers'] as List).first as Map<String, dynamic>;
    server['apiKey'] = 'leaked';
    server['bridgeToken'] = 'leaked-bridge';

    final restored = AppProfile.fromJson(json);

    expect(restored.servers.single.apiKey, isEmpty);
    expect(restored.servers.single.bridgeToken, isEmpty);
  });

  test('profile round trip keeps settings', () {
    final data = AppData(
      themeMode: AppThemeMode.light,
      appLanguage: AppLanguage.en,
      fontFamily: AppFontFamily.manrope,
      fontScale: 1.1,
      uiDensity: UiDensity.compact,
      defaultTemperature: 0.4,
      defaultTopP: 0.8,
      defaultTopK: 64,
      defaultRepeatPenalty: 1.1,
      defaultMaxTokens: 512,
      defaultSystemPrompt: 'Be brief',
      defaultResponseFormat: const ResponseFormat(
        mode: ResponseFormatMode.jsonSchema,
        schema: '{"type":"object"}',
      ),
      defaultLaunch: const LaunchSettings(
        contextLength: 8192,
        loadOnDemand: false,
        flashAttention: false,
      ),
    );

    final restored = AppProfile.fromJson(AppProfile.fromData(data).toJson());

    expect(restored.themeMode, AppThemeMode.light);
    expect(restored.appLanguage, AppLanguage.en);
    expect(restored.fontFamily, AppFontFamily.manrope);
    expect(restored.fontScale, 1.1);
    expect(restored.uiDensity, UiDensity.compact);
    expect(restored.defaultTemperature, 0.4);
    expect(restored.defaultTopP, 0.8);
    expect(restored.defaultTopK, 64);
    expect(restored.defaultRepeatPenalty, 1.1);
    expect(restored.defaultMaxTokens, 512);
    expect(restored.defaultSystemPrompt, 'Be brief');
    expect(restored.defaultResponseFormat.mode, ResponseFormatMode.jsonSchema);
    expect(restored.defaultResponseFormat.schema, '{"type":"object"}');
    expect(restored.defaultLaunch.contextLength, 8192);
    expect(restored.defaultLaunch.loadOnDemand, false);
    expect(restored.defaultLaunch.flashAttention, false);
  });

  test(
    'import merges servers, preserves local tokens and avoids duplicates',
    () {
      final state = AppState();
      addTearDown(state.dispose);
      state.data.servers.add(
        ServerConfig(
          id: 's1',
          name: 'Old name',
          baseUrl: '192.168.1.5:1234',
          apiKey: 'local-api',
          bridgeUrl: 'http://192.168.1.5:1235',
          bridgeToken: 'local-bridge',
        ),
      );

      final profile = AppProfile(
        servers: [
          ServerConfig(
            id: 's1',
            name: 'Home PC',
            baseUrl: '192.168.1.5:1234',
            bridgeUrl: 'http://192.168.1.5:1235',
            chatViaBridge: false,
          ),
          ServerConfig(id: 's2', name: 'Laptop', baseUrl: '192.168.1.6:1234'),
        ],
        promptTemplates: const [
          PromptTemplate(id: 'custom', name: 'Custom', content: 'Be nice'),
        ],
        themeMode: AppThemeMode.light,
        appLanguage: AppLanguage.en,
        fontFamily: AppFontFamily.inter,
        fontScale: 1.05,
        uiDensity: UiDensity.compact,
        defaultTemperature: 0.3,
        defaultTopP: 0.7,
        defaultTopK: 64,
        defaultRepeatPenalty: 1.1,
        defaultMaxTokens: 256,
        defaultSystemPrompt: 'Short',
        defaultResponseFormat: const ResponseFormat(),
        defaultLaunch: const LaunchSettings(contextLength: 4096),
      );

      final preview = state.parseProfileJson(jsonEncode(profile.toJson()));
      expect(preview.ok, isTrue);

      final result = state.importProfile(preview);
      expect(result.ok, isTrue);
      expect(result.serversAdded, 1);
      expect(result.serversUpdated, 1);
      expect(result.templates, 1);
      expect(state.data.servers.length, 2);
      expect(state.data.promptTemplates.length, 1);

      final updated = state.serverById('s1');
      expect(updated, isNotNull);
      expect(updated!.name, 'Home PC');
      expect(updated.apiKey, 'local-api');
      expect(updated.bridgeToken, 'local-bridge');
      expect(updated.chatViaBridge, isFalse);

      expect(state.data.defaultTemperature, 0.3);
      expect(state.data.defaultTopP, 0.7);
      expect(state.data.defaultTopK, 64);
      expect(state.data.defaultRepeatPenalty, 1.1);
      expect(state.data.defaultMaxTokens, 256);
      expect(state.data.defaultSystemPrompt, 'Short');
      expect(state.data.themeMode, AppThemeMode.light);
      expect(state.data.appLanguage, AppLanguage.en);
      expect(state.data.fontFamily, AppFontFamily.inter);
      expect(state.data.fontScale, 1.05);
      expect(state.data.uiDensity, UiDensity.compact);
      expect(state.data.defaultLaunch.contextLength, 4096);

      final again = state.importProfile(preview);
      expect(again.serversAdded, 0);
      expect(again.templates, 0);
      expect(state.data.servers.length, 2);
      expect(state.data.promptTemplates.length, 1);
    },
  );

  test('changing a server address drops its old tokens', () {
    final state = AppState();
    addTearDown(state.dispose);
    state.data.servers.add(
      ServerConfig(
        id: 's1',
        name: 'PC',
        baseUrl: '192.168.1.5:1234',
        apiKey: 'local-api',
        bridgeUrl: 'http://192.168.1.5:1235',
        bridgeToken: 'local-bridge',
      ),
    );

    final profile = AppProfile(
      servers: [
        ServerConfig(
          id: 's1',
          name: 'PC',
          baseUrl: '10.0.0.5:1234',
          bridgeUrl: 'http://10.0.0.5:1235',
        ),
      ],
      promptTemplates: const [],
      themeMode: AppThemeMode.dark,
      appLanguage: AppLanguage.ru,
      fontFamily: AppFontFamily.system,
      fontScale: 1,
      defaultTemperature: 0.7,
      defaultTopP: 0.95,
      defaultMaxTokens: -1,
      defaultSystemPrompt: '',
      defaultResponseFormat: const ResponseFormat(),
      defaultLaunch: const LaunchSettings(),
    );
    final preview = state.parseProfileJson(jsonEncode(profile.toJson()));
    final result = state.importProfile(
      preview,
      options: const ProfileImportOptions(
        generation: false,
        appearance: false,
        prompts: false,
      ),
    );

    expect(result.ok, isTrue);
    expect(result.serversUpdated, 1);
    final server = state.data.servers.single;
    expect(server.baseUrl, '10.0.0.5:1234');
    expect(server.apiKey, isEmpty);
    expect(server.bridgeUrl, 'http://10.0.0.5:1235');
    expect(server.bridgeToken, isEmpty);
  });

  test('import can skip a section and requires at least one', () {
    final state = AppState();
    addTearDown(state.dispose);
    final preview = state.parseProfileJson(
      jsonEncode(
        AppProfile(
          servers: [
            ServerConfig(id: 's1', name: 'PC', baseUrl: '192.168.1.5:1234'),
          ],
          promptTemplates: const [],
          themeMode: AppThemeMode.light,
          appLanguage: AppLanguage.ru,
          fontFamily: AppFontFamily.system,
          fontScale: 1,
          defaultTemperature: 0.7,
          defaultTopP: 0.95,
          defaultMaxTokens: -1,
          defaultSystemPrompt: '',
          defaultResponseFormat: const ResponseFormat(),
          defaultLaunch: const LaunchSettings(),
        ).toJson(),
      ),
    );
    expect(preview.ok, isTrue);

    final none = state.importProfile(
      preview,
      options: const ProfileImportOptions(
        servers: false,
        generation: false,
        appearance: false,
        prompts: false,
      ),
    );
    expect(none.error, isNotNull);

    final result = state.importProfile(
      preview,
      options: const ProfileImportOptions(
        generation: false,
        appearance: false,
        prompts: false,
      ),
    );
    expect(result.ok, isTrue);
    expect(result.serversAdded, 1);
    expect(state.data.servers.single.name, 'PC');
  });

  test('history export is rejected as a profile', () {
    final state = AppState();
    addTearDown(state.dispose);

    final preview = state.parseProfileJson(jsonEncode({'chats': <Object>[]}));

    expect(preview.ok, isFalse);
    expect(preview.error, isNotNull);
  });

  test('profile import clamps max tokens', () {
    AppProfile profile(int tokens) => AppProfile(
      servers: const [],
      promptTemplates: const [],
      themeMode: AppThemeMode.dark,
      appLanguage: AppLanguage.ru,
      fontFamily: AppFontFamily.system,
      fontScale: 1,
      defaultTemperature: 0.7,
      defaultTopP: 0.95,
      defaultMaxTokens: tokens,
      defaultSystemPrompt: '',
      defaultResponseFormat: const ResponseFormat(),
      defaultLaunch: const LaunchSettings(),
    );

    expect(
      AppProfile.fromJson(profile(99999999).toJson()).defaultMaxTokens,
      maxProfileTokens,
    );
    expect(AppProfile.fromJson(profile(-42).toJson()).defaultMaxTokens, -1);
  });
}
