import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/model_catalog.dart';
import 'package:lm_chat/models.dart';

void main() {
  test('catalog caches models per server and expires them after ttl', () {
    var now = DateTime(2026, 1, 1, 12);
    final catalog = ModelCatalog(
      now: () => now,
      ttl: const Duration(minutes: 2),
    );

    expect(catalog.isStale('server'), isTrue);
    expect(catalog.modelsFor('server'), isEmpty);

    catalog.set('server', const [
      LmModelInfo(key: 'model-a', displayName: 'Model A'),
    ]);

    expect(catalog.isStale('server'), isFalse);
    expect(catalog.modelsFor('server').single.key, 'model-a');
    expect(catalog.info('server', 'model-a')?.displayName, 'Model A');
    expect(catalog.info('server', 'missing'), isNull);

    now = now.add(const Duration(minutes: 2));
    expect(catalog.isStale('server'), isTrue);
    // Stale data is still available while a refresh is in flight.
    expect(catalog.modelsFor('server'), hasLength(1));

    catalog.remove('server');
    expect(catalog.modelsFor('server'), isEmpty);
    expect(catalog.isStale('server'), isTrue);
  });
}
