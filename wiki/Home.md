# LM Chat

Клиент для **LM Studio** на Android и Windows. Модель работает на вашем
компьютере, а приложение общается с ней по локальной сети: без облака, без
аккаунтов и без отправки чатов наружу.

- Репозиторий: <https://github.com/Spe4naz/lm-chat>
- Плагин доступа модели к компьютеру: <https://github.com/Spe4naz/lm-computer>
- Полный список возможностей: [README](https://github.com/Spe4naz/lm-chat#readme)

## Быстрый старт

| Шаг | Что сделать |
|---|---|
| 1 | В LM Studio: **Developer → Start Server**, включить **Serve on Local Network** |
| 2 | Установить приложение: APK на Android или установщик на Windows — см. [Installation](https://github.com/Spe4naz/lm-chat/wiki/Installation) |
| 3 | Ввести адрес сервера, например `http://192.168.1.50:1234` — без `/v1` |
| 4 | Если в LM Studio включена авторизация, вставить API-токен |
| 5 | Нажать «Проверить подключение», выбрать модель и писать |

Телефон и компьютер должны быть в одной сети. HTTP разрешён только для
локальных адресов; для внешнего endpoint нужен HTTPS или Tailscale
(см. [Security](https://github.com/Spe4naz/lm-chat/wiki/Security)).

## Страницы

| Страница | О чём |
|---|---|
| [Installation](https://github.com/Spe4naz/lm-chat/wiki/Installation) | Установка на Android и Windows, первый запуск, где лежат данные |
| [Updating](https://github.com/Spe4naz/lm-chat/wiki/Updating) | Как обновить приложение и почему обновление иногда не ставится |
| [LM-Studio](https://github.com/Spe4naz/lm-chat/wiki/LM-Studio) | Настройка сервера LM Studio, контекст, GPU, headless |
| [Bridge](https://github.com/Spe4naz/lm-chat/wiki/Bridge) | Мостик к `lms`: принудительный оффлоад, генерация в фоне |
| [FAQ](https://github.com/Spe4naz/lm-chat/wiki/FAQ) | Короткие ответы: «как обновить плагин», «почему не на 100% GPU» и т. п. |
| [Troubleshooting](https://github.com/Spe4naz/lm-chat/wiki/Troubleshooting) | Что проверить, если нет связи, обрывается ответ, не ставится обновление |
| [Security](https://github.com/Spe4naz/lm-chat/wiki/Security) | Модель безопасности, токены, cleartext HTTP, проверка обновлений |
| [Building](https://github.com/Spe4naz/lm-chat/wiki/Building) | Сборка APK и EXE, подпись, чек-лист релиза |

## Версии и совместимость

- Приложение: Flutter 3.47+, Android 7.0+ (API 24), Windows 10/11 x64.
- LM Studio 0.4+ — нативные методы `/api/v1/*`; на более старых версиях
  приложение откатывается к `/v1/models` и JIT-загрузке.
- Плагин `lm-computer` необязателен: без него чат работает, но модель не
  получает доступ к компьютеру.

Страницы этой вики хранятся в репозитории в каталоге
[`wiki/`](https://github.com/Spe4naz/lm-chat/tree/main/wiki) — правки удобнее
делать там, а затем публиковать в вики.
