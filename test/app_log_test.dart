import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/app_log.dart';

void main() {
  setUp(AppLog.instance.clear);

  test('log keeps the newest entries within the limit', () {
    for (var i = 0; i < AppLog.maxEntries + 5; i++) {
      AppLog.instance.info('entry $i');
    }

    final entries = AppLog.instance.entries;
    expect(entries, hasLength(AppLog.maxEntries));
    expect(entries.first.message, 'entry 5');
    expect(entries.last.message, 'entry ${AppLog.maxEntries + 4}');
  });

  test('log text includes level, message and detail', () {
    AppLog.instance.warning('bridge failed', detail: 'connection refused');
    final text = AppLog.instance.asText();
    expect(text, contains('[warning] bridge failed'));
    expect(text, contains('connection refused'));
  });
}
