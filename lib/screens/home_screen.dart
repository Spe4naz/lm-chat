import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n_text.dart';
import '../models.dart';
import '../theme.dart';
import '../voice_input.dart';
import '../widgets/context_indicator.dart';
import '../widgets/generation_stats_sheet.dart';
import '../widgets/import_preview_sheet.dart';
import '../widgets/message_bubble.dart';
import '../widgets/model_picker.dart';
import '../widgets/model_settings_sheet.dart';
import '../widgets/params_sheet.dart';
import '../widgets/update_banner.dart';
import '../widgets/version_sheet.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _chatListKey = GlobalKey<_ChatListState>();
  late final bool _shortcutsEnabled =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);
  late final VoiceInputController _voice = VoiceInputController();
  TextRange? _dictationRange;
  int _dictationSession = 0;
  String? _lastStatus;
  final List<ChatAttachment> _pendingAttachments = [];
  bool _pickingImages = false;

  /// Message multi-select mode used to export only part of a chat.
  bool _selectionMode = false;
  String? _selectionChatId;
  final Set<String> _selectedMessageIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_shortcutsEnabled) {
      HardwareKeyboard.instance.addHandler(_handleShortcut);
    }
    _voice.addListener(_onVoiceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AppState>().start();
        unawaited(_maybeCheckUpdates());
      }
    });
  }

  Future<void> _maybeCheckUpdates() async {
    if (!mounted) return;
    final state = context.read<AppState>();
    if (!state.data.autoCheckUpdates) return;
    final last = state.data.lastUpdateCheck;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(hours: 6)) {
      return;
    }
    final service = readUpdateService(context);
    if (service == null) return;
    await service.check();
    if (mounted) state.markUpdateChecked();
  }

  /// Windows/Linux/macOS shortcuts: new chat, search, settings and stop.
  bool _handleShortcut(KeyEvent event) {
    if (!_shortcutsEnabled || event is! KeyDownEvent) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;

    final keyboard = HardwareKeyboard.instance;
    final control =
        keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed;
    // Physical keys, not logical ones: Ctrl+N and Ctrl+F must also work on a
    // Russian keyboard layout.
    final key = event.physicalKey;

    if (control && key == PhysicalKeyboardKey.keyN) {
      final scaffold = _scaffoldKey.currentState;
      if (scaffold?.isDrawerOpen ?? false) scaffold!.closeDrawer();
      unawaited(_newChat());
      return true;
    }
    if (control && key == PhysicalKeyboardKey.keyF) {
      _focusSearch();
      return true;
    }
    if (control && key == PhysicalKeyboardKey.keyB) {
      if (MediaQuery.sizeOf(context).width >= 960) {
        context.read<AppState>().toggleSidebar();
      }
      return true;
    }
    if (control && key == PhysicalKeyboardKey.comma) {
      final scaffold = _scaffoldKey.currentState;
      if (scaffold?.isDrawerOpen ?? false) scaffold!.closeDrawer();
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
      return true;
    }
    if (key == PhysicalKeyboardKey.escape) {
      if (_selectionMode) {
        _exitSelectionMode();
        return true;
      }
      final scaffold = _scaffoldKey.currentState;
      if (scaffold?.isDrawerOpen ?? false) return false;
      final state = context.read<AppState>();
      if (!state.sending) return false;
      state.stop();
      return true;
    }
    return false;
  }

  void _focusSearch() {
    final wide = MediaQuery.sizeOf(context).width >= 960;
    if (wide) {
      final state = context.read<AppState>();
      if (state.data.sidebarCollapsed) {
        state.setSidebarCollapsed(false);
        _requestSearchFocus(0);
        return;
      }
      _chatListKey.currentState?.focusSearch();
      return;
    }
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && !scaffold.isDrawerOpen) scaffold.openDrawer();
    _requestSearchFocus(0);
  }

  /// The drawer builds its chat list during the opening animation, so the
  /// search field may not exist on the first frame.
  void _requestSearchFocus(int attempt) {
    final list = _chatListKey.currentState;
    if (list != null) {
      list.focusSearch();
      return;
    }
    if (attempt >= 4) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _requestSearchFocus(attempt + 1);
    });
  }

  void _onVoiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      // Do not keep the microphone open while the app is in the background.
      // `inactive` is ignored: Android reports it while the microphone
      // permission dialog is on screen.
      _dictationSession++;
      _dictationRange = null;
      if (_voice.listening) unawaited(_voice.cancel());
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    if (_shortcutsEnabled) {
      HardwareKeyboard.instance.removeHandler(_handleShortcut);
    }
    WidgetsBinding.instance.removeObserver(this);
    _voice.removeListener(_onVoiceChanged);
    _voice.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _toggleVoice() async {
    if (_voice.listening) {
      // Keep the range: the recognizer may still deliver a final result that
      // replaces the last partial text instead of appending to it.
      await _voice.stop();
      return;
    }
    if (_voice.starting) return;
    unawaited(HapticFeedback.selectionClick());
    final session = ++_dictationSession;
    final value = _input.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    _dictationRange = TextRange(start: start, end: end);
    final started = await _voice.start(
      localeId: voiceLocaleFor(english: L10n.isEnglish),
      onWords: (words, isFinal) => _onVoiceWords(session, words, isFinal),
      onError: _showVoiceError,
    );
    if (!started && mounted && session == _dictationSession) {
      setState(() => _dictationRange = null);
    }
  }

  void _onVoiceWords(int session, String words, bool isFinal) {
    if (!mounted || session != _dictationSession) return;
    final edit = applyDictation(
      value: _input.value,
      range: _dictationRange ?? TextRange.collapsed(_input.value.text.length),
      words: words,
    );
    _dictationRange = isFinal ? null : edit.range;
    _input.value = edit.value;
    if (isFinal) unawaited(HapticFeedback.lightImpact());
  }

  void _showVoiceError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onInputChanged(String _) {
    if (!_voice.listening && _dictationRange == null) return;
    // The user is editing by hand: stop dictation instead of overwriting it.
    _dictationSession++;
    _dictationRange = null;
    unawaited(_voice.cancel());
  }

  Future<void> _send() async {
    _dictationSession++;
    _dictationRange = null;
    if (_voice.listening) unawaited(_voice.cancel());
    final text = _input.text;
    final attachments = List<ChatAttachment>.from(_pendingAttachments);
    if (text.trim().isEmpty && attachments.isEmpty) return;
    final state = context.read<AppState>();
    final chat = state.activeChat;
    final estimatedTokens = estimateTokens(text) + attachments.length * 256;
    if (chat != null &&
        state.exceedsContext(chat, text, imageCount: attachments.length)) {
      final usage = state.contextUsage(chat);
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Запрос не помещается в контекст'),
          content: Text(
            'Сообщение занимает примерно $estimatedTokens токенов, '
            'а свободно ${usage?.remaining ?? 0} из ${usage?.limit ?? 0}.\n\n'
            'Модель может обрезать ответ или запрос. Отправить всё равно?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Отправить'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    _input.clear();
    setState(_pendingAttachments.clear);
    unawaited(state.send(text, attachments: attachments));
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _pickImages() async {
    if (_pickingImages) return;
    final state = context.read<AppState>();
    final chat = state.activeChat;
    if (chat == null) return;
    final info = state.modelInfo(chat.serverId, chat.model);
    if (info != null && !info.vision) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Выбранная модель не поддерживает изображения'),
          ),
        );
      return;
    }
    setState(() => _pickingImages = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.image,
        compressionQuality: 85,
        dialogTitle: L10n.t('Выберите изображения'),
      );
      if (!mounted || files.isEmpty) return;
      final remaining = 4 - _pendingAttachments.length;
      if (remaining <= 0) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Можно прикрепить не более 4 изображений'),
            ),
          );
        return;
      }
      final picked = <ChatAttachment>[];
      for (final file in files.take(remaining)) {
        final bytes = await file.readAsBytes();
        if (bytes.length > 4 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                    L10n.tf('Изображение слишком большое: {name}', {
                      'name': file.name,
                    }),
                  ),
                ),
              );
          }
          continue;
        }
        picked.add(
          ChatAttachment(
            id: newId(),
            mimeType: _mimeTypeFor(file.name),
            data: base64Encode(bytes),
            name: file.name,
          ),
        );
      }
      if (!mounted || picked.isEmpty) return;
      setState(() => _pendingAttachments.addAll(picked));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf('Не удалось открыть изображение: {error}', {
                'error': error,
              }),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _pickingImages = false);
    }
  }

  String _mimeTypeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
      return 'image/heic';
    }
    return 'image/jpeg';
  }

  Future<void> _newChat({bool closeDrawer = false}) async {
    final state = context.read<AppState>();
    final chat = state.newChat();
    if (closeDrawer && mounted) Navigator.of(context).pop();
    if (chat.model.isEmpty) {
      final server = state.serverById(chat.serverId);
      if (server != null) {
        final result = await state.refreshModels(server);
        final llm = result.models.where((m) => m.isLlm).toList();
        if (llm.isNotEmpty && chat.model.isEmpty) {
          state.setChatModel(chat, llm.first.key);
        }
      }
    }
  }

  Future<void> _rename(ChatSession chat) async {
    final controller = TextEditingController(text: chat.title);
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Название чата'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: L10n.t('Название')),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title != null && mounted) {
      context.read<AppState>().renameChat(chat, title);
    }
  }

  Future<void> _confirmDeleteMessage(
    AppState state,
    ChatSession chat,
    ChatMessage message,
  ) async {
    if (!message.hasVersions) {
      state.deleteMessage(chat, message);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить сообщение?'),
        content: Text(
          L10n.tf(
            'Вместе с ним будут удалены сохранённые варианты ответа (всего {count}).',
            {'count': message.versionCount},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) state.deleteMessage(chat, message);
  }

  Future<void> _editMessage(
    AppState state,
    ChatSession chat,
    ChatMessage message,
  ) async {
    if (message.isUser) {
      final result = await showDialog<_EditUserResult>(
        context: context,
        builder: (_) => _EditUserDialog(initialText: message.content),
      );
      if (!mounted || result == null) return;
      if (result.text.trim().isEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Сообщение не может быть пустым')),
          );
        return;
      }
      state.editUserMessage(
        chat,
        message,
        result.text,
        dropFollowing: result.regenerate,
      );
      if (result.regenerate) await state.regenerate();
      return;
    }

    final text = await showDialog<String>(
      context: context,
      builder: (_) => _EditAnswerDialog(
        initialText: message.displayContent,
        hasVersions: message.hasVersions,
      ),
    );
    if (!mounted || text == null) return;
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Ответ не может быть пустым')),
        );
      return;
    }
    state.editMessage(chat, message, text);
  }

  Future<void> _confirmDelete(ChatSession chat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить чат?'),
        content: Text(
          L10n.tf('«{title}» будет удалён без возможности отмены.', {
            'title': chat.title,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      context.read<AppState>().deleteChat(chat);
    }
  }

  /// Enters message multi-select mode. A long press selects the message it
  /// started from; the chat menu starts with an empty selection.
  void _startSelection([ChatMessage? message]) {
    final chat = context.read<AppState>().activeChat;
    if (chat == null || chat.messages.isEmpty) return;
    setState(() {
      _selectionMode = true;
      _selectionChatId = chat.id;
      _selectedMessageIds.clear();
      if (message != null) _selectedMessageIds.add(message.id);
    });
  }

  void _exitSelectionMode() {
    if (!_selectionMode && _selectedMessageIds.isEmpty) return;
    setState(() {
      _selectionMode = false;
      _selectionChatId = null;
      _selectedMessageIds.clear();
    });
  }

  void _toggleMessageSelection(ChatMessage message) {
    setState(() {
      if (!_selectedMessageIds.remove(message.id)) {
        _selectedMessageIds.add(message.id);
      }
    });
  }

  void _toggleSelectAll(ChatSession chat) {
    setState(() {
      final allSelected =
          chat.messages.isNotEmpty &&
          chat.messages.every(
            (message) => _selectedMessageIds.contains(message.id),
          );
      if (allSelected) {
        _selectedMessageIds.clear();
      } else {
        _selectedMessageIds.addAll(chat.messages.map((message) => message.id));
      }
    });
  }

  List<ChatMessage> _selectedMessages(ChatSession chat) => chat.messages
      .where((message) => _selectedMessageIds.contains(message.id))
      .toList();

  Future<void> _copySelectedMessages(AppState state, ChatSession chat) async {
    final selected = _selectedMessages(chat);
    if (selected.isEmpty) return;
    await Clipboard.setData(
      ClipboardData(text: state.messagesToMarkdown(chat, selected)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            L10n.tf('Скопировано сообщений: {count}', {
              'count': selected.length,
            }),
          ),
        ),
      );
  }

  AppBar _selectionAppBar(
    AppState state,
    ChatSession chat,
    List<ChatMessage> selected,
  ) {
    final allSelected =
        chat.messages.isNotEmpty && selected.length == chat.messages.length;
    final enabled = selected.isNotEmpty;
    return AppBar(
      leading: IconButton(
        onPressed: _exitSelectionMode,
        icon: const Icon(Icons.close_rounded),
        tooltip: L10n.t('Отмена'),
      ),
      titleSpacing: 4,
      title: Text(
        L10n.tf('Выбрано: {count}', {'count': selected.length}),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      actions: [
        IconButton(
          onPressed: () => _toggleSelectAll(chat),
          icon: Icon(
            allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
          ),
          tooltip: allSelected ? L10n.t('Снять выбор') : L10n.t('Выбрать всё'),
        ),
        IconButton(
          onPressed: enabled ? () => _copySelectedMessages(state, chat) : null,
          icon: const Icon(Icons.copy_rounded),
          tooltip: L10n.t('Копировать выбранное'),
        ),
        PopupMenuButton<String>(
          enabled: enabled,
          tooltip: L10n.t('Экспорт выбранного'),
          onSelected: (value) {
            final messages = _selectedMessages(chat);
            if (messages.isEmpty) return;
            switch (value) {
              case 'md':
                state.exportMessagesMarkdown(chat, messages);
              case 'json':
                state.exportMessagesJson(chat, messages);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'md',
              child: _SelectionMenuRow(
                icon: Icons.description_outlined,
                label: 'Экспорт Markdown',
              ),
            ),
            PopupMenuItem(
              value: 'json',
              child: _SelectionMenuRow(
                icon: Icons.data_object_rounded,
                label: 'Экспорт JSON',
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final chat = state.activeChat;
    final contextInfo = chat == null ? null : state.contextUsage(chat);
    final scheme = Theme.of(context).colorScheme;

    // Switching chats leaves the previous selection behind.
    if (_selectionMode && chat?.id != _selectionChatId) {
      _selectionMode = false;
      _selectionChatId = null;
      _selectedMessageIds.clear();
    }

    if (state.statusMessage != null && state.statusMessage != _lastStatus) {
      _lastStatus = state.statusMessage;
      final message = state.statusMessage!;
      state.statusMessage = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      });
    }

    final wide = MediaQuery.sizeOf(context).width >= 960;
    final compact = AppDensity.isCompact(context);

    final appBar = _selectionMode && chat != null
        ? _selectionAppBar(state, chat, _selectedMessages(chat))
        : AppBar(
            leading: wide && state.data.sidebarCollapsed
                ? IconButton(
                    onPressed: () => state.setSidebarCollapsed(false),
                    icon: const Icon(Icons.chevron_right_rounded),
                    tooltip: L10n.t('Показать чаты'),
                  )
                : null,
            titleSpacing: 16,
            title: chat == null
                ? Text('LM Chat', style: Theme.of(context).textTheme.titleLarge)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _rename(chat),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            chat.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => showModelPicker(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.memory_rounded,
                                size: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  chat.model.isEmpty
                                      ? 'Выберите модель'
                                      : chat.model,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.expand_more_rounded,
                                size: 14,
                                color: scheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
            actions: [
              IconButton(
                onPressed: () => showChatParams(context),
                icon: const Icon(Icons.tune_rounded, size: 21),
                tooltip: L10n.t('Параметры чата'),
              ),
              if (MediaQuery.sizeOf(context).width >= 520)
                IconButton(
                  onPressed: () => showModelSettings(context),
                  icon: const Icon(Icons.memory_rounded, size: 21),
                  tooltip: L10n.t('Запуск модели'),
                ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  final current = state.activeChat;
                  if (current == null) return;
                  switch (value) {
                    case 'launch':
                      await showModelSettings(context);
                    case 'rename':
                      await _rename(current);
                    case 'regen':
                      await state.regenerate();
                    case 'clear':
                      state.clearChat(current);
                    case 'export':
                      await state.exportChats(chat: current);
                    case 'export_md':
                      await state.exportChatMarkdown(current);
                    case 'export_csv':
                      await state.exportChatStats(current);
                    case 'copy':
                      await Clipboard.setData(
                        ClipboardData(text: state.chatToMarkdown(current)),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(content: Text('Чат скопирован')),
                        );
                    case 'select':
                      _startSelection();
                    case 'delete':
                      await _confirmDelete(current);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'launch', child: Text('Запуск модели')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                  PopupMenuItem(value: 'regen', child: Text('Повторить ответ')),
                  PopupMenuItem(value: 'clear', child: Text('Очистить чат')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'copy', child: Text('Копировать чат')),
                  PopupMenuItem(
                    value: 'select',
                    child: Text('Выбрать сообщения'),
                  ),
                  PopupMenuItem(value: 'export', child: Text('Экспорт JSON')),
                  PopupMenuItem(
                    value: 'export_md',
                    child: Text('Экспорт Markdown'),
                  ),
                  PopupMenuItem(
                    value: 'export_csv',
                    child: Text('Экспорт статистики CSV'),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'delete', child: Text('Удалить чат')),
                ],
              ),
            ],
          );

    final bodyContent = chat == null
        ? const SizedBox.shrink()
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                children: [
                  const UpdateBanner(),
                  if (state.isOffline)
                    _OfflineBanner(
                      checking: state.checkingConnection,
                      onRetry: state.reconnect,
                    ),
                  Expanded(
                    child: chat.messages.isEmpty
                        ? _EmptyChat(
                            onPrompt: (prompt) {
                              final localized = L10n.t(prompt);
                              _input.text = localized;
                              _input.selection = TextSelection.collapsed(
                                offset: localized.length,
                              );
                            },
                          )
                        : ListView.builder(
                            controller: _scroll,
                            reverse: true,
                            padding: compact
                                ? const EdgeInsets.fromLTRB(16, 4, 14, 8)
                                : const EdgeInsets.fromLTRB(16, 8, 14, 14),
                            itemCount: chat.messages.length,
                            itemBuilder: (context, index) {
                              final message = chat
                                  .messages[chat.messages.length - 1 - index];
                              final isLast = index == 0;
                              return MessageBubble(
                                message: message,
                                selectionMode: _selectionMode,
                                selected: _selectedMessageIds.contains(
                                  message.id,
                                ),
                                onToggleSelection: () =>
                                    _toggleMessageSelection(message),
                                onStartSelection: () =>
                                    _startSelection(message),
                                showRetry:
                                    isLast &&
                                    message.role == 'assistant' &&
                                    message.viewingLatest &&
                                    !message.streaming &&
                                    !state.sending,
                                onRetry: state.regenerate,
                                showContinue:
                                    isLast &&
                                    message.role == 'assistant' &&
                                    message.viewingLatest &&
                                    !message.streaming &&
                                    !message.hasPendingJob &&
                                    !state.sending,
                                onContinue: state.continueGeneration,
                                onDelete: message.streaming
                                    ? null
                                    : () => _confirmDeleteMessage(
                                        state,
                                        chat,
                                        message,
                                      ),
                                onSelectVersion: (number) =>
                                    state.selectMessageVersion(message, number),
                                onShowVersions: () => showVersionsSheet(
                                  context,
                                  message: message,
                                  onSelect: (number) => state
                                      .selectMessageVersion(message, number),
                                  onDelete: (number) => state
                                      .deleteMessageVersion(message, number),
                                ),
                                onShowStats: message.hasStats
                                    ? () => showGenerationStats(
                                        context,
                                        message: message,
                                        contextUsage: contextInfo,
                                      )
                                    : null,
                                onEdit: message.streaming
                                    ? null
                                    : () => _editMessage(state, chat, message),
                                onResume:
                                    message.hasPendingJob &&
                                        !message.streaming &&
                                        !state.sending
                                    ? () => state.resumeMessage(chat, message)
                                    : null,
                              );
                            },
                          ),
                  ),
                  if (_pendingAttachments.isNotEmpty)
                    _PendingImages(
                      attachments: _pendingAttachments,
                      onRemove: (attachment) => setState(
                        () => _pendingAttachments.remove(attachment),
                      ),
                    ),
                  if (!chat.responseFormat.isText)
                    _ResponseFormatBadge(
                      format: chat.responseFormat,
                      onTap: () => showChatParams(context),
                    ),
                  if (_voice.listening)
                    _VoiceListeningBar(onStop: _toggleVoice),
                  if (contextInfo != null)
                    ContextIndicator(
                      usage: contextInfo,
                      onTap: () => showContextDetails(context, contextInfo),
                    ),
                  _Composer(
                    controller: _input,
                    sending: state.sending,
                    onSend: _send,
                    onStop: state.stop,
                    onAttach: _pickImages,
                    picking: _pickingImages,
                    canAttach:
                        state.modelInfo(chat.serverId, chat.model)?.vision ??
                        true,
                    showVoice:
                        !kIsWeb &&
                        (defaultTargetPlatform == TargetPlatform.android ||
                            defaultTargetPlatform == TargetPlatform.iOS),
                    listening: _voice.listening,
                    voiceBusy: _voice.starting,
                    onVoice: _toggleVoice,
                    onChanged: _onInputChanged,
                  ),
                ],
              ),
            ),
          );

    if (wide) {
      final width = state.data.sidebarWidth.clamp(240.0, 480.0);
      return Scaffold(
        key: _scaffoldKey,
        body: Row(
          children: [
            if (!state.data.sidebarCollapsed) ...[
              SizedBox(
                width: width,
                child: _AppDrawer(
                  chatListKey: _chatListKey,
                  onNewChat: () => _newChat(closeDrawer: false),
                  onDeleteChat: _confirmDelete,
                  onRenameChat: _rename,
                  onCollapse: () => state.setSidebarCollapsed(true),
                  embedded: true,
                  closeOnSelect: false,
                ),
              ),
              _SidebarResizer(
                key: const ValueKey('sidebar-resizer'),
                onDrag: (delta) => state.setSidebarWidth(width + delta),
                onReset: () => state.setSidebarWidth(320),
              ),
            ],
            Expanded(
              child: Scaffold(appBar: appBar, body: bodyContent),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: _AppDrawer(
        chatListKey: _chatListKey,
        onNewChat: () => _newChat(closeDrawer: true),
        onDeleteChat: _confirmDelete,
        onRenameChat: _rename,
      ),
      appBar: appBar,
      body: bodyContent,
    );
  }
}

class _SelectionMenuRow extends StatelessWidget {
  const _SelectionMenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.onSurface),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: scheme.onSurface)),
      ],
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.checking, required this.onRetry});

  final bool checking;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Нет связи с сервером',
              style: TextStyle(fontSize: 12.5, color: scheme.onErrorContainer),
            ),
          ),
          if (checking)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Повторить'),
            ),
        ],
      ),
    );
  }
}

