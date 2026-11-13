# TODO

Текущая версия: **1.8.3**, плагин **0.1.5**.

P0 и P1 закрыты в исходниках, большинство P2 — тоже. Ниже только открытые
задачи; выполненное вынесено в конец файла.

## Открытые задачи

### P1 — безопасность и выпуск

- [ ] **Полностью закрыть cleartext на Android.** Сейчас
      `usesCleartextTraffic="true"` остаётся, потому что Android Network
      Security Config не поддерживает CIDR, а приложению нужны произвольные
      LAN-IP по HTTP. Публичный HTTP уже отклоняется в `ServerConfig` до
      открытия сокета, но манифест всё ещё разрешает cleartext для любого кода
      внутри приложения. Полное решение: HTTPS или локальный reverse proxy для
      LM Studio/мостика.

- [ ] **Подписать Windows-установщик.** Android уже подписан release-ключом, а
      сертификата для Windows нет: `lm-chat-setup-1.8.2.exe` опубликован без
      Authenticode, поэтому встроенное автообновление его отклоняет и
      Windows-пользователи ставят вручную. Нужен сертификат (или бесплатный
      вариант для OSS), затем `LMCHAT_SIGN_CERT` для
      `build_windows_installer.ps1`.

- [ ] **Обновить плагин на Ubuntu.** Хост `192.168.0.183` был недоступен;
      после включения: `cd ~/lm-computer && git pull && ./install.sh`, затем
      проверить `lm-computer.service` и порты `1236`/`1237`.

### P2 — зависимости и CI

- [ ] **`zod` 3 → 4.** `npm audit` показывает 2 high из-за
      `zod` 3 и транзитивного `@lmstudio/sdk` 2.1.0. Обновление заблокировано
      до версии SDK с поддержкой zod 4; пока размеры тел и аргументов
      ограничены в коде, а в `osv-scanner.toml` есть временное исключение
      GHSA-mrhx-c7xc-m3w5 до 2027-01-31.

- [ ] **Мажорные обновления Flutter-пакетов.** 12 пакетов имеют новые
      мажорные версии; обновлять по одному с прогоном `flutter test`.

- [ ] **Дозакрепить CI.** `permissions: contents: read`,
      `npm audit --omit=dev`, CodeQL, OSV, dependency review и SBOM добавлены.
      Осталось закрепить старые `ci.yml`/`secret-scan.yml` по commit SHA и
      добавить release-сборку APK с проверкой подписи.

- [ ] **Убрать предупреждение SmartScreen.** Подписать APK и Windows installer
      постоянным сертификатом (пересекается с задачей о release-подписи).

### P3 — позже

- [ ] Рассмотреть TLS/локальный reverse proxy для `1235`/`1236`/`1237`:
      сейчас токены и чат идут по LAN в cleartext.

- [ ] Проверить интерфейс на реальном Android: узкий экран, крупный системный
      шрифт, светлая тема, голосовой ввод.

### Новые возможности

- [ ] **Tool / function calling** и поддержка OpenAI-совместимых tools.
- [ ] **Дополнительные параметры генерации:** `seed`, `stop`,
      `presence_penalty`, `frequency_penalty`, `min_p`.
- [ ] **Сравнение моделей** side-by-side на одном запросе.
- [ ] **Локальный RAG** через embeddings-модели LM Studio.
- [ ] Показывать стоимость/энергопотребление ответа, если сервер отдаёт
      метрики.

## Сделано (архив)

### P0 — безопасность

- Обход workspace через dangling symlink: `PathGuard` проверяет `lstat`
  каждого несуществующего компонента, `fs_append` на Unix использует
  `O_NOFOLLOW`. Тесты: `test/paths.test.ts`.
- Сетевой слой приложения: `LmClient` проверяет base/bridge до сокета,
  `send()`/`_generate()` блокируют небезопасный сервер, импорт истории и
  профиля вырезает токены и пропускает небезопасные URL. Тесты:
  `test/security_test.dart`.
- Bridge URL: `bridgeSecurityError` проверяет мост отдельно,
  `bridgeUrlForBase()` не строит `http://` для публичного хоста.

### P1 — высокий приоритет

- `shell_run` получает только allowlist окружения (`PATH`, `HOME`, `LANG`,
  `TERM`, `TMPDIR`, display, системные пути Windows). `LMS_*`, proxy-
  переменные и `SSH_AUTH_SOCK` не передаются. `src/core/shell.ts`.
- `PUT /api/config` не может сменить workspace на `/` или symlink вне
  домашнего каталога/`LM_COMPUTER_ALLOWED_ROOTS`. Проверка выполняется до
  `mkdir`, ответ — `400`. `src/config.ts`, `src/core/service.ts`,
  `src/core/http.ts`.
- Подпись обновлений: release APK без `android/key.properties` не собирается,
  Android сверяет сертификат APK с установленным, Windows проверяет
  Authenticode, installer умеет подписываться через `signtool`.
