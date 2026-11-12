import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';

class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class UpdateInfo {
  const UpdateInfo({
    required this.tag,
    required this.version,
    required this.notes,
    required this.htmlUrl,
    required this.assetName,
    required this.assetUrl,
    required this.assetSize,
    required this.sha256,
  });

  final String tag;
  final Version version;
  final String notes;
  final Uri htmlUrl;
  final String assetName;
  final Uri assetUrl;
  final int assetSize;
  final String sha256;
}

/// Checks GitHub Releases and installs a newer APK/installer.
///
/// The release asset digest is taken from the GitHub API (`digest`), with a
/// fallback to the `SHA-256` block in the release notes. Downloads are verified
/// before anything is executed.
class UpdateService extends ChangeNotifier {
  UpdateService({http.Client? client, String? currentVersion, String? platform})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _currentVersionOverride = currentVersion,
      _platformOverride = platform;

  static final Uri _latestReleaseUri = Uri.parse(
    'https://api.github.com/repos/Spe4naz/lm-chat/releases/latest',
  );
  static const String _userAgent = 'lm-chat-updater';
  static const MethodChannel _updateChannel = MethodChannel('lm_chat/update');

  final http.Client _client;
  final bool _ownsClient;
  final String? _currentVersionOverride;
  final String? _platformOverride;

  UpdateInfo? available;
  bool checking = false;
  bool installing = false;
  double progress = 0;
  String? error;
  String? status;

  String get platform => _platformOverride ?? Platform.operatingSystem;

  bool get canInstallHere => platform == 'android' || platform == 'windows';