class _VoiceListeningBar extends StatelessWidget {
  const _VoiceListeningBar({required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 2, 6, 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.graphic_eq_rounded, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Слушаю…',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurface),
            ),
          ),
          TextButton(
            onPressed: onStop,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text('Стоп'),
          ),
        ],
      ),
    );
  }
}

class _ResponseFormatBadge extends StatelessWidget {
  const _ResponseFormatBadge({required this.format, required this.onTap});

  final ResponseFormat format;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = switch (format.mode) {
      ResponseFormatMode.json => 'JSON',
      ResponseFormatMode.jsonSchema => L10n.t('JSON по схеме'),
      ResponseFormatMode.grammar => 'GBNF',
      ResponseFormatMode.text => '',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          avatar: const Icon(Icons.data_object_rounded, size: 16),
          label: Text(label, style: const TextStyle(fontSize: 11.5)),
          onPressed: onTap,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

class _EditUserResult {
  const _EditUserResult(this.text, {required this.regenerate});

  final String text;
  final bool regenerate;
}

class _EditUserDialog extends StatefulWidget {
  const _EditUserDialog({required this.initialText});

  final String initialText;

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Редактировать сообщение'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 3,
              maxLines: 10,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: L10n.t('Текст сообщения'),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '«Сохранить и ответить» удалит все сообщения после этого и '
              'сгенерирует новый ответ.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            _EditUserResult(_controller.text, regenerate: false),
          ),
          child: const Text('Сохранить'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _EditUserResult(_controller.text, regenerate: true),
          ),
          child: const Text('Сохранить и ответить'),
        ),
      ],
    );
  }
}

