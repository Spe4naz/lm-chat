import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ServerSecrets {
  const ServerSecrets({this.apiKey = '', this.bridgeToken = ''});

  final String apiKey;
  final String bridgeToken;

  bool get isEmpty => apiKey.isEmpty && bridgeToken.isEmpty;
}

/// Storage for per-server secrets. The real implementation uses the platform
/// keystore through `flutter_secure_storage`. If no secure store is available,
/// secrets are kept in memory only and are never written to `lm_chat_data.json`.
abstract class SecretStore {
  Future<bool> isAvailable();

  Future<ServerSecrets> read(String serverId);

  Future<void> write(String serverId, ServerSecrets secrets);

  Future<void> delete(String serverId);
}

class SecureSecretStore implements SecretStore {
  SecureSecretStore([this.storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage storage;
  bool? _available;

  static String _apiKey(String id) => 'lm_chat.$id.apiKey';
  static String _bridgeToken(String id) => 'lm_chat.$id.bridgeToken';

  @override
  Future<bool> isAvailable() async {
    final cached = _available;
    if (cached != null) return cached;
    try {
      await storage.read(key: 'lm_chat.secret_probe');
      _available = true;
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      _available = false;
    } catch (_) {
      _available = false;
    }
    return _available!;
  }

  @override
  Future<ServerSecrets> read(String serverId) async {
    final apiKey = await storage.read(key: _apiKey(serverId)) ?? '';
    final bridgeToken = await storage.read(key: _bridgeToken(serverId)) ?? '';
    return ServerSecrets(apiKey: apiKey, bridgeToken: bridgeToken);
  }

  @override
  Future<void> write(String serverId, ServerSecrets secrets) async {
    if (secrets.apiKey.isEmpty) {
      await storage.delete(key: _apiKey(serverId));
    } else {
      await storage.write(key: _apiKey(serverId), value: secrets.apiKey);
    }
    if (secrets.bridgeToken.isEmpty) {
      await storage.delete(key: _bridgeToken(serverId));
    } else {
      await storage.write(
        key: _bridgeToken(serverId),
        value: secrets.bridgeToken,
      );
    }
  }

  @override
  Future<void> delete(String serverId) async {
    await storage.delete(key: _apiKey(serverId));
    await storage.delete(key: _bridgeToken(serverId));
  }
}

/// In-memory store used by tests. It keeps secrets for the lifetime of the
/// process and never persists them.
class MemorySecretStore implements SecretStore {
  final Map<String, ServerSecrets> _values = {};

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ServerSecrets> read(String serverId) async =>
      _values[serverId] ?? const ServerSecrets();

  @override
  Future<void> write(String serverId, ServerSecrets secrets) async {
    if (secrets.isEmpty) {
      _values.remove(serverId);
    } else {
      _values[serverId] = secrets;
    }
  }

  @override
  Future<void> delete(String serverId) async {
    _values.remove(serverId);
  }
}
