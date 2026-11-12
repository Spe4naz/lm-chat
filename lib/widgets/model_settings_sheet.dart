import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../format_utils.dart';
import '../l10n_text.dart';
import '../models.dart';

/// Bottom sheet with model launch options: context window, on-demand loading,
/// idle TTL, Flash Attention, KV-cache offload and eval batch size.
///
/// With [defaults] enabled the sheet edits the app-wide defaults instead of the
/// active chat.
Future<void> showModelSettings(
  BuildContext context, {
  bool defaults = false,
}) async {
  final state = context.read<AppState>();
  if (!defaults && state.activeChat == null) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ModelSettingsSheet(defaults: defaults),
  );
}

class _ModelSettingsSheet extends StatefulWidget {
  const _ModelSettingsSheet({required this.defaults});

  final bool defaults;

  @override
  State<_ModelSettingsSheet> createState() => _ModelSettingsSheetState();
}

class _ModelSettingsSheetState extends State<_ModelSettingsSheet> {
  static const _contextPresets = [
    1024,
    2048,
    4096,
    8192,
    16384,
    32768,
    65536,
    131072,
    262144,
  ];

  static const _ttlPresets = [null, 300, 900, 1800, 3600, 7200, 28800, 86400];

  static const _batchPresets = [null, 128, 256, 512, 1024, 2048];

  late LaunchSettings _launch;
  bool _busy = false;
  bool _refreshing = false;
  String? _error;
  String? _warning;
  String? _command;