- Denylist shell ловит `sudo`/`doas`/`pkexec` в любом месте строки, включая
  `/usr/bin/sudo`, `env sudo` и `bash -c 'sudo …'`; документация прямо
  называет denylist защитой от случайностей, а не sandbox.
- Импорт истории больше не доверяет серверам и токенам из файла.
- Release 1.8.2: keystore создан (RSA 4096, alias `lm-chat`, действителен до
  2054), APK собран и проверен `apksigner` (SHA-256 сертификата
  `EE:F4:4E:CB:45:6A:A3:CB:04:99:92:1F:E7:1C:96:9A:5F:75:0B:0B:D9:D0:8C:79:7B:C6:2E:39:4B:99:A1:FD`),
  релиз `v1.8.2` опубликован с `lm-chat-universal.apk`,
  `lm-chat-setup-1.8.2.exe` и portable ZIP.

### P2 — средний приоритет

- Python-мостик: лимиты `MAX_EVENTS`, `MAX_JOB_BYTES`, таймаут чтения тела,
  публичный `/health` без запуска `lms`, ограничение вывода `lms`, корректный
  разбор IPv6.
- Автообновление: allowlist имён APK/EXE, только HTTPS `github.com`, лимит
  400 МБ, проверка `Content-Length`, общий дедлайн, удаление частичного файла.
- `ComputerService.shutdown()` отменяет подтверждения, ждёт завершения
  shell-процессов и затем останавливает HTTP; используется в `standalone.ts` и
  `/api/shutdown`.
- Zenity: таймер перепроверяет активность приложения, пока запрос в очереди.
- Systemd: `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=full`,
  `ProtectControlGroups`, `ProtectKernelTunables`, `RestrictSUIDSGID`,
  `RestrictAddressFamilies`, `UMask=0077`. `ProtectKernelModules` и
  `ProtectClock` убраны: в `systemd --user` они дают
  `Failed to drop capabilities`.
- MCP-инструменты в приложении: при включённом переключателе чат идёт через
  нативный `/api/v1/chat` с `integrations`, инструменты выполняет LM Studio.
  Без моста и структурированного вывода. Тесты: `test/mcp_chat_test.dart`,
  страница вики `MCP`.
- Audit: маскирование bearer-токенов, паролей, API-ключей и URL userinfo;
  ротация `audit.jsonl` после 5 МБ.
- CORS выключен по умолчанию; Origin отражается только из
  `LM_COMPUTER_CORS_ORIGINS`.
- `fs_list` не следует symlink; `fs_move` обрабатывает `EXDEV`; `fs_search`
  ограничен 10 000 записей и 5 секундами.
- Приложение проверяет размер файла до `readAsBytes()` для шрифта, истории и
  профиля (лимит 32 МБ).
- `defaultMaxTokens` в профиле нормализуется: `<= 0` → `-1`, положительные
  значения ограничены 131072.
- Односоставное имя хоста больше не считается локальным: `http://ubuntu`
  отклоняется, `http://ubuntu.local` — нет.
- `vitest` обновлён до 5.1.0, critical `tinypool` закрыт.
- Добавлены тесты на symlink, `securityError`, импорт серверов, лимиты
  обновлений, workspace, shell env, audit и CORS.

### P3 — безопасность и CI

- `lib/custom_font.dart`: имена файлов шрифтов проверяются по строгому
  шаблону, `..`, разделители, не-TTF и symlink отклоняются; путь обязан
  оставаться внутри `fonts/`. Тест: `test/custom_font_test.dart`.
- В оба репозитория добавлены CodeQL, OSV-скан зависимостей,
  dependency review для PR и SBOM:
  - `lm-chat`: CodeQL (Python), OSV, SPDX SBOM через `anchore/sbom-action`;
  - `lm-computer`: CodeQL (JavaScript/TypeScript), OSV, CycloneDX SBOM через
    `npm sbom`.
- GitHub Actions в новых workflow закреплены по commit SHA (кроме
  `dependency-review-action` и `sbom-action`, которые используют major-тег).

### Проверки на 2026-11-13

- `flutter analyze` — без замечаний;
- `flutter test` — **171/171**;
- плагин: `npm run build`, `npm test` — **43/43**;
- Python: `pytest tools/test_lms_gpu_bridge.py` — **19/19**;
- `flutter build apk --debug` — успешно;
- `flutter build apk --release` — успешно с release-keystore, `apksigner` OK;
- `flutter build windows --release` + Inno Setup — `lm-chat-setup-1.8.2.exe`;
- `npm audit`: 2 high (`zod` 3 и `@lmstudio/sdk`), критичных нет.

Пути `src/core/...`, `install.sh`, `start.sh`, `stop.sh` и `prompts/...`
относятся к отдельному репозиторию `tools/lm-computer-plugin`.
