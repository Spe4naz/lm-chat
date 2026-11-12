import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import 'l10n.dart';
import 'models.dart';
import 'secret_store.dart';

/// Owns `lm_chat_data.json`: loading, backups, serialised writes, isolate
/// encoding and secret migration to the secure store.
class HistoryStore {
  HistoryStore({SecretStore? secretStore, this.onStatus})
    : _secretStore = secretStore ?? SecureSecretStore();

  final SecretStore _secretStore;
  void Function(String? message)? onStatus;

  void cancelScheduledSave() => _saveTimer?.cancel();

  AppData data = AppData();

  /// Test hook: points the history at a temporary directory.
  Future<File> Function()? dataFileOverride;

  bool _secretsAvailable = false;
  bool _secretsDirty = false;
  bool _warnedNoKeystore = false;
  Timer? _saveTimer;
  Future<void> _saveChain = Future<void>.value();

  Future<void> load() async {
    File? dataFile;
    var hadPlaintextSecrets = false;
    try {
      dataFile = await _dataFile();
      final decoded = await _readDataFile(dataFile);
      hadPlaintextSecrets = _containsSecrets(decoded);
      if (decoded != null) data = AppData.fromJson(decoded);
    } catch (error) {
      onStatus?.call(
        L10n.tf('Не удалось загрузить историю: {error}', {'error': error}),
      );
    }

    var shouldScrub = hadPlaintextSecrets;
    try {
      _secretsAvailable = await _secretStore.isAvailable();
      if (_secretsAvailable) {
        shouldScrub = await _loadSecrets() || shouldScrub;
      }
      if (dataFile != null) {
        shouldScrub =
            await _fileContainsSecrets(File('${dataFile.path}.bak')) ||
            shouldScrub;
      }
    } catch (_) {
      // No secure store: tokens stay in memory for this session only.
      _secretsAvailable = false;
    }

    if (hadPlaintextSecrets && !_secretsAvailable) {
      _warnedNoKeystore = true;
      onStatus?.call(
        L10n.t(
          'Безопасное хранилище недоступно: токены не сохранятся после перезапуска.',
        ),
      );
    }

    if (shouldScrub) {
      try {
        // Rewrite both the history and its backup without credentials. The
        // tokens remain in memory for this session when the keystore is absent.
        await saveNow(scrubBackup: true);
      } catch (error) {
        onStatus?.call(
          L10n.tf('Не удалось удалить токены из истории: {error}', {
            'error': error,
          }),
        );
      }
    }
  }

  /// True when credentials are stored in the platform keystore.
  bool get secretsAvailable => _secretsAvailable;

  void markSecretsDirty() => _secretsDirty = true;

  Future<void> deleteServerSecrets(String serverId) async {
    if (!_secretsAvailable) return;
    try {
      await _secretStore.delete(serverId);
    } catch (_) {
      // The server is already removed from the JSON.
    }
  }