class _EditAnswerDialog extends StatefulWidget {
  const _EditAnswerDialog({
    required this.initialText,
    required this.hasVersions,
  });

  final String initialText;
  final bool hasVersions;

  @override
  State<_EditAnswerDialog> createState() => _EditAnswerDialogState();
}

class _EditAnswerDialogState extends State<_EditAnswerDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Редактировать ответ'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.hasVersions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Прежний текст сохранится как отдельный вариант.',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              TextField(
                controller: _controller,
                autofocus: true,
                minLines: 6,
                maxLines: 14,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: L10n.t('Текст ответа'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _PendingImages extends StatelessWidget {
  const _PendingImages({required this.attachments, required this.onRemove});

  final List<ChatAttachment> attachments;
  final ValueChanged<ChatAttachment> onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 82,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final attachment = attachments[index];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  attachment.bytes,
                  width: 68,
                  height: 68,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 68,
                    height: 68,
                    color: scheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
              Positioned(
                top: -4,
                right: -4,
                child: Material(
                  color: scheme.error,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => onRemove(attachment),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(
                        Icons.close_rounded,
                        size: 13,
                        color: scheme.onError,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onStop,
    required this.onAttach,
    required this.picking,
    required this.canAttach,
    required this.showVoice,
    required this.listening,
    required this.voiceBusy,
    required this.onVoice,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onAttach;
  final bool picking;
  final bool canAttach;
  final bool showVoice;
  final bool listening;
  final bool voiceBusy;
  final VoidCallback onVoice;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = AppDensity.isCompact(context);
    final desktop =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS);
    return Container(
      margin: compact
          ? const EdgeInsets.fromLTRB(12, 4, 12, 6)
          : const EdgeInsets.fromLTRB(12, 6, 12, 10),
      padding: EdgeInsets.all(compact ? 4 : 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.75),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: sending || picking || !canAttach ? null : onAttach,
              icon: picking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.image_outlined, size: 20),
              tooltip: canAttach
                  ? L10n.t('Прикрепить изображение')
                  : L10n.t('Модель не поддерживает изображения'),
              visualDensity: VisualDensity.compact,
            ),
            if (showVoice)
              IconButton(
                onPressed: voiceBusy ? null : onVoice,
                icon: voiceBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        listening
                            ? Icons.graphic_eq_rounded
                            : Icons.mic_none_rounded,
                        size: 20,
                        color: listening ? scheme.primary : null,
                      ),
                tooltip: listening
                    ? L10n.t('Остановить голосовой ввод')
                    : L10n.t('Голосовой ввод'),
                visualDensity: VisualDensity.compact,
              ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: desktop
                    ? TextInputAction.send
                    : TextInputAction.newline,
                onChanged: onChanged,
                onSubmitted: desktop && !sending ? (_) => onSend() : null,
                decoration: InputDecoration(
                  hintText: sending
                      ? L10n.t('Модель печатает…')
                      : L10n.t('Сообщение'),
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: compact ? 8 : 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            if (sending)
              IconButton.filledTonal(
                onPressed: onStop,
                icon: const Icon(Icons.stop_rounded, size: 20),
                tooltip: L10n.t('Остановить'),
              )
            else
              IconButton.filled(
                onPressed: onSend,
                icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                tooltip: L10n.t('Отправить'),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.onPrompt});

  final ValueChanged<String> onPrompt;

  static const _prompts = [
    (
      Icons.lightbulb_outline_rounded,
      'Объясни простыми словами, как работает Transformer',
    ),
    (
      Icons.mail_outline_rounded,
      'Помоги написать письмо коллеге о переносе встречи',
    ),
    (Icons.explore_outlined, 'Придумай 5 идей для выходных в городе'),
    (Icons.code_rounded, 'Напиши функцию на Dart для парсинга JSON'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final chat = state.activeChat;
    final server = state.activeServer;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [scheme.primary, scheme.tertiary],
                  ),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 32,
                  color: scheme.onPrimary,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Чем помочь?',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 7),
              Text(
                'Модель работает на вашем компьютере',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (chat != null) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    if (server != null)
                      _StatusChip(
                        icon: Icons.dns_outlined,
                        label: serverLabel(server),
                      ),
                    _StatusChip(
                      icon: Icons.memory_rounded,
                      label: chat.model.isEmpty
                          ? L10n.t('Выберите модель')
                          : chat.model,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 520 ? 2 : 1;
                  final width = columns == 2
                      ? (constraints.maxWidth - 10) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final prompt in _prompts)
                        SizedBox(
                          width: width,
                          child: _SuggestionCard(
                            icon: prompt.$1,
                            text: prompt.$2,
                            onTap: () => onPrompt(prompt.$2),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.65),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.arrow_outward_rounded,
                size: 15,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarResizer extends StatelessWidget {
  const _SidebarResizer({
    super.key,
    required this.onDrag,
    required this.onReset,
  });

  final ValueChanged<double> onDrag;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        onDoubleTap: onReset,
        child: Tooltip(
          message: L10n.t('Изменить ширину списка чатов'),
          child: SizedBox(
            width: 8,
            height: double.infinity,
            child: Center(
              child: Container(
                width: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.onNewChat,
    required this.onDeleteChat,
    required this.onRenameChat,
    this.onCollapse,
    this.chatListKey,
    this.embedded = false,
    this.closeOnSelect = true,
  });

  final VoidCallback onNewChat;
  final Future<void> Function(ChatSession) onDeleteChat;
  final Future<void> Function(ChatSession) onRenameChat;

  /// Hides the permanent desktop sidebar. Null in drawer mode.
  final VoidCallback? onCollapse;
  final Key? chatListKey;

  /// Desktop sidebar: no drawer animation, always visible.
  final bool embedded;
  final bool closeOnSelect;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final server = state.activeServer;
    final colors = AppColors.of(context);

    final content = SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [scheme.primary, scheme.tertiary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(
                    Icons.forum_rounded,
                    size: 21,
                    color: scheme.onPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LM Chat',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: state.isOffline
                                  ? scheme.error
                                  : colors.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              server == null
                                  ? 'нет сервера'
                                  : serverLabel(server),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onCollapse != null)
                  IconButton(
                    onPressed: onCollapse,
                    icon: const Icon(Icons.menu_open_rounded, size: 20),
                    tooltip: L10n.t('Скрыть список чатов'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: FilledButton.icon(
              onPressed: onNewChat,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Новый чат'),
              style: FilledButton.styleFrom(
                minimumSize: Size.fromHeight(
                  AppDensity.isCompact(context) ? 42 : 46,
                ),
              ),
            ),
          ),
          Expanded(
            child: _ChatList(
              key: chatListKey,
              onDeleteChat: onDeleteChat,
              onRenameChat: onRenameChat,
              closeOnSelect: closeOnSelect,
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.dns_outlined, size: 20),
                  title: const Text(
                    'Серверы и настройки',
                    style: TextStyle(fontSize: 13.5),
                  ),
                  subtitle: Text(
                    L10n.tf('{count} сервер(ов)', {
                      'count': state.servers.length,
                    }),
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () {
                    if (!embedded) Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.file_open_outlined, size: 20),
                  title: const Text(
                    'Импорт истории',
                    style: TextStyle(fontSize: 13.5),
                  ),
                  subtitle: const Text(
                    'Объединить с текущими чатами из JSON',
                    style: TextStyle(fontSize: 11),
                  ),
                  onTap: () async {
                    if (!embedded) Navigator.of(context).pop();
                    final preview = await state.pickImportPreview();
                    if (!context.mounted) return;
                    if (preview.cancelled) return;
                    if (!preview.ok) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(
                              preview.error ?? 'Не удалось прочитать файл',
                            ),
                          ),
                        );
                      return;
                    }
                    final selected = await showImportPreview(context, preview);
                    if (!context.mounted ||
                        selected == null ||
                        selected.isEmpty) {
                      return;
                    }
                    final result = state.importPreview(
                      preview,
                      selectedChats: selected,
                    );
                    final extra = [
                      if (result.servers > 0)
                        L10n.tf('серверов: {count}', {'count': result.servers}),
                      if (result.templates > 0)
                        L10n.tf('промптов: {count}', {
                          'count': result.templates,
                        }),
                    ].join(', ');
                    final message =
                        result.error ??
                        '${L10n.tf('Импортировано чатов: {count}', {'count': result.chats})}'
                            '${extra.isEmpty ? '' : ', $extra'}';
                    final messenger = ScaffoldMessenger.of(context);
                    messenger
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(content: Text(message)));
                  },
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.ios_share_rounded, size: 20),
                  title: const Text(
                    'Экспорт всех чатов',
                    style: TextStyle(fontSize: 13.5),
                  ),
                  onTap: () {
                    if (!embedded) Navigator.of(context).pop();
                    state.exportChats();
                  },
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.description_outlined, size: 20),
                  title: const Text(
                    'Все чаты в Markdown',
                    style: TextStyle(fontSize: 13.5),
                  ),
                  onTap: () {
                    if (!embedded) Navigator.of(context).pop();
                    state.exportAllChatsMarkdown();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (embedded) {
      return Material(
        color: colors.sidebar,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
          child: content,
        ),
      );
    }
    return Drawer(child: content);
  }
}

class _ChatList extends StatefulWidget {
  const _ChatList({
    super.key,
    required this.onDeleteChat,
    required this.onRenameChat,
    this.closeOnSelect = true,
  });

  final Future<void> Function(ChatSession) onDeleteChat;
  final Future<void> Function(ChatSession) onRenameChat;
  final bool closeOnSelect;

  @override
  State<_ChatList> createState() => _ChatListState();
}

class _ChatListState extends State<_ChatList> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  bool _showArchived = false;

  void focusSearch() {
    _searchFocus.requestFocus();
    _search.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _search.text.length,
    );
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  List<ChatSession> _filtered(List<ChatSession> chats) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return chats;
    return chats.where((chat) {
      if (chat.title.toLowerCase().contains(query)) return true;
      if (chat.model.toLowerCase().contains(query)) return true;
      return chat.messages.any(
        (message) => message.displayContent.toLowerCase().contains(query),
      );
    }).toList();
  }

  Future<void> _showActions(ChatSession chat) async {
    final state = context.read<AppState>();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 460),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                chat.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              ),
              title: Text(chat.pinned ? 'Открепить' : 'Закрепить'),
              onTap: () {
                Navigator.pop(sheetContext);
                state.togglePinned(chat);
              },
            ),
            ListTile(
              leading: Icon(
                chat.archived
                    ? Icons.unarchive_rounded
                    : Icons.archive_outlined,
              ),
              title: Text(chat.archived ? 'Вернуть из архива' : 'Архивировать'),
              onTap: () {
                Navigator.pop(sheetContext);
                if (chat.archived) {
                  state.unarchiveChat(chat);
                } else {
                  state.archiveChat(chat);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Переименовать'),
              onTap: () {
                Navigator.pop(sheetContext);
                widget.onRenameChat(chat);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: Theme.of(sheetContext).colorScheme.error,
              ),
              title: Text(
                'Удалить',
                style: TextStyle(
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                widget.onDeleteChat(chat);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final source = _showArchived ? state.archivedChats : state.activeChats;
    final chats = _filtered(source);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: TextField(
            key: const ValueKey('chat-search-field'),
            controller: _search,
            focusNode: _searchFocus,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: L10n.t('Поиск по чатам и сообщениям'),
              prefixIcon: const Icon(Icons.search_rounded, size: 19),
              isDense: true,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                      tooltip: L10n.t('Очистить'),
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 8, 2),
          child: Row(
            children: [
              Text(
                _showArchived ? 'АРХИВ' : 'ЧАТЫ',
                style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 0.9,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() {
                  _showArchived = !_showArchived;
                  _query = '';
                  _search.clear();
                }),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(
                  _showArchived
                      ? L10n.t('К активным')
                      : L10n.tf('Архив ({count})', {
                          'count': state.archivedChats.length,
                        }),
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: chats.isEmpty
              ? Center(
                  child: Text(
                    _query.isNotEmpty
                        ? 'Ничего не найдено'
                        : _showArchived
                        ? 'Архив пуст'
                        : 'Пока нет чатов',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  itemCount: chats.length,
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    return _ChatTile(
                      chat: chat,
                      selected: chat.id == state.activeChat?.id,
                      generating: state.isGenerating(chat),
                      onTap: () {
                        state.selectChat(chat);
                        if (widget.closeOnSelect) {
                          Navigator.of(context).maybePop();
                        }
                      },
                      onLongPress: () => _showActions(chat),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.chat,
    required this.selected,
    required this.generating,
    required this.onTap,
    required this.onLongPress,
  });

  final ChatSession chat;
  final bool selected;
  final bool generating;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = _chatPreview(chat);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: selected
                        ? scheme.primary.withValues(alpha: 0.16)
                        : scheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    chat.archived
                        ? Icons.inventory_2_outlined
                        : Icons.chat_bubble_outline_rounded,
                    size: 17,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              chat.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _formatChatTime(chat.updatedAt),
                            style: TextStyle(
                              fontSize: 10.5,
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (chat.pinned || generating) ...[
                  const SizedBox(width: 6),
                  if (chat.pinned)
                    Icon(
                      Icons.push_pin_rounded,
                      size: 14,
                      color: scheme.primary,
                    ),
                  if (generating) ...[
                    if (chat.pinned) const SizedBox(width: 5),
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _chatPreview(ChatSession chat) {
  if (chat.messages.isEmpty) {
    return chat.model.isEmpty ? 'Нет сообщений' : chat.model;
  }
  final last = chat.messages.last;
  final text = last.displayContent.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.isNotEmpty) return text;
  if (last.attachments.isNotEmpty) return L10n.t('Изображение');
  return chat.model.isEmpty ? 'Нет сообщений' : chat.model;
}

String _formatChatTime(DateTime date) {
  final local = date.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  String two(int value) => value.toString().padLeft(2, '0');
  if (day == today) return '${two(local.hour)}:${two(local.minute)}';
  if (day == today.subtract(const Duration(days: 1))) {
    return L10n.t('Вчера');
  }
  if (local.year == now.year) return '${two(local.day)}.${two(local.month)}';
  return '${two(local.day)}.${two(local.month)}.${local.year % 100}';
}
