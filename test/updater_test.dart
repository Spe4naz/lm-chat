import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/models.dart';
import 'package:lm_chat/updater.dart';
import 'package:pub_semver/pub_semver.dart';

const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, dynamic> _release({
  String tag = 'v1.8.0',
  String? digest = 'sha256:$_hash',
  String body = '',
  List<Map<String, dynamic>>? assets,
}) => {
  'tag_name': tag,
  'body': body,
  'html_url': 'https://github.com/Spe4naz/lm-chat/releases/tag/$tag',
  'assets':
      assets ??
      [
        {
          'name': 'lm-chat-universal.apk',
          'browser_download_url':
              'https://github.com/Spe4naz/lm-chat/releases/download/$tag/lm-chat-universal.apk',
          'size': 123,
          'digest': digest,
        },
        {
          'name': 'lm-chat-setup-1.8.0.exe',
          'browser_download_url':
              'https://github.com/Spe4naz/lm-chat/releases/download/$tag/lm-chat-setup-1.8.0.exe',
          'size': 456,
          'digest': digest,
        },
      ],
};

void main() {
  test('Android selects the universal APK and parses the digest', () {
    final info = UpdateService.parseRelease(
      _release(),
      platform: 'android',
      currentVersion: Version.parse('1.7.1'),
    );

    expect(info, isNotNull);
    expect(info!.assetName, 'lm-chat-universal.apk');
    expect(info.version, Version.parse('1.8.0'));
    expect(info.sha256, _hash);
    expect(info.assetSize, 123);
  });

  test('Windows selects the setup installer', () {
    final info = UpdateService.parseRelease(
      _release(),
      platform: 'windows',
      currentVersion: Version.parse('1.7.1'),
    );

    expect(info, isNotNull);
    expect(info!.assetName, 'lm-chat-setup-1.8.0.exe');
  });

  test('an equal or older release is not offered', () {
    expect(
      UpdateService.parseRelease(
        _release(tag: 'v1.8.0'),
        platform: 'android',
        currentVersion: Version.parse('1.8.0+17'),
      ),
      isNull,
    );
    expect(
      UpdateService.parseRelease(
        _release(tag: 'v1.7.9'),
        platform: 'android',
        currentVersion: Version.parse('1.8.0'),
      ),
      isNull,
    );
  });

  test('release notes are used when GitHub has no asset digest', () {
    final info = UpdateService.parseRelease(
      _release(digest: null, body: 'SHA-256\n$_hash  lm-chat-universal.apk'),
      platform: 'android',
      currentVersion: Version.parse('1.7.1'),
    );

    expect(info, isNotNull);
    expect(info!.sha256, _hash);
  });

  test('a release without a required asset reports a readable error', () {
    expect(
      () => UpdateService.parseRelease(
        _release(assets: const []),
        platform: 'android',
        currentVersion: Version.parse('1.7.1'),
      ),
      throwsA(isA<UpdateException>()),
    );
  });

  test('a release with an unexpected asset name is rejected', () {
    final assets = [
      {
        'name': 'lm-chat-setup-evil.exe',
        'browser_download_url': 'https://github.com/Spe4naz/lm-chat/releases/download/v1.8.1/lm-chat-setup-evil.exe',
        'size': 456,
        'digest': 'sha256:$_hash',
      },
    ];
    expect(
      () => UpdateService.parseRelease(
        _release(assets: assets),
        platform: 'windows',
        currentVersion: Version.parse('1.7.1'),
      ),
      throwsA(isA<UpdateException>()),
    );
  });

  test('an oversized update asset is rejected', () {
    final assets = [
      {
        'name': 'lm-chat-universal.apk',
        'browser_download_url': 'https://github.com/Spe4naz/lm-chat/releases/download/v1.8.1/lm-chat-universal.apk',
        'size': UpdateService.maxAssetBytes + 1,
        'digest': 'sha256:$_hash',
      },
    ];
    expect(
      () => UpdateService.parseRelease(
        _release(assets: assets),
        platform: 'android',
        currentVersion: Version.parse('1.7.1'),
      ),
      throwsA(isA<UpdateException>()),
    );
  });

  test('a non-GitHub download URL is rejected', () {
    final assets = [
      {
        'name': 'lm-chat-universal.apk',
        'browser_download_url': 'https://evil.example/lm-chat-universal.apk',
        'size': 123,
        'digest': 'sha256:$_hash',
      },
    ];
    expect(
      () => UpdateService.parseRelease(
        _release(assets: assets),
        platform: 'android',
        currentVersion: Version.parse('1.7.1'),
      ),
      throwsA(isA<UpdateException>()),
    );
  });

  test('update preferences survive a json round trip', () {
    final data = AppData(
      autoCheckUpdates: false,
      skippedUpdateTag: 'v1.8.0',
      lastUpdateCheck: DateTime.utc(2026, 11, 12, 12, 0),
    );

    final restored = AppData.fromJson(data.toJson());

    expect(restored.autoCheckUpdates, isFalse);
    expect(restored.skippedUpdateTag, 'v1.8.0');
    expect(restored.lastUpdateCheck, DateTime.utc(2026, 11, 12, 12, 0));
    expect(restored.schemaVersion, AppData.currentSchemaVersion);
  });
}
