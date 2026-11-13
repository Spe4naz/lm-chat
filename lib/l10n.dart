/// Minimal runtime localization for LM Chat.
///
/// Strings are keyed by their Russian source text. Widgets use [L10nText],
/// which translates `Text.data` automatically; non-widget code calls [t] or
/// [tf]. Russian is always the fallback, so missing translations never break
/// the UI.
class L10n {
  L10n._();

  static String _language = 'ru';

  static String get language => _language;

  static bool get isEnglish => _language == 'en';

  static final Map<String, String> _cache = {};

  static void setLanguage(String code) {
    _language = code.toLowerCase().startsWith('en') ? 'en' : 'ru';
    _cache.clear();
  }

  /// Translates a static string or, for concatenated/dynamic text, replaces
  /// known Russian fragments. Results are cached per string.
  static String t(String ru) {
    if (!isEnglish) return ru;
    final exact = _en[ru];
    if (exact != null) return exact;
    final cached = _cache[ru];
    if (cached != null) return cached;

    var value = ru;
    for (final key in _fragments) {
      if (value.contains(key)) {
        value = value.replaceAll(key, _en[key]!);
      }
    }
    _cache[ru] = value;
    return value;
  }

  /// Fragments safe to replace inside longer messages: phrases, not single
  /// short words that could occur inside another word.
  static final List<String> _fragments =
      (_en.keys
          .where(
            (key) =>
                key.length >= 6 &&
                (key.contains(' ') ||
                    key.endsWith(':') ||
                    key.endsWith('.') ||
                    key.endsWith('!') ||
                    key.endsWith('…')),
          )
          .toList()
        ..sort((a, b) => b.length.compareTo(a.length)));