  void scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () {
      saveNow().catchError((Object error) {
        onStatus?.call(
          L10n.tf('Не удалось сохранить: {error}', {'error': error}),
        );
      });
    });
  }

  Future<void> saveNow({bool scrubBackup = false}) {
    final next = _saveChain.then((_) async {
      await _syncSecretsIfNeeded();
      if (!_secretsAvailable &&
          !_warnedNoKeystore &&
          data.servers.any(
            (server) =>
                server.apiKey.isNotEmpty || server.bridgeToken.isNotEmpty,
          )) {
        _warnedNoKeystore = true;
        onStatus?.call(
          L10n.t(
            'Безопасное хранилище недоступно: токены не сохранятся после перезапуска.',
          ),
        );
      }
      // Credentials live in the platform keystore. The history file must never
      // contain them, even when the keystore is unavailable.
      final payload = data.toJson(includeSecrets: false);
      final json = await _encodeData(payload);
      await _writeData(json, scrubBackup: scrubBackup);
    });
    _saveChain = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  /// Test hook: runs the same serialised save used by the app.
  Future<void> saveForTest() => saveNow();

  void dispose() {
    _saveTimer?.cancel();
  }

  /// Loads tokens from the Keystore and migrates older plain-JSON secrets.
  ///
  /// Returns true when at least one plaintext token was moved to the keystore.
  Future<bool> _loadSecrets() async {
    var migrated = false;
    for (final server in data.servers) {
      final stored = await _secretStore.read(server.id);
      if (!stored.isEmpty) {
        server.apiKey = stored.apiKey;
        server.bridgeToken = stored.bridgeToken;
      } else if (server.apiKey.isNotEmpty || server.bridgeToken.isNotEmpty) {
        await _secretStore.write(
          server.id,
          ServerSecrets(apiKey: server.apiKey, bridgeToken: server.bridgeToken),
        );
        migrated = true;
      }
    }
    _secretsDirty = false;
    return migrated;
  }

  Future<void> _syncSecretsIfNeeded() async {
    if (!_secretsAvailable || !_secretsDirty) return;
    try {
      for (final server in data.servers) {
        await _secretStore.write(
          server.id,
          ServerSecrets(apiKey: server.apiKey, bridgeToken: server.bridgeToken),
        );
      }
      _secretsDirty = false;
    } catch (_) {
      // The keystore failed while writing. Keep the tokens in memory only and
      // let the next save write a history file without credentials.
      _secretsAvailable = false;
      _secretsDirty = false;
      onStatus?.call(
        L10n.t('Не удалось сохранить токены в безопасном хранилище.'),
      );
    }
  }

  /// Checks a decoded history for legacy plaintext credentials.
  bool _containsSecrets(Object? value) {
    if (value is Map) {
      final apiKey = value['apiKey'];
      if (apiKey is String && apiKey.isNotEmpty) return true;
      final bridgeToken = value['bridgeToken'];
      if (bridgeToken is String && bridgeToken.isNotEmpty) return true;
      for (final item in value.values) {
        if (_containsSecrets(item)) return true;
      }
    } else if (value is List) {
      for (final item in value) {
        if (_containsSecrets(item)) return true;
      }
    }
    return false;
  }

  /// Streaming check for secrets in a legacy `.bak` file. Keeps a small tail so
  /// a key split between chunks is still found.
  Future<bool> _fileContainsSecrets(File file) async {
    if (!await file.exists()) return false;
    const markers = ['"apiKey"', '"bridgeToken"'];
    final reader = await file.open();
    try {
      const chunkSize = 64 * 1024;
      var tail = '';
      while (true) {
        final bytes = await reader.read(chunkSize);
        if (bytes.isEmpty) break;
        final text = tail + utf8.decode(bytes, allowMalformed: true);
        if (markers.any(text.contains)) return true;
        tail = text.length > 32 ? text.substring(text.length - 32) : text;
      }
    } finally {
      await reader.close();
    }
    return false;
  }

  /// Reads the history, falling back to `.bak` when the main file is damaged.
  Future<Map<String, dynamic>?> _readDataFile(File file) async {
    Future<Map<String, dynamic>?> parse(File source) async {
      if (!await source.exists()) return null;
      final decoded = jsonDecode(await source.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
      throw const FormatException('Корень файла истории — не объект');
    }

    try {
      final decoded = await parse(file);
      if (decoded != null) return decoded;
    } catch (_) {
      final restored = await parse(File('${file.path}.bak'));
      if (restored != null) {
        onStatus?.call(L10n.t('История восстановлена из резервной копии'));
        return restored;
      }
      rethrow;
    }

    // The main file is missing: a backup may still be usable after a crash
    // between the temporary write and rename.
    final restored = await parse(File('${file.path}.bak'));
    if (restored != null) {
      onStatus?.call(L10n.t('История восстановлена из резервной копии'));
    }
    return restored;
  }

  Future<File> _dataFile() async {
    final override = dataFileOverride;
    if (override != null) return override();
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}lm_chat_data.json');
  }

  /// JSON encoding of a large history is noticeable on the UI thread, so it
  /// runs in a short-lived isolate; the synchronous fallback keeps desktop and
  /// restricted environments working.
  Future<String> _encodeData(Map<String, dynamic> payload) async {
    try {
      return await Isolate.run(() => jsonEncode(payload));
    } catch (_) {
      return jsonEncode(payload);
    }
  }

  Future<void> _writeData(String json, {bool scrubBackup = false}) async {
    final file = await _dataFile();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(json, flush: true);

    // Keep a recent copy for recovery. Copying the whole history on every
    // streaming save would be wasteful, so refresh it at most once per 5 min.
    // When scrubbing legacy credentials, never copy the old file: it may still
    // contain plaintext tokens.
    if (!scrubBackup && await file.exists()) {
      try {
        final backup = File('${file.path}.bak');
        var shouldCopy = true;
        if (await backup.exists()) {
          final age = DateTime.now().difference((await backup.stat()).modified);
          shouldCopy = age > const Duration(minutes: 5);
        }
        if (shouldCopy) await file.copy(backup.path);
      } catch (_) {
        // Backup is best-effort; never block the actual save.
      }
    }

    try {
      await temp.rename(file.path);
    } on PathNotFoundException {
      // A leftover writer already moved the temporary file.
      await file.writeAsString(json, flush: true);
    }

    if (scrubBackup) {
      // Replace a legacy backup that may contain plaintext credentials with
      // the clean payload. This keeps a usable backup without leaking secrets.
      await File('${file.path}.bak').writeAsString(json, flush: true);
    }
  }
}
