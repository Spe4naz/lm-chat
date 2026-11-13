# Мостик к `lms`

Мостик — необязательный HTTP-сервис на машине с LM Studio. Он выполняет
`lms load` / `lms unload` от вашего имени и умеет держать генерацию на сервере,
пока телефон сворачивает приложение.

Зачем он нужен:

- принудительный оффлоад (`--gpu max`, `--gpu 0.50`, `--gpu off`), которого нет
  в REST-API LM Studio;
- оценка памяти до загрузки (`lms load --estimate-only`);
- задания чата `POST /chat`, которые продолжаются после потери связи.

## Установка

```bash
sudo mkdir -p /opt/lm-gpu-bridge
sudo cp tools/lms_gpu_bridge.py /opt/lm-gpu-bridge/
BRIDGE_TOKEN='длинный-случайный-токен' python3 /opt/lm-gpu-bridge/lms_gpu_bridge.py
```

Без `BRIDGE_TOKEN` мостик откажется слушать `0.0.0.0`. Пустой токен разрешён
только на loopback (`BRIDGE_HOST=127.0.0.1`).

Проверка:

```bash
curl http://127.0.0.1:1235/health

curl -X POST http://192.168.1.50:1235/load \
  -H 'Authorization: Bearer <BRIDGE_TOKEN>' \
  -H 'Content-Type: application/json' \
  -d '{"model":"google/gemma-3n-e4b","gpu":"max","context_length":8192}'
```

Самопроверка без LM Studio:

```bash
python3 tools/test_lms_gpu_bridge.py
```

## Автозапуск

В `tools/lms-gpu-bridge.service` замените `__USER__` на пользователя, который
запускает LM Studio, создайте файл с токеном и установите сервис:

```bash
sudo sh -c 'umask 077; echo "BRIDGE_TOKEN=$(openssl rand -hex 32)" > /etc/lm-gpu-bridge.env'
sudo cp tools/lms-gpu-bridge.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now lms-gpu-bridge
sudo systemctl status lms-gpu-bridge
```

Токен лежит в `/etc/lm-gpu-bridge.env` (только root, `chmod 600`). Не
коммитьте его в git.

## Эндпоинты

| Метод | Путь | Назначение |
|---|---|---|
| GET | `/health` | проверка живости |
| GET | `/ps` | запущенные модели |
| POST | `/load` | `lms load` с `gpu`, `context_length`, `ttl` |
| POST | `/unload` | `lms unload` |
| POST | `/estimate` | `lms load --estimate-only` |
| POST | `/chat` | задание чата, токены буферизуются на сервере |
| GET | `/chat/<id>?since=N&wait=С` | long-poll событий задания |
| POST | `/chat/<id>/cancel` | отменить задание |

Все запросы, кроме `/health`, требуют `Authorization: Bearer <токен>`.

## Подключение в приложении

**Настройки → сервер → Изменить → «Включить мост»**. Адрес вводить не нужно:
приложение берёт адрес LM Studio и подставляет порт `1235`. Остаётся ввести
токен моста и при желании включить «Чат через мост».

Когда мостик задан:

- «Загрузить / Перезагрузить» и автозагрузка идут через `POST /load`;
- «Выгрузить» сначала пробует REST, при ошибке — `POST /unload`;
- `100%` → `--gpu max`, `CPU` → `--gpu off`, `25/50/75%` → `--gpu 0.25/…`;
- контекст и TTL передаются в `--context-length` и `--ttl`;
- «Авто» не передаёт `--gpu`;
- появляется кнопка «Оценить память»;
- Flash Attention, KV-кэш и batch size через мостик не передаются — задайте их
  в LM Studio.

Если мостик вернул ошибку (например, не хватило VRAM), приложение показывает
текст ошибки и **не** грузит модель молча через REST.

## Генерация в фоне

При включённом «Чат через мостик» запрос уходит в `POST /chat`, мостик читает
SSE и складывает токены в буфер. Приложение забирает их long-poll-запросами и
после возврата из фона дочитывает пропущенные события по `seq`.

- ответ генерируется на сервере и не зависит от телефона;
- свернул приложение, потерял Wi-Fi, убил процесс — генерация продолжается;
- сохранённый `jobId` позволяет догрузить ответ при следующем запуске;
- задания живут в памяти: после перезапуска мостика они теряются (TTL 60 минут);
- если мостик старый и `/chat` отвечает 404, приложение переключается на прямой
  стрим и предлагает обновить `lms_gpu_bridge.py`.

## Переменные

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `LMS_BIN` | `lms` | путь к CLI `lms` |
| `LMS_API_KEY` | пусто | токен LM Studio, если включён |
| `LMS_HOST` | `127.0.0.1:1234` | LM Studio на другом компьютере |
| `BRIDGE_HOST` | `0.0.0.0` | адрес мостика |
| `BRIDGE_PORT` | `1235` | порт мостика |
| `BRIDGE_LOAD_TIMEOUT` | 900 | сколько ждать загрузку модели |
| `BRIDGE_CHAT_TIMEOUT` | 1800 | сколько ждать токены от LM Studio |
| `BRIDGE_JOB_TTL` | 3600 | сколько хранить готовое задание |
| `BRIDGE_MAX_JOBS` | 8 | максимум заданий в памяти |
| `BRIDGE_MAX_EVENTS` | 20000 | максимум событий в задании |
| `BRIDGE_MAX_JOB_BYTES` | 67108864 | суммарный размер тел заданий |
| `BRIDGE_READ_TIMEOUT` | 30 | таймаут чтения тела запроса, секунды |
| `BRIDGE_MAX_LMS_OUTPUT` | 1048576 | максимум вывода `lms` |
| `BRIDGE_MAX_BODY` | 33554432 | максимальный размер тела (изображения) |

## LM Studio требует токен

Если в LM Studio включено **Require Authentication**, мостик должен
аутентифицироваться сам: он вызывает `/v1/chat/completions` от своего имени.
Без `LMS_API_KEY` LM Studio отвечает `401` и сообщает, что заголовок
`Authorization` не передан.

Варианты:

1. **Отключить «Чат через мост»** в настройках сервера. Приложение пойдёт в
   LM Studio напрямую и передаст токен из профиля. Свежие сборки делают это
   автоматически после первого `401` от мостика и показывают уведомление.
2. **Задать токен мостику**:

   ```bash
   sudo systemctl edit lms-gpu-bridge.service
   ```

   ```ini
   [Service]
   Environment="LMS_API_KEY=<токен LM Studio>"
   ```

   ```bash
   sudo systemctl restart lms-gpu-bridge
   ```

Загрузка моделей (`/load`) токен не требует: мостик вызывает CLI `lms`.

## Ограничения

- Это отдельный процесс, его нужно обновлять вместе с приложением: новые
  эндпоинты появляются в новых версиях `lms_gpu_bridge.py`.
- Токен моста хранится в защищённом хранилище приложения, но передаётся по LAN
  в cleartext — как и остальной трафик.
- Мостик выполняет `lms` с правами своего пользователя. Не открывайте порт в
  интернет.