  Future<UpdateInfo?> check() async {
    if (checking) return available;
    checking = true;
    error = null;
    notifyListeners();
    try {
      final current = await _currentVersion();
      if (current == null) {
        throw const UpdateException('Не удалось определить версию приложения.');
      }
      final response = await _client
          .get(
            _latestReleaseUri,
            headers: const {
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
              'User-Agent': _userAgent,
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 404) {
        throw const UpdateException('Релизы LM Chat на GitHub не найдены.');
      }
      if (response.statusCode == 403) {
        throw const UpdateException(
          'GitHub временно ограничил проверку обновлений. Попробуйте позже.',
        );
      }
      if (response.statusCode != 200) {
        throw UpdateException('GitHub вернул ошибку ${response.statusCode}.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const UpdateException('Некорректный ответ GitHub.');
      }
      final latest = parseRelease(
        decoded,
        platform: platform,
        currentVersion: current,
      );
      available = latest;
      return latest;
    } catch (errorValue) {
      available = null;
      error = _humanError(errorValue);
      return null;
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  Future<void> install({void Function(double value)? onProgress}) async {
    final info = available;
    if (info == null || installing) return;
    installing = true;
    progress = 0;
    error = null;
    status = null;
    notifyListeners();
    try {
      if (!canInstallHere) {
        throw const UpdateException(
          'Автоматическая установка поддерживается только на Android и Windows.',
        );
      }
      final directory = await getTemporaryDirectory();
      final updateDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}updates',
      );
      await updateDirectory.create(recursive: true);
      final file = File(
        '${updateDirectory.path}${Platform.pathSeparator}${info.assetName}',
      );
      if (!await _fileMatches(file, info)) {
        await _download(info, file, onProgress: onProgress);
      }
      if (!await _fileMatches(file, info)) {
        throw const UpdateException('Контрольная сумма файла не совпала.');
      }
      if (platform == 'android') {
        await _installAndroid(file);
      } else if (platform == 'windows') {
        await _installWindows(file);
      }
      notifyListeners();
    } catch (errorValue) {
      error = _humanError(errorValue);
      rethrow;
    } finally {
      installing = false;
      notifyListeners();
    }
  }

  void dismiss() {
    available = null;
    error = null;
    status = null;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
    super.dispose();
  }

  Future<Version?> _currentVersion() async {
    final override = _currentVersionOverride;
    if (override != null) {
      return _tryVersion(override);
    }
    try {
      final info = await PackageInfo.fromPlatform();
      final raw = info.version.trim();
      if (raw.isEmpty) return null;
      if (raw.contains('+')) return _tryVersion(raw);
      final build = info.buildNumber.trim();
      return _tryVersion(build.isEmpty ? raw : '$raw+$build');
    } catch (_) {
      return null;
    }
  }

  Future<void> _download(
    UpdateInfo info,
    File file, {
    void Function(double value)? onProgress,
  }) async {
    if (await file.exists()) {
      await file.delete();
    }
    final request = http.Request('GET', info.assetUrl);
    request.headers['User-Agent'] = _userAgent;
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw UpdateException(
        'Не удалось скачать обновление (HTTP ${response.statusCode}).',
      );
    }
    final total = response.contentLength ?? info.assetSize;
    final sink = file.openWrite();
    final digestSink = _DigestSink();
    final digestInput = sha256.startChunkedConversion(digestSink);
    var received = 0;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
      )) {
        digestInput.add(chunk);
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          progress = (received / total).clamp(0.0, 1.0);
          onProgress?.call(progress);
          notifyListeners();
        }
      }
      await sink.flush();
      await sink.close();
      digestInput.close();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {
        // Ignore a close error after a failed download.
      }
      if (await file.exists()) await file.delete();
      rethrow;
    }
    final digest = digestSink.value?.toString().toLowerCase();
    if (digest == null || digest != info.sha256.toLowerCase()) {
      if (await file.exists()) await file.delete();
      throw const UpdateException('Контрольная сумма файла не совпала.');
    }
    progress = 1;
    onProgress?.call(1);
    notifyListeners();
  }

  Future<bool> _fileMatches(File file, UpdateInfo info) async {
    if (!await file.exists()) return false;
    if (info.assetSize > 0 && await file.length() != info.assetSize) {
      return false;
    }
    final digest = await _sha256File(file);
    return digest.toLowerCase() == info.sha256.toLowerCase();
  }

  Future<String> _sha256File(File file) async {
    final output = _DigestSink();
    final input = sha256.startChunkedConversion(output);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    return output.value?.toString() ?? '';
  }

  Future<void> _installAndroid(File file) async {
    try {
      final canInstall =
          await _updateChannel.invokeMethod<bool>('canInstallPackages') ?? true;
      if (!canInstall) {
        await _updateChannel.invokeMethod<void>('openInstallSettings');
        throw const UpdateException(
          'Разрешите установку из неизвестных источников для LM Chat и повторите.',
        );
      }
      await _updateChannel.invokeMethod<void>('installApk', {
        'path': file.path,
      });
      status = 'Открыто системное окно установки. Нажмите «Обновить».';
    } on MissingPluginException {
      throw const UpdateException(
        'Установка APK не поддерживается на этом устройстве.',
      );
    }
  }

  Future<void> _installWindows(File file) async {
    final executable = File(Platform.resolvedExecutable);
    final uninstaller = File(
      '${executable.parent.path}${Platform.pathSeparator}unins000.exe',
    );
    if (!await uninstaller.exists()) {
      throw const UpdateException(
        'Это portable-сборка. Скачайте новый ZIP со страницы релиза.',
      );
    }
    final directory = await getTemporaryDirectory();
    final script = File(
      '${directory.path}${Platform.pathSeparator}lm_chat_update.ps1',
    );
    String quote(String value) => "'${value.replaceAll("'", "''")}'";
    final buffer = StringBuffer()
      ..writeln('\$installer = ${quote(file.path)}')
      ..writeln('\$exe = ${quote(executable.path)}')
      ..writeln(
        "\$p = Start-Process -FilePath \$installer "
        "-ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"
        "'/CLOSEAPPLICATIONS' -Wait -PassThru",
      )
      ..writeln('if (\$p.ExitCode -eq 0) {')
      ..writeln('  Start-Sleep -Seconds 2')
      ..writeln('  Start-Process -FilePath \$exe')
      ..writeln('}');
    await script.writeAsString(buffer.toString(), flush: true);
    await Process.start('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      script.path,
    ], mode: ProcessStartMode.detached);
    status = 'Устанавливаю обновление… Приложение закроется.';
    notifyListeners();
    await Future<void>.delayed(const Duration(seconds: 1));
    exit(0);
  }

  static UpdateInfo? parseRelease(
    Map<String, dynamic> release, {
    required String platform,
    required Version currentVersion,
  }) {
    final tag = (release['tag_name'] as String? ?? '').trim();
    final versionText = tag.startsWith('v') ? tag.substring(1) : tag;
    final version = _tryVersion(versionText);
    if (version == null || version.compareTo(currentVersion) <= 0) {
      return null;
    }
    final assets =
        (release['assets'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];
    final asset = _selectAsset(assets, platform);
    if (asset == null) {
      throw UpdateException('В релизе $tag нет файла для платформы $platform.');
    }
    final name = asset['name'] as String? ?? '';
    final url = Uri.tryParse(asset['browser_download_url'] as String? ?? '');
    if (url == null) {
      throw const UpdateException('В релизе нет ссылки на файл обновления.');
    }
    final digest =
        _digestFromAsset(asset) ??
        _digestFromNotes(release['body'] as String? ?? '', name);
    if (digest == null) {
      throw UpdateException('В релизе нет SHA-256 для $name.');
    }
    return UpdateInfo(
      tag: tag,
      version: version,
      notes: release['body'] as String? ?? '',
      htmlUrl: Uri.tryParse(release['html_url'] as String? ?? '') ?? url,
      assetName: name,
      assetUrl: url,
      assetSize: (asset['size'] as num?)?.toInt() ?? 0,
      sha256: digest.toLowerCase(),
    );
  }

  static Map<String, dynamic>? _selectAsset(
    List<Map<String, dynamic>> assets,
    String platform,
  ) {
    if (platform == 'android') {
      return assets.cast<Map<String, dynamic>?>().firstWhere(
        (asset) => asset?['name'] == 'lm-chat-universal.apk',
        orElse: () => null,
      );
    }
    if (platform == 'windows') {
      return assets.cast<Map<String, dynamic>?>().firstWhere((asset) {
        final name = asset?['name'] as String? ?? '';
        return name.startsWith('lm-chat-setup-') && name.endsWith('.exe');
      }, orElse: () => null);
    }
    return null;
  }

  static String? _digestFromAsset(Map<String, dynamic> asset) {
    final digest = asset['digest'] as String?;
    if (digest == null) return null;
    final value = digest.startsWith('sha256:')
        ? digest.substring('sha256:'.length)
        : digest;
    return RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value) ? value : null;
  }

  static String? _digestFromNotes(String notes, String assetName) {
    if (assetName.isEmpty) return null;
    final match = RegExp('([0-9a-fA-F]{64})\\s+${RegExp.escape(assetName)}')
        .firstMatch(notes);
    return match?.group(1);
  }

  static String _humanError(Object error) {
    if (error is UpdateException) return error.message;
    if (error is SocketException) {
      return 'Нет подключения к GitHub. Проверьте интернет.';
    }
    if (error is TimeoutException) {
      return 'GitHub не ответил вовремя. Попробуйте позже.';
    }
    return 'Ошибка обновления: $error';
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

Version? _tryVersion(String value) {
  try {
    return Version.parse(value);
  } catch (_) {
    return null;
  }
}
