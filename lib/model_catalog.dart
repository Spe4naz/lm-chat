import 'models.dart';

/// Per-server cache of `/api/v1/models` metadata with a short TTL.
///
/// The UI keeps showing the last known list while a refresh is in flight, but
/// after [ttl] the data is considered stale and callers may refresh it.
class ModelCatalog {
  ModelCatalog({
    DateTime Function()? now,
    this.ttl = const Duration(minutes: 2),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Duration ttl;
  final Map<String, _CachedModels> _cache = {};

  List<LmModelInfo> modelsFor(String serverId) =>
      _cache[serverId]?.models ?? const [];

  DateTime? fetchedAt(String serverId) => _cache[serverId]?.fetchedAt;

  bool isStale(String serverId) {
    final entry = _cache[serverId];
    if (entry == null) return true;
    return _now().difference(entry.fetchedAt) >= ttl;
  }

  void set(String serverId, List<LmModelInfo> models) {
    _cache[serverId] = _CachedModels(models, _now());
  }

  LmModelInfo? info(String serverId, String? modelKey) {
    if (modelKey == null) return null;
    for (final model in modelsFor(serverId)) {
      if (model.key == modelKey) return model;
    }
    return null;
  }

  void remove(String serverId) => _cache.remove(serverId);

  void clear() => _cache.clear();
}

class _CachedModels {
  const _CachedModels(this.models, this.fetchedAt);

  final List<LmModelInfo> models;
  final DateTime fetchedAt;
}