  ChatSession? get _chat => context.read<AppState>().activeChat;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _launch = widget.defaults
        ? state.data.defaultLaunch
        : (state.activeChat?.launch ?? state.data.defaultLaunch);
    if (!widget.defaults) _refresh();
  }

  /// Pulls fresh model metadata so the loaded state and max context are real.
  Future<void> _refresh() async {
    final state = context.read<AppState>();
    final chat = state.activeChat;
    final server = state.serverById(chat?.serverId);
    if (chat == null || server == null) return;
    setState(() => _refreshing = true);
    await state.refreshModels(server);
    if (mounted) setState(() => _refreshing = false);
  }

  void _update(LaunchSettings next) {
    final state = context.read<AppState>();
    setState(() {
      _launch = next;
      _error = null;
      _warning = null;
      _command = null;
    });
    if (widget.defaults) {
      state.updateDefaultLaunch(next);
    } else {
      final chat = state.activeChat;
      if (chat != null) state.updateChatLaunch(chat, next);
    }
  }

  LmModelInfo? get _info {
    if (widget.defaults) return null;
    final state = context.read<AppState>();
    final chat = state.activeChat;
    if (chat == null) return null;
    return state.modelInfo(chat.serverId, chat.model);
  }

  Future<void> _pickCustomContext() async {
    final max = _info?.maxContextLength;
    final controller = TextEditingController(
      text: _launch.contextLength?.toString() ?? '',
    );
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Контекстное окно'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: L10n.t('Токенов'),
                hintText: L10n.t('например 12288'),
                helperText: max == null
                    ? null
                    : L10n.tf('Максимум модели: {tokens}', {
                        'tokens': formatNumber(max),
                      }),
              ),
              onSubmitted: (text) =>
                  Navigator.pop(dialogContext, int.tryParse(text.trim())),
            ),
            const SizedBox(height: 10),
            Text(
              'Больший контекст требует больше памяти. '
              'Значение применяется при загрузке модели.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              int.tryParse(controller.text.trim()),
            ),
            child: const Text('ОК'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    var tokens = value < 256 ? 256 : value;
    if (max != null && tokens > max) tokens = max;
    _update(_launch.copyWith(contextLength: tokens));
  }

  Future<void> _apply() async {
    final state = context.read<AppState>();
    final chat = _chat;
    if (chat == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _warning = null;
      _command = null;
    });
    final result = await state.applyLaunchSettings(chat);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.error;
      _warning = result.warning;
      _command = result.command;
    });
    if (result.ok && result.warning == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              result.viaBridge
                  ? L10n.tf('Загружено через мостик · {context}', {
                      'context': formatContext(_launch.contextLength),
                    })
                  : L10n.tf('Модель загружена · {context}', {
                      'context': formatContext(_launch.contextLength),
                    }),
            ),
          ),
        );
    }
  }

  Future<void> _unload() async {
    final state = context.read<AppState>();
    final chat = _chat;
    if (chat == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _warning = null;
      _command = null;
    });
    final error = await state.unloadChatModel(chat);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Модель выгружена')));
    }
  }

  Future<void> _estimate() async {
    final chat = _chat;
    if (chat == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await context.read<AppState>().estimateLaunch(chat);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.error != null) {
      setState(() => _error = result.error);
      return;
    }
    final text = stripAnsi(result.output).trim();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Оценка памяти'),
        content: SingleChildScrollView(
          child: SelectableText(
            text.isEmpty ? 'Мостик вернул пустой ответ' : text,
            style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  List<int> get _contextOptions {
    final max = _info?.maxContextLength;
    final options = _contextPresets
        .where((value) => max == null || value <= max)
        .toList();
    final current = _launch.contextLength;
    if (current != null &&
        current > 0 &&
        !options.contains(current) &&
        (max == null || current <= max)) {
      options.add(current);
      options.sort();
    }
    return options;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final chat = state.activeChat;
    final info = infoOrNull(state);
    final server = state.serverById(chat?.serverId) ?? state.activeServer;
    final bridge = !widget.defaults && (server?.hasBridge ?? false);
    final loaded = info?.isLoaded ?? false;
    final loadedContext = info?.instance?.contextLength;
    final modelName = widget.defaults
        ? null
        : (chat?.model.isNotEmpty == true
              ? (info?.displayName ?? chat!.model)
              : 'Модель не выбрана');

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  widget.defaults ? 'Запуск по умолчанию' : 'Запуск модели',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                if (!widget.defaults)
                  IconButton(
                    onPressed: _refreshing || _busy ? null : _refresh,
                    icon: _refreshing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                    tooltip: L10n.t('Обновить состояние'),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              widget.defaults ? 'Применяются к новым чатам' : modelName ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            if (!widget.defaults)
              _StatusCard(
                loaded: loaded,
                loadedContext: loadedContext,
                desiredContext: _launch.contextLength,
                modelMissing: chat?.model.isEmpty ?? true,
              ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _launch.loadOnDemand,
              onChanged: (value) =>
                  _update(_launch.copyWith(loadOnDemand: value)),
              title: const Text('Загрузка модели по требованию'),
              subtitle: const Text(
                'Отправлять запрос сразу, не проверяя память заранее: '
                'LM Studio загрузит модель сама. Контекст и параметры ниже '
                'в этом режиме применяются только по кнопке «Загрузить».',
              ),
            ),
            const Divider(height: 12),
            _SectionTitle(
              title: 'Контекстное окно',
              hint: info?.maxContextLength == null
                  ? null
                  : L10n.tf('до {value}', {
                      'value': formatNumber(info!.maxContextLength!),
                    }),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Авто'),
                  selected: _launch.contextLength == null,
                  onSelected: (_) =>
                      _update(_launch.copyWith(contextLength: null)),
                ),
                for (final tokens in _contextOptions)
                  ChoiceChip(
                    label: Text(formatNumber(tokens)),
                    selected: _launch.contextLength == tokens,
                    onSelected: (_) =>
                        _update(_launch.copyWith(contextLength: tokens)),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.edit_rounded, size: 15),
                  label: const Text('Своё'),
                  onPressed: _pickCustomContext,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              L10n.tf(
                'Сейчас: {value}. Больше контекста — больше оперативной памяти.',
                {'value': formatContext(_launch.contextLength)},
              ),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const Divider(height: 24),
            _SectionTitle(
              title: 'Автовыгрузка простоя (TTL)',
              hint: formatDuration(_launch.ttlSeconds),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final ttl in _ttlPresets)
                  ChoiceChip(
                    label: Text(ttl == null ? 'Сервер' : formatDuration(ttl)),
                    selected: _launch.ttlSeconds == ttl,
                    onSelected: (_) =>
                        _update(_launch.copyWith(ttlSeconds: ttl)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '«Сервер» — использовать значение из настроек LM Studio '
              '(по умолчанию 60 минут).',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const Divider(height: 24),
            _SectionTitle(
              title: 'Передача на GPU',
              hint: formatGpuRatio(_launch.gpuRatio),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Авто'),
                  selected: _launch.gpuRatio == null,
                  onSelected: (_) => _update(_launch.copyWith(gpuRatio: null)),
                ),
                for (final ratio in const [0.0, 0.25, 0.5, 0.75, 1.0])
                  ChoiceChip(
                    label: Text(
                      ratio <= 0 ? 'CPU' : '${(ratio * 100).round()}%',
                    ),
                    selected: _launch.gpuRatio == ratio,
                    onSelected: (_) =>
                        _update(_launch.copyWith(gpuRatio: ratio)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              bridge
                  ? 'Загрузка идёт через мостик на Ubuntu: 100% → --gpu max, '
                        'CPU → --gpu off, промежуточные значения — доля слоёв. '
                        'Контекст и TTL тоже передаются. Flash Attention и '
                        'KV-кэш мостик не меняет — они задаются в LM Studio.'
                  : 'Сколько модели выгрузить в видеопамять: CPU — только '
                        'процессор, 100% — максимум слоёв. «Авто» — значение из '
                        'LM Studio. REST-API 0.4 может не принимать этот '
                        'параметр — тогда модель загрузится по настройкам '
                        'сервера, а приложение покажет команду lms load --gpu.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            if (bridge)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Icon(Icons.cable_rounded, size: 16, color: scheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        L10n.tf('Мостик: {value}', {
                          'value': server!.normalizedBridge
                              .replaceFirst('http://', '')
                              .replaceFirst('https://', ''),
                        }),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: scheme.primary),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _estimate,
                      icon: const Icon(Icons.calculate_outlined, size: 16),
                      label: const Text('Оценить память'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 24),
            _SectionTitle(title: 'Параметры загрузки', hint: 'llama.cpp'),
            const SizedBox(height: 8),
            _TriChoice(
              label: 'Flash Attention',
              value: _launch.flashAttention,
              onChanged: (value) =>
                  _update(_launch.copyWith(flashAttention: value)),
            ),
            const SizedBox(height: 4),
            _TriChoice(
              label: 'KV-кэш на GPU',
              value: _launch.offloadKvCache,
              onChanged: (value) =>
                  _update(_launch.copyWith(offloadKvCache: value)),
            ),
            const SizedBox(height: 12),
            Text(
              'Eval batch size',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final size in _batchPresets)
                  ChoiceChip(
                    label: Text(size == null ? 'Авто' : formatNumber(size)),
                    selected: _launch.evalBatchSize == size,
                    onSelected: (_) =>
                        _update(_launch.copyWith(evalBatchSize: size)),
                  ),
              ],
            ),
            if (_error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, size: 17, color: scheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_warning != null)
              _WarningCard(text: _warning!, command: _command),
            const SizedBox(height: 16),
            if (widget.defaults)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Готово'),
                ),
              )
            else
              Row(
                children: [
                  if (loaded)
                    TextButton.icon(
                      onPressed: _busy ? null : _unload,
                      icon: const Icon(Icons.eject_rounded, size: 18),
                      label: const Text('Выгрузить'),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _busy || (chat?.model.isEmpty ?? true)
                        ? null
                        : _apply,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.memory_rounded, size: 18),
                    label: Text(loaded ? 'Перезагрузить' : 'Загрузить'),
                  ),
                ],
              ),
            const SizedBox(height: 4),
            if (!widget.defaults)
              Text(
                'Параметры сохраняются сразу и применяются при следующей '
                'загрузке модели.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  LmModelInfo? infoOrNull(AppState state) {
    final chat = state.activeChat;
    if (chat == null) return null;
    return state.modelInfo(chat.serverId, chat.model);
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.loaded,
    required this.loadedContext,
    required this.desiredContext,
    required this.modelMissing,
  });

  final bool loaded;
  final int? loadedContext;
  final int? desiredContext;
  final bool modelMissing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mismatch =
        loaded &&
        loadedContext != null &&
        desiredContext != null &&
        loadedContext != desiredContext;
    final color = modelMissing
        ? scheme.onSurfaceVariant
        : (loaded && !mismatch)
        ? scheme.primary
        : scheme.tertiary;
    final text = modelMissing
        ? L10n.t('Сначала выберите модель')
        : mismatch
        ? L10n.tf(
            'Загружена с контекстом {loaded}, выбран {desired} — нажмите «Перезагрузить».',
            {
              'loaded': formatNumber(loadedContext!),
              'desired': formatNumber(desiredContext!),
            },
          )
        : loaded
        ? loadedContext == null
              ? L10n.t('Загружена')
              : L10n.tf('Загружена · контекст {context}', {
                  'context': formatNumber(loadedContext!),
                })
        : L10n.t(
            'Не загружена · загрузится при первом сообщении или по кнопке ниже',
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            mismatch
                ? Icons.sync_problem_rounded
                : loaded
                ? Icons.check_circle_rounded
                : Icons.memory_rounded,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: color, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.text, this.command});

  final String text;
  final String? command;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 17,
                color: scheme.onTertiaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  text,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
          if (command != null)
            Container(
              margin: const EdgeInsets.only(top: 8, left: 25),
              padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      command!,
                      style: TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 11.5,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: command!));
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(content: Text('Команда скопирована')),
                        );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    tooltip: L10n.t('Копировать команду'),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        if (hint != null)
          Text(
            hint!,
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

class _TriChoice extends StatelessWidget {
  const _TriChoice({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = value == null ? -1 : (value! ? 1 : 0);
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5))),
        SegmentedButton<int>(
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          segments: const [
            ButtonSegment(value: -1, label: Text('Авто')),
            ButtonSegment(value: 1, label: Text('Вкл')),
            ButtonSegment(value: 0, label: Text('Выкл')),
          ],
          selected: {current},
          onSelectionChanged: (selection) {
            final next = selection.first;
            onChanged(next == -1 ? null : next == 1);
          },
        ),
      ],
    );
  }
}
