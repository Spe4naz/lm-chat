# Сборка и релиз

## Требования

- Flutter 3.47+, Dart из состава Flutter;
- JDK 17+, Android SDK (platform 36, build-tools 36) — для APK;
- Visual Studio с рабочей нагрузкой «Разработка классических приложений на C++»
  и Windows 10 SDK — для EXE;
- Inno Setup 6 — для установщика.

```bash
flutter pub get
flutter analyze
flutter test
```

## APK

```bash
flutter build apk --release
```

Результат: `build/app/outputs/flutter-apk/app-release.apk`.

Компактные сборки:

```bash
flutter build apk --release --split-per-abi
```

- `app-arm64-v8a-release.apk` — современные телефоны;
- `app-armeabi-v7a-release.apk` — старые 32-битные устройства;
- `app-x86_64-release.apk` — эмуляторы.

### Подпись

1. Создайте keystore (один раз, храните вне репозитория):

   ```bash
   keytool -genkeypair -v -keystore keystore.jks -keyalg RSA -keysize 2048 \
     -validity 10000 -alias lm-chat
   ```

2. Скопируйте `android/key.properties.example` в `android/key.properties` и
   заполните `storePassword`, `keyPassword`, `keyAlias`, `storeFile`.
3. Соберите APK.

Без `key.properties` release-сборка **завершается ошибкой**. Для локальной
проверки можно разрешить debug-подпись:

```bash
LMCHAT_ALLOW_DEBUG_SIGNING=1 flutter build apk --release
```

Debug-ключ не годится для публичного релиза и не совместим с release-подписью.

## Windows

```bash
flutter build windows --release
```

Комплект: `build/windows/x64/runner/Release/`. Рядом с `lm_chat.exe` должны
лежать DLL и каталог `data/`.

Установщик:

```powershell
.\tools\build_windows_installer.ps1
```

Скрипт берёт версию из `pubspec.yaml`, собирает release и компилирует
`installer\lm_chat.iss`. Результат: `dist/lm-chat-setup-<версия>.exe`.

Подпись (для автообновления обязательна):

```powershell
$env:LMCHAT_SIGN_CERT="<sha1 сертификата>"
.\tools\build_windows_installer.ps1
```

Скрипт подписывает EXE через `signtool` с timestamp. Без подписи установщик
запускается только вручную — автообновление его отклонит.

## Версия

Версия и build-номер задаются в `pubspec.yaml`:

```yaml
version: 1.8.9+26
```

Приложение сравнивает с текущей версией тег релиза (`v1.8.9`). Build-номер в
сравнении обновлений не участвует, но нужен Android для установки новой сборки.

## Чек-лист релиза

1. Обновить `version` в `pubspec.yaml`.
2. `flutter analyze` и `flutter test` — без ошибок.
3. Собрать APK и EXE, подписать их постоянным ключом/сертификатом.
4. Проверить, что APK ставится поверх предыдущего релиза, а не требует
   переустановки.
5. Посчитать SHA-256:

   ```bash
   sha256sum lm-chat-universal.apk lm-chat-setup-1.8.9.exe
   ```

6. Создать тег `vX.Y.Z` и GitHub Release.
7. Приложить файлы **с точными именами**:
   - `lm-chat-universal.apk` — обязателен для автообновления Android;
   - `lm-chat-setup-<версия>.exe` — обязателен для Windows;
   - при желании `lm-chat-arm64-v8a.apk`, `lm-chat-armeabi-v7a.apk`,
     `lm-chat-x86_64.apk`, `lm-chat-windows-x64.zip`.
8. В описании релиза добавить блок `SHA-256`:

   ```text
   SHA-256
   lm-chat-universal.apk  <хеш>
   lm-chat-setup-1.8.9.exe  <хеш>
   ```

   Приложение использует `digest` из метаданных GitHub, а если его нет —
   этот блок.

9. Проверить обновление с предыдущей версии на Android и Windows.

## CI

| Workflow | Что делает |
|---|---|
| `CI` | `dart format`, `flutter analyze`, тесты, сборка debug APK |
| `Secret scan` | gitleaks |
| `CodeQL` | анализ Python (скрипты мостика) |
| `Security` | OSV-скан зависимостей, dependency review, SBOM |

Секреты (`key.properties`, keystore, сертификаты) в репозиторий не попадают.
Для CI-сборки с подписью используйте GitHub Secrets, а не файлы в репозитории.