  /// Translates a template and replaces `{name}` placeholders.
  static String tf(String ru, [Map<String, Object?> args = const {}]) {
    var value = t(ru);
    for (final entry in args.entries) {
      value = value.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return value;
  }

  static const Map<String, String> _en = {
    // ------------------------------------------------------------ navigation
    'Новый чат': 'New chat',
    'Показать чаты': 'Show chats',
    'Скрыть список чатов': 'Hide chat list',
    'Изменить ширину списка чатов': 'Resize the chat list',
    'Свернуть сайдбар': 'Toggle sidebar',
    'Список чатов на широком экране можно свернуть кнопкой в его заголовке или через Ctrl+B. Ширина меняется перетаскиванием края, двойной щелчок сбрасывает её.': 'On a wide window the chat list can be collapsed with the button in its header or with Ctrl+B. Drag its edge to resize; double-click the edge to reset the width.',
    'ЧАТЫ': 'CHATS',
    'АРХИВ': 'ARCHIVE',
    'Архив': 'Archive',
    'К активным': 'Back to chats',
    'Поиск по чатам и сообщениям': 'Search chats and messages',
    'Очистить': 'Clear',
    'Ничего не найдено': 'Nothing found',
    'Пока нет чатов': 'No chats yet',
    'Архив пуст': 'Archive is empty',
    'модель не выбрана': 'no model selected',
    'Серверы и настройки': 'Servers and settings',
    'Серверы и параметры по умолчанию': 'Servers and default parameters',
    'Экспорт всех чатов': 'Export all chats',
    'Все чаты в Markdown': 'All chats as Markdown',
    'Импорт истории': 'Import history',
    'Объединить с текущими чатами из JSON':
        'Merge with current chats from JSON',
    'Настройки': 'Settings',
    'Диагностика': 'Diagnostics',
    'Серверы': 'Servers',
    'Сервер': 'Server',
    'Мостик': 'Bridge',
    'Модель': 'Model',
    'Моделей': 'Models',
    'Моделей: {count}': 'Models: {count}',
    'Моделей в кэше': 'Models in cache',
    'Версия': 'Version',
    'Пока нет записей': 'No entries yet',

    // ------------------------------------------------------------ actions
    'Прикрепить изображение': 'Attach image',
    'Модель не поддерживает изображения': 'The model does not support images',
    'Выберите изображения': 'Select images',
    'Изображение': 'Image',
    'Изображение: {name}': 'Image: {name}',
    'Изображение слишком большое: {name}': 'Image is too large: {name}',
    'Не удалось открыть изображение: {error}':
        'Could not open the image: {error}',
    'Можно прикрепить не более 4 изображений': 'You can attach up to 4 images',
    'Открыть изображение': 'Open image',
    'Из библиотеки': 'From library',
    'Удалить чат': 'Delete chat',
    'Выбрать сообщения': 'Select messages',
    'Выбрать сообщение': 'Select message',
    'Выбрано: {count}': 'Selected: {count}',
    'Снять выбор': 'Deselect all',
    'Копировать выбранное': 'Copy selected',
    'Экспорт выбранного': 'Export selected',
    'Выбранные сообщения': 'Selected messages',
    'из {count}': 'of {count}',
    'Скопировано сообщений: {count}': 'Copied messages: {count}',
    'Экспорт JSON': 'Export JSON',
    'Экспорт Markdown': 'Export Markdown',
    'Экспорт статистики CSV': 'Export statistics CSV',
    'Отправить': 'Send',
    'Остановить': 'Stop',
    'Сохранить': 'Save',
    'Применить': 'Apply',
    'Отмена': 'Cancel',
    'Удалить': 'Delete',
    'Изменить': 'Edit',
    'Переименовать': 'Rename',
    'Повторить': 'Retry',
    'Повторить ответ': 'Regenerate answer',
    'Сгенерировать заново': 'Regenerate',
    'Продолжить ответ': 'Continue answer',
    'Догрузить ответ': 'Resume answer',
    'Копировать': 'Copy',
    'Копировать чат': 'Copy chat',
    'Копировать код': 'Copy code',
    'Копировать команду': 'Copy command',
    'Скопировано': 'Copied',
    'Код скопирован': 'Code copied',
    'Команда скопирована': 'Command copied',
    'Чат скопирован': 'Chat copied',
    'Лог скопирован': 'Log copied',
    'Скопировать лог': 'Copy log',
    'Очистить лог': 'Clear log',
    'Очистить чат': 'Clear chat',
    'Сбросить': 'Reset',
    'Готово': 'Done',
    'Закрыть': 'Close',
    'ОК': 'OK',
    'Проверить': 'Test',
    'Проверить подключение': 'Test connection',
    'Проверяю подключение…': 'Testing connection…',
    'Настроить позже': 'Set up later',
    'Подключиться': 'Connect',
    'Сохранить без проверки': 'Save without testing',
    'Добавить сервер': 'Add server',
    'Сделать активным': 'Make active',
    'Выгрузить': 'Unload',
    'Загрузить': 'Load',
    'Перезагрузить': 'Reload',
    'Автовыгрузка простоя (TTL)': 'Idle unload (TTL)',
    'Передача на GPU': 'GPU offload',
    'Параметры загрузки': 'Loading parameters',
    'Оценить память': 'Estimate memory',
    'Оценка памяти': 'Memory estimate',
    'Обновить': 'Refresh',
    'Обновить список': 'Refresh list',
    'Обновить состояние': 'Refresh state',
    'Выбрать все': 'Select all',
    'Снять все': 'Deselect all',
    'Импортировать ({count})': 'Import ({count})',
    'Выберите чаты': 'Select chats',

    // ------------------------------------------------------------ voice input
    'Голосовой ввод': 'Voice input',
    'Остановить голосовой ввод': 'Stop voice input',
    'Слушаю…': 'Listening…',
    'Стоп': 'Stop',
    'Распознавание речи недоступно. Установите сервис распознавания Google или включите микрофон в настройках.': 'Speech recognition is unavailable. Install the Google speech service or enable the microphone in settings.',
    'Не удалось начать распознавание речи: {error}':
        'Could not start speech recognition: {error}',
    'Речь не распознана. Попробуйте ещё раз.':
        'No speech recognized. Try again.',
    'Сервис распознавания недоступен. Проверьте подключение к сети.':
        'The speech service is unavailable. Check your network connection.',
    'Не удалось записать звук. Проверьте микрофон.':
        'Could not record audio. Check the microphone.',
    'Нет доступа к микрофону. Разрешите его в настройках приложения.':
        'No microphone access. Allow it in the app settings.',
    'Этот язык не поддерживается распознаванием речи.':
        'This language is not supported by speech recognition.',
    'Распознавание уже запущено.': 'Speech recognition is already running.',
    'Ошибка распознавания речи: {code}': 'Speech recognition error: {code}',

    // -------------------------------------------------- structured responses
    'Формат ответа': 'Response format',
    'Обычный текст': 'Plain text',
    'JSON по схеме': 'JSON by schema',
    'Модель вернёт только JSON-объект.':
        'The model will return a JSON object only.',
    'JSON Schema. LM Studio превращает её в грамматику для GGUF-моделей.':
        'JSON Schema. LM Studio turns it into a grammar for GGUF models.',
    'GBNF-грамматика. Поддерживается llama.cpp-совместимыми серверами; LM Studio может проигнорировать это поле.': 'GBNF grammar. Supported by llama.cpp-compatible servers; LM Studio may ignore this field.',
    'Пример': 'Example',
    'Введите JSON-схему ответа': 'Enter a response JSON schema',
    'Схема ответа — некорректный JSON': 'The response schema is not valid JSON',
    'Введите GBNF-грамматику': 'Enter a GBNF grammar',

    // ------------------------------------------------------------ chat UI
    'Запуск модели': 'Model launch',
    'Параметры чата': 'Chat parameters',
    'Параметры по умолчанию': 'Default parameters',
    'Параметры сохраняются сразу и применяются при следующей отправке.':
        'Parameters are saved immediately and applied to the next message.',
    'Загрузка модели по требованию': 'Load model on demand',
    'Отправлять запрос сразу, не проверяя память заранее:':
        'Send the request immediately without checking memory first:',
    'Контекст и загрузка': 'Context and loading',
    'Контекстное окно': 'Context window',
    'Контекст модели': 'Model context',
    'Длина ответа': 'Response length',
    'Креативность ответов': 'Response creativity',
    'Разнообразие выбора токенов': 'Token sampling diversity',
    'Тема приложения': 'App theme',
    'Системная': 'System',
    'Светлая': 'Light',
    'Тёмная': 'Dark',
    'Шрифт интерфейса': 'Interface font',
    'Свой TTF-шрифт': 'Custom TTF font',
    'Свой шрифт': 'Custom font',
    'Файл хранится только на этом устройстве':
        'The file is stored only on this device',
    'Используется': 'In use',
    'Нажмите, чтобы применить': 'Tap to apply',
    'Импорт': 'Import',
    'Заменить шрифт': 'Replace font',
    'Удалить шрифт': 'Delete font',
    'Шрифт добавлен': 'Font added',
    'Шрифт удалён': 'Font deleted',
    'Удалить шрифт?': 'Delete the font?',
    'Файл будет удалён с этого устройства, интерфейс вернётся к системному шрифту.': 'The file will be deleted from this device and the interface will use the system font.',
    'Выберите TTF-шрифт': 'Choose a TTF font',
    'Файл шрифта пуст': 'The font file is empty',
    'Файл шрифта слишком большой (максимум 32 МБ)':
        'The font file is too large (32 MB maximum)',
    'Не удалось импортировать шрифт: {error}':
        'Could not import the font: {error}',
    'Размер текста': 'Text size',
    'Плотность интерфейса': 'Interface density',
    'Обычная': 'Normal',
    'Компактная': 'Compact',
    'Шрифт кода': 'Code font',
    'Вчера': 'Yesterday',
    'Нет сообщений': 'No messages',
    'Параметры генерации': 'Generation parameters',
    'ток.': 'tok.',
    'без системного промпта': 'no system prompt',
    'есть системный промпт': 'system prompt set',
    'Подключение к LM Studio': 'Connect to LM Studio',
    'Укажите адрес компьютера в локальной сети.':
        'Enter the address of a computer on your local network.',
    'Без облака и аккаунтов': 'No cloud and no accounts',
    'Работает в локальной сети и через Tailscale':
        'Works on a local network and over Tailscale',
    'История, параметры и промпты остаются на устройстве':
        'History, settings and prompts stay on the device',
    'Значения применяются к новым сообщениям': 'Values apply to new messages',
    'Сейчас:': 'Now:',
    'Авто': 'Auto',
    'Своё': 'Custom',
    'Вкл': 'On',
    'Выкл': 'Off',
    'включено': 'on',
    'выключено': 'off',
    'авто': 'auto',
    'В памяти': 'In memory',
    'В памяти модели': 'Model in memory',
    'не загружена': 'not loaded',
    'Загружена': 'Loaded',
    'Загружена с контекстом': 'Loaded with context',
    'Максимум модели': 'Model maximum',
    'Например: отвечай кратко и по-русски':
        'For example: answer briefly in Russian',
    'Токенов': 'Tokens',
    'например 12288': 'e.g. 12288',
    'Контекст:': 'Context:',
    'осталось': 'remaining',
    'из': 'of',
    'занято': 'used',
    'лимит': 'limit',
    'источник': 'source',
    'запрос': 'request',
    'ответ': 'answer',
    'системный промпт': 'system prompt',
    'сообщения': 'messages',
    'ответ модели': 'model answer',
    'Контекст занят': 'Context used',
    'Осталось контекста': 'Context remaining',
    'Лимит из': 'Limit from',
    'Токены запроса': 'Prompt tokens',
    'Токены ответа': 'Completion tokens',
    'Всего токенов': 'Total tokens',
    'Первый токен': 'First token',
    'Скорость': 'Speed',
    'Время': 'Time',
    'Вариант': 'Variant',
    'Варианты ответа': 'Answer variants',
    'Статистика ответа': 'Answer statistics',
    'Статистика': 'Statistics',
    'Модель печатает…': 'Model is typing…',
    'Сообщение': 'Message',
    'Текст сообщения': 'Message text',
    'Текст ответа': 'Answer text',
    'Размышления': 'Reasoning',
    'Показать размышления': 'Show reasoning',
    'Скрыть размышления': 'Hide reasoning',
    'изменено': 'edited',
    'в памяти': 'in memory',
    'активный': 'active',
    'Не удалось': 'Failed',
    'Ошибка': 'Error',
    'Остановлено': 'Stopped',
    'Продолжение остановлено': 'Continuation stopped',
    'Модель не продолжила ответ': 'The model did not continue the answer',
    'Модель вернула пустой ответ': 'The model returned an empty answer',
    'Новый вариант не получен': 'No new variant received',
    'Нет связи с сервером': 'No connection to the server',
    'Подключение восстановлено': 'Connection restored',
    'Ответ прерван': 'Answer interrupted',
    'Продолжить можно только последний ответ':
        'Only the last answer can be continued',
    'Сначала добавьте сервер в настройках': 'Add a server in settings first',
    'Выберите модель': 'Select a model',
    'Ответ не может быть пустым': 'Answer cannot be empty',
    'Сообщение не может быть пустым': 'Message cannot be empty',
    'Запрос не помещается в контекст':
        'The request does not fit into the context',
    'Отправить всё равно?': 'Send anyway?',
    'Импортировано чатов:': 'Imported chats:',
    'серверов:': 'servers:',
    'промптов:': 'prompts:',
    'Импортировано чатов: {count}': 'Imported chats: {count}',
    'Импорт отменён': 'Import cancelled',
    'Не удалось прочитать файл': 'Could not read the file',
    'Не выбран ни один чат': 'No chat selected',
    'В файле не найдено ни одного чата': 'No chats found in the file',
    'Корень JSON должен быть объектом': 'JSON root must be an object',

    // ------------------------------------------------------------ dialogs
    'Название чата': 'Chat name',
    'Название': 'Name',
    'Удалить чат?': 'Delete chat?',
    'Удалить сервер?': 'Delete server?',
    'Удалить сообщение?': 'Delete message?',
    'Удалить шаблон?': 'Delete template?',
    'Удалить вариант': 'Delete variant',
    '«{title}» будет удалён без возможности отмены.':
        '“{title}” will be deleted without the possibility of undo.',
    '«{name}» будет удалён из списка.':
        '“{name}” will be removed from the list.',
    '«{name}» будет удалён из списка. История чатов сохранится.':
        '“{name}” will be removed from the list. Chat history will be kept.',
    '«{name}» будет удалён.': '“{name}” will be deleted.',
    'Вместе с ним будут удалены сохранённые варианты ответа':
        'Saved answer variants will be deleted with it',
    'Прежний текст сохранится как отдельный вариант.':
        'The previous text will be kept as a separate variant.',
    '«Сохранить и ответить» удалит все сообщения после этого и':
        '“Save and answer” will delete all messages after this one and',
    'сгенерирует новый ответ.': 'generate a new answer.',
    'Редактировать ответ': 'Edit answer',
    'Редактировать сообщение': 'Edit message',
    'Редактировать': 'Edit',
    'Действия': 'Actions',
    'Сохранить и ответить': 'Save and answer',
    'Сообщение занимает примерно': 'The message takes approximately',
    'токенов,': 'tokens,',
    'а свободно': 'and',
    'свободно из': 'free of',
    'Модель может обрезать ответ или запрос.':
        'The model may truncate the answer or request.',

    // ------------------------------------------------------------ settings
    'Запуск модели по умолчанию': 'Default model launch',
    'Оформление': 'Appearance',
    'Как подключить LM Studio': 'How to connect LM Studio',
    'Новый сервер': 'New server',
    'Изменить сервер': 'Edit server',
    'Мостик GPU - необязательно': 'GPU bridge — optional',
    'Пока нет ни одного сервера.\nДобавьте адрес LM Studio.':
        'No servers yet.\nAdd the LM Studio address.',
    'Сервер не вернул ни одной модели.\nЗагрузите модель в LM Studio.':
        'The server returned no models.\nLoad a model in LM Studio.',
    'Не удалось получить список моделей.': 'Could not fetch the model list.',
    'Очистить историю': 'Clear history',
    'Промпты': 'Prompts',
    'Библиотека промптов': 'Prompt library',
    'Встроенные шаблоны системного промпта и свои':
        'Built-in and custom system prompt templates',
    'Профиль настроек': 'Settings profile',
    'Экспорт профиля': 'Export profile',
    'Импорт профиля': 'Import profile',
    'Серверы, параметры, оформление и промпты — без токенов':
        'Servers, parameters, appearance and prompts — no tokens',
    'Перенести настройки с другого устройства':
        'Move settings from another device',
    'Профиль с другого устройства': 'Profile from another device',
    'Серверов: {servers} · промптов: {prompts}':
        'Servers: {servers} · prompts: {prompts}',
    'Что перенести': 'What to transfer',
    'Серверы и адреса': 'Servers and addresses',
    'Оформление и язык': 'Appearance and language',
    'Пользовательские промпты': 'Custom prompts',
    'Temperature, top-p, контекст и системный промпт':
        'Temperature, top-p, context and system prompt',
    'Temperature, top-p, top-k, repeat penalty и системный промпт':
        'Temperature, top-p, top-k, repeat penalty and system prompt',
    'Тема, шрифт и размер текста': 'Theme, font and text size',
    'Тема, шрифт, плотность и размер текста':
        'Theme, font, density and text size',
    '{count} промпт(ов)': '{count} prompt(s)',
    'Токены доступа не входят в профиль. После импорта введите их заново на этом устройстве.': 'Access tokens are not part of the profile. Enter them again on this device after importing.',
    'Импортировать': 'Import',
    'Выберите раздел': 'Select a section',
    'Профиль сохранён': 'Profile saved',
    'Не удалось прочитать профиль': 'Could not read the profile',
    'Не удалось прочитать профиль: {error}':
        'Could not read the profile: {error}',
    'Не удалось сохранить профиль: {error}':
        'Could not save the profile: {error}',
    'Безопасное хранилище недоступно: токены не сохранятся после перезапуска.':
        'Secure storage is unavailable: tokens will not survive a restart.',
    'Не удалось сохранить токены в безопасном хранилище.':
        'Could not save tokens to secure storage.',
    'Не удалось удалить токены из истории: {error}':
        'Could not remove tokens from the history: {error}',
    'Обновления': 'Updates',
    'Проверять обновления': 'Check for updates automatically',
    'Автоматически раз в несколько часов через GitHub Releases':
        'Automatically every few hours via GitHub Releases',
    'Проверить обновления': 'Check for updates',
    'Проверка обновлений…': 'Checking for updates…',
    'Доступна версия {version}': 'Version {version} is available',
    'Проверить наличие новой версии': 'Check for a new version',
    'Обновлений нет': 'You are up to date',
    'Доступно обновление {version}': 'Update available: {version}',
    'Обновить приложение': 'Update app',
    'Позже': 'Later',
    'Обновление LM Chat': 'LM Chat update',
    'Новая версия: {version}': 'New version: {version}',
    'Текущая версия: {version}': 'Current version: {version}',
    'Заметки к релизу': 'Release notes',
    'Скачивание: {percent}%': 'Downloading: {percent}%',
    'Установка…': 'Installing…',
    'Скачать и установить': 'Download and install',
    'Файл скачивается с GitHub и проверяется по SHA-256 перед установкой.': 'The file is downloaded from GitHub and verified with SHA-256 before installation.',
    'Не удалось применить профиль: {error}':
        'Could not apply the profile: {error}',
    'Это не файл профиля LM Chat': 'This is not an LM Chat profile file',
    'В файле нет настроек профиля': 'The file has no profile settings',
    'Не выбран ни один раздел': 'No section selected',
    'Профиль применён': 'Profile applied',
    'новых серверов: {count}': 'new servers: {count}',
    'обновлено серверов: {count}': 'servers updated: {count}',
    'Горячие клавиши': 'Keyboard shortcuts',
    'Поиск по чатам': 'Search chats',
    'Остановить ответ': 'Stop answer',
    'Фон и генерация': 'Background and generation',
    'Продолжать в фоне': 'Continue in background',
    'Foreground-сервис не даёт Android заморозить ответ.':
        'A foreground service prevents Android from freezing the answer.',
    'Foreground-сервис не даёт Android заморозить ответ. На Xiaomi/Redmi/POCO также включите «Автозапуск» и «Без ограничений» в настройках батареи.': 'A foreground service prevents Android from freezing the answer. On Xiaomi/Redmi/POCO also enable Autostart and No restrictions in battery settings.',
    'Генерация': 'Generation',
    'Задания на мостике': 'Bridge jobs',
    'Если у сервера указан мостик, ответ готовится на Ubuntu.':
        'If the server has a bridge, the answer is generated on Ubuntu.',
    'Сворачивание, потеря Wi-Fi и закрытие приложения его не':
        'Minimizing, losing Wi-Fi and closing the app do not',
    'прерывают — при возврате текст догружается.':
        'interrupt it — the text is resumed on return.',
    'Последние запросы, ошибки и состояние сервера':
        'Recent requests, errors and server state',
    'Адрес': 'Address',
    'API-токен (если включён)': 'API token (if enabled)',
    'API-токен (необязательно)': 'API token (optional)',
    'Адрес мостика': 'Bridge address',
    'Токен мостика (BRIDGE_TOKEN)': 'Bridge token (BRIDGE_TOKEN)',
    'Мост GPU — необязательно': 'GPU bridge — optional',
    'Включить мост': 'Enable bridge',
    'Мост включён': 'Bridge enabled',
    'Отключить': 'Disable',
    'Адрес моста: {url}': 'Bridge address: {url}',
    'Токен моста (BRIDGE_TOKEN)': 'Bridge token (BRIDGE_TOKEN)',
    'Оставьте пустым, если на сервере не задан BRIDGE_TOKEN.':
        'Leave empty if BRIDGE_TOKEN is not set on the server.',
    'Чат через мост': 'Chat via bridge',
    'Сначала укажите адрес сервера': 'Enter the server address first',
    'Укажите адрес сервера': 'Enter the server address',
    'Позволяет грузить все слои на GPU через lms load.':
        'Allows loading all layers on GPU via lms load.',
    'Чат через мостик': 'Chat via bridge',
    'Ответ готовится на сервере и не обрывается в фоне.': 'The answer is generated on the server and is not interrupted in the background.',
    'Нужен обновлённый lms_gpu_bridge.py.':
        'An updated lms_gpu_bridge.py is required.',
    'Адрес LM Studio': 'LM Studio address',
    'Работает только в локальной сети': 'Works on the local network only',
    'MCP-инструменты': 'MCP tools',
    'Модель вызывает инструменты плагина (файлы, команды). '
            'Нужен LM Studio 0.4+, API-токен и разрешение на серверы '
            'из mcp.json. Чат через мост и структурированный вывод '
            'при этом не используются.':
        'The model can call plugin tools (files, commands). Requires '
        'LM Studio 0.4+, an API token and permission for mcp.json '
        'servers. Bridge chat and structured output are not used.',
    'ID интеграции': 'Integration ID',
    'lmchat/lm-computer — плагин, mcp/lm-computer — сервер '
            'из mcp.json.':
        'lmchat/lm-computer is the plugin, mcp/lm-computer a mcp.json server.',
    'mcp/lm-computer — сервер из mcp.json. '
            'lmchat/lm-computer — нативный плагин.':
        'mcp/lm-computer is a mcp.json server, '
        'lmchat/lm-computer the native plugin.',
    'Инструменты выполняет LM Studio, приложение только '
            'показывает ответ.':
        'LM Studio runs the tools; the app only shows the answer.',
    'LM Chat · 1.8.0': 'LM Chat · 1.8.0',

    // ------------------------------------------------------------ model dialog
    'Запуск по умолчанию': 'Default launch',
    'Применяются к новым чатам': 'Applied to new chats',
    'CPU': 'CPU',
    'Flash Attention': 'Flash Attention',
    'KV-кэш на GPU': 'KV cache on GPU',
    'Eval batch size': 'Eval batch size',
    'до': 'up to',
    'Не удалось подготовить модель': 'Could not prepare the model',
    'Не удалось загрузить через мостик': 'Could not load through the bridge',
    'Передача на GPU не применилась': 'GPU offload was not applied',
    'LM Studio использует настройки сервера':
        'LM Studio uses the server settings',
    'нажмите': 'tap',

    // ------------------------------------------------------------ diagnostics
    'Лог хранится только в памяти и очищается при':
        'The log is kept in memory and cleared when',
    'закрытии приложения.': 'the app is closed.',
    'LM Chat 1.8.0': 'LM Chat 1.8.0',

    // ------------------------------------------------------------ import
    '{count} сервер(ов)': '{count} server(s)',
    'Чатов: {count}': 'Chats: {count}',
    'Чатов: {chats} · сообщений: {messages}':
        'Chats: {chats} · messages: {messages}',
    'сообщений: {count}': 'messages: {count}',
    'серверов: {count}': 'servers: {count}',
    'промптов: {count}': 'prompts: {count}',

    // ------------------------------------------------------------ prompts
    // Full strings are intentional: `L10n.t` falls back to fragment
    // replacement, and split keys used to leave a mixed Russian/English
    // system prompt when the interface language was English.
    'Кратко и по делу': 'Short and to the point',
    'Отвечай кратко и по существу. Не повторяй вопрос, не добавляй вступлений и извинений. Если нужен список — используй короткие пункты.': 'Answer briefly and to the point. Do not repeat the question or add introductions or apologies. If a list is needed, use short bullets.',
    'Подробный наставник': 'Detailed mentor',
    'Объясняй пошагово и простыми словами. Сначала дай короткий ответ, затем разбор с примерами. Отмечай типичные ошибки и важные нюансы.': 'Explain step by step in simple terms. Start with a short answer, then a breakdown with examples. Point out common mistakes and important details.',
    'Опытный разработчик': 'Experienced developer',
    'Ты опытный разработчик. Предлагай рабочий код, объясняй ключевые решения и компромиссы. Учитывай обработку ошибок и граничные случаи. Не выдумывай API, которых нет.': 'You are an experienced developer. Provide working code and explain key decisions and trade-offs. Consider error handling and edge cases. Do not invent APIs that do not exist.',
    'Структурированный ответ': 'Structured answer',
    'Отвечай в структурированном виде: краткое резюме, затем разделы с заголовками, таблицами или списками, если это уместно. В конце — один практический следующий шаг.': 'Answer in a structured format: a short summary, then sections with headings, tables or lists when appropriate. End with one practical next step.',
    'Переводчик': 'Translator',
    'Переводи текст на указанный язык, сохраняя смысл, тон и форматирование. Если термин неоднозначен, предложи короткий вариант перевода в скобках. Не добавляй пояснений, если пользователь не просил.': 'Translate the text into the requested language while preserving meaning, tone and formatting. If a term is ambiguous, offer a short translation in brackets. Do not add explanations unless the user asked for them.',

    // ------------------------------------------------------------ misc
    'Чем помочь?': 'How can I help?',
    'Объясни простыми словами, как работает Transformer':
        'Explain how a Transformer works in simple terms',
    'Помоги написать письмо коллеге о переносе встречи':
        'Help me write an email to a colleague about rescheduling a meeting',
    'Придумай 5 идей для выходных в городе':
        'Suggest 5 ideas for a weekend in the city',
    'Напиши функцию на Dart для парсинга JSON':
        'Write a Dart function for parsing JSON',
    'Модель работает на вашем компьютере': 'The model runs on your computer',
    'Общайтесь с моделями, которые запущены на вашем компьютере.':
        'Chat with models running on your computer.',
    'Запросы не покидают домашнюю сеть.':
        'Requests never leave your home network.',
    'Подготовка LM Studio': 'Preparing LM Studio',
    '1. Developer → Start Server (порт 1234).':
        '1. Developer → Start Server (port 1234).',
    '2. Включите «Serve on Local Network».':
        '2. Enable “Serve on Local Network”.',
    '3. IP на Ubuntu: hostname -I.': '3. IP on Ubuntu: hostname -I.',
    '4. Телефон и ПК – в одной Wi-Fi сети.':
        '4. Phone and PC must be on the same Wi-Fi network.',
    'Адрес сервера указывается без /v1:':
        'The server address must not include /v1:',
    'Проверка с телефона:': 'Check from the phone:',
    'Если телефон не подключается:': 'If the phone cannot connect:',
    'Управление:': 'Management:',
    'Мостик установлен и работает.': 'The bridge is installed and running.',
    'Настройки для LM Chat:': 'Settings for LM Chat:',
    'Адрес LM Studio :': 'LM Studio address:',
    'Адрес мостика   :': 'Bridge address  :',
    'Токен мостика   :': 'Bridge token    :',
    'Чат через мостик: включён': 'Chat via bridge: enabled',
    'Мостик слушает только loopback. С телефона он будет недоступен.': 'The bridge listens on loopback only. It will not be reachable from the phone.',
    'Не удалось сохранить': 'Could not save',
    'Не удалось сохранить: {error}': 'Could not save: {error}',
    'Не удалось загрузить историю: {error}': 'Could not load history: {error}',
    'Не удалось загрузить через мостик: {message}':
        'Could not load through the bridge: {message}',
    'Не удалось подготовить модель: {message}':
        'Could not prepare the model: {message}',
    'Не удалось догрузить ответ: {text}': 'Could not resume the answer: {text}',
    'Новый вариант не получен: {problem}': 'No new variant received: {problem}',
    'Не удалось экспортировать: {error}': 'Could not export: {error}',
    'Не удалось загрузить историю': 'Could not load history',
    'Не удалось экспортировать': 'Could not export',
    'Не удалось импортировать': 'Could not import',
    'Не удалось открыть файл': 'Could not open the file',
    'Не удалось прочитать JSON': 'Could not read JSON',
    'Не удалось догрузить ответ': 'Could not resume the answer',
    'Соединение прервано': 'Connection interrupted',
    'Сервер не ответил вовремя. Возможно, модель ещё загружается.':
        'The server did not respond in time. The model may still be loading.',
    'Не удалось найти сервер. Проверьте адрес.':
        'Could not find the server. Check the address.',
    'Не удалось подключиться. Проверьте, что LM Studio запущен, ':
        'Could not connect. Check that LM Studio is running, ',
    'включён «Serve on Local Network» и брандмауэр не блокирует порт.': '“Serve on Local Network” is enabled and the firewall is not blocking the port.',
    'Неверный токен мостика (401)': 'Invalid bridge token (401)',
    'Мостик не найден (404). Проверьте адрес и обновите lms_gpu_bridge.py.': 'Bridge not found (404). Check the address and update lms_gpu_bridge.py.',
    'Ошибка {code}{detail}': 'Error {code}{detail}',
    'Неверный API-токен (401)': 'Invalid API token (401)',
    'Доступ запрещён (403)': 'Access denied (403)',
    'Метод не найден (404). Возможно, LM Studio старше 0.4.0.':
        'Endpoint not found (404). LM Studio may be older than 0.4.0.',
    'Сервер перестал присылать токены. Проверьте LM Studio и подключение к сети.': 'The server stopped sending tokens. Check LM Studio and the network connection.',
    'Истёк таймаут ожидания ответа.': 'The response timed out.',
    'без лимита': 'no limit',
    'не задан': 'not set',
    'Сервер не найден': 'Server not found',
    'Модель не выбрана': 'Model not selected',
    'Модель не загружена': 'Model is not loaded',
    'Модель выгружена': 'Model unloaded',
    'История восстановлена из резервной копии': 'History restored from backup',
    'Загружаю модель…': 'Loading model…',
    'Загружаю модель на GPU через мостик…':
        'Loading model on GPU through the bridge…',
    'Догружаю ответ…': 'Resuming answer…',
    'Готовится ответ…': 'Preparing answer…',
    'Модель не загружена через мостик':
        'Model was not loaded through the bridge',
    'LM Studio не поддерживает /api/v1: контекст и параметры запуска не применены.': 'LM Studio does not support /api/v1: context and launch parameters were not applied.',
    'Мостик не поддерживает чат — обновите lms_gpu_bridge.py, чтобы ответ готовился в фоне.': 'The bridge does not support chat — update lms_gpu_bridge.py so answers can be generated in the background.',
    'Пользователь остановил генерацию': 'The user stopped generation',
    'Начало генерации': 'Generation started',
    'Генерация завершена': 'Generation finished',
    'Генерация остановлена': 'Generation stopped',
    'Продолжение генерации': 'Generation continuation',
    'Догрузка ответа с мостика': 'Resuming answer from bridge',
    'Догрузка завершена': 'Resume finished',
    'Не удалось получить список моделей': 'Could not fetch the model list',
    'Не удалось применить настройки запуска': 'Could not apply launch settings',
    'Не удалось экспортировать чаты': 'Could not export chats',
    'Не удалось импортировать историю': 'Could not import history',
    'Не удалось прочитать историю': 'Could not read history',

    // ------------------------------------------------------------ controls
    'Поиск модели': 'Search model',
    'Пусто или -1 — без ограничения': 'Empty or -1 — no limit',
    'Новый шаблон': 'New template',
    'Поиск по названию или тексту': 'Search by name or text',
    'Системный промпт': 'System prompt',
    'Максимум модели: {tokens}': 'Model maximum: {tokens}',
    'Предыдущий вариант': 'Previous variant',
    'Следующий вариант': 'Next variant',
    'Все варианты': 'All variants',
    '{tokens} токенов': '{tokens} tokens',
    '{tokens} ток.': '{tokens} tok.',
    'Контекст: {estimated}осталось {remaining} из {limit}':
        'Context: {estimated}{remaining} of {limit} remaining',
    '{current} из {count}': '{current} of {count}',
    'от запроса до конца': 'from request to finish',
    'загрузка по требованию': 'on-demand load',
    'загрузка заранее': 'preload',
    'Мостик GPU: {host}': 'GPU bridge: {host}',
    'Подключено. Доступно моделей: {count}':
        'Connected. Models available: {count}',
    'Мостик GPU отвечает': 'GPU bridge is responding',
    'Мостик GPU: {version}': 'GPU bridge: {version}',
    'Мостик GPU: {error}': 'GPU bridge: {error}',
    'не отвечает': 'not responding',
    'контекст: {value}': 'context: {value}',
    'контекст до {value}': 'context up to {value}',
    'GPU: {value}': 'GPU: {value}',
    'TTL: {value}': 'TTL: {value}',
    'Вместе с ним будут удалены сохранённые варианты ответа (всего {count}).':
        'Saved answer variants will be deleted with it ({count} total).',
    'Архив ({count})': 'Archive ({count})',
    'до {value}': 'up to {value}',
    'Сейчас: {value}. Больше контекста — больше оперативной памяти.':
        'Now: {value}. More context requires more RAM.',
    'Мостик: {value}': 'Bridge: {value}',
    'Загружено через мостик · {context}': 'Loaded through bridge · {context}',
    'Модель загружена · {context}': 'Model loaded · {context}',
    'Загружена с контекстом {loaded}, выбран {desired} — нажмите «Перезагрузить».':
        'Loaded with context {loaded}, selected {desired} — tap “Reload”.',
    'Загружена · контекст {context}': 'Loaded · context {context}',
    'Не загружена · загрузится при первом сообщении или по кнопке ниже': 'Not loaded · it will load on the first message or with the button below',
    'Сохранён один ответ': 'One answer saved',
    'Сохранено ответов: {count}. Предыдущие варианты остаются на телефоне.':
        'Saved answers: {count}. Previous variants stay on the phone.',
    'Вариант {number}': 'Variant {number}',
    'Пустой ответ': 'Empty answer',
    'изменён': 'edited',
    'ошибка': 'error',
    'новый': 'new',
    'Осталось': 'Remaining',
    'Занято': 'Used',
    'Лимит': 'Limit',
    'Источник лимита': 'Limit source',
    'Часть подсчёта приблизительная: LM Studio не вернула точный usage, либо после последнего ответа появились новые сообщения. Цифры обновятся после следующего ответа.': 'Part of the count is approximate: LM Studio did not return exact usage, or new messages appeared after the last answer. The numbers will update after the next answer.',
    'Занято = системный промпт + все сообщения + последний ответ. Когда остаток закончится, начните новый чат или увеличьте контекст в настройках запуска.': 'Used = system prompt + all messages + the last answer. When the remaining space runs out, start a new chat or increase the context in launch settings.',
    'LM Studio не вернула точный usage — токены посчитаны приблизительно по символам.': 'LM Studio did not return exact usage — tokens were estimated from characters.',
    'Токены возвращены LM Studio и совпадают с использованием контекста.':
        'Tokens were returned by LM Studio and match context usage.',
    'настройки запуска': 'launch settings',
    'загруженная модель': 'loaded model',
    'модель': 'model',
    'Вариант {current} из {count}': 'Variant {current} of {count}',
    'Вариант {current} из {count} — старый':
        'Variant {current} of {count} — old',
    'Ждём первый токен · {time}': 'Waiting for the first token · {time}',
    '{tokens} ток. · {speed} tok/s · {time}':
        '{tokens} tok. · {speed} tok/s · {time}',
    'по умолчанию': 'default',
    '1 час': '1 hour',
    '{hours} ч': '{hours} h',
    '{minutes} мин': '{minutes} min',
    '{seconds} с': '{seconds} s',
    '{minutes} мин {rest} с': '{minutes} min {rest} s',
    'только CPU': 'CPU only',
    'HTTP разрешён только для локальной сети. Для внешнего сервера используйте HTTPS или Tailscale.': 'HTTP is allowed only on the local network. Use HTTPS or Tailscale for an external server.',
    'Язык': 'Language',
    'Системный': 'System',
    'Русский': 'Russian',
    'English': 'English',
  };
}
