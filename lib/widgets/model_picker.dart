import 'package:flutter/material.dart' hide Text;
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../format_utils.dart';
import '../l10n_text.dart';
import '../models.dart';

Future<void> showModelPicker(BuildContext context) async {
  if (context.read<AppState>().activeChat == null) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _ModelPickerSheet(),
  );
}

class _ModelPickerSheet extends StatefulWidget {
  const _ModelPickerSheet();

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  late String _serverId;
  List<LmModelInfo> _models = const [];
  String _query = '';
  String? _error;
  bool _loading = false;
  bool _onlyLoaded = false;
  bool _onlyVision = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _serverId = state.activeChat?.serverId ?? state.activeServer?.id ?? '';
    _models = state.modelsFor(_serverId);
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final server = state.serverById(_serverId) ?? state.activeServer;
    if (server == null) return;
    if (mounted) {
      setState(() {
        _serverId = server.id;
        _loading = true;
        _error = null;
      });
    }
    final result = await state.refreshModels(server);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _models = result.models;
      _error = result.error;
    });
  }

  void _choose(LmModelInfo model) {
    final state = context.read<AppState>();
    final chat = state.activeChat;
    if (chat == null) return;
    final server = state.serverById(_serverId);
    if (server != null) state.setChatServer(chat, server);
    state.setChatModel(chat, model.key);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final chat = state.activeChat;
    final query = _query.toLowerCase();
    final filtered = _models
        .where((m) => m.isLlm)
        .where((m) => !_onlyLoaded || m.isLoaded)
        .where((m) => !_onlyVision || m.vision)
        .where(
          (m) =>
              query.isEmpty ||
              m.displayName.toLowerCase().contains(query) ||
              m.key.toLowerCase().contains(query),
        )
        .toList();

    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Модель', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  onPressed: _loading ? null : _load,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  tooltip: L10n.t('Обновить список'),
                ),
              ],
            ),
            if (state.servers.length > 1)
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: state.servers.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final server = state.servers[index];
                    final selected = server.id == _serverId;
                    return ChoiceChip(
                      label: Text(server.name),
                      selected: selected,
                      onSelected: (_) {
                        setState(() {
                          _serverId = server.id;
                          _models = state.modelsFor(server.id);
                        });
                        _load();
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 10),
            if (_models.length > 8)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: L10n.t('Поиск модели'),
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('В памяти'),
                    selected: _onlyLoaded,
                    onSelected: (value) => setState(() => _onlyLoaded = value),
                  ),
                  FilterChip(
                    label: const Text('Vision'),
                    selected: _onlyVision,
                    onSelected: (value) => setState(() => _onlyVision = value),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: _loading
                          ? const CircularProgressIndicator()
                          : Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _error == null
                                    ? 'Сервер не вернул ни одной модели.\n'
                                          'Загрузите модель в LM Studio.'
                                    : 'Не удалось получить список моделей.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final model = filtered[index];
                        final selected = model.key == chat?.model;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          leading: Icon(
                            selected
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: selected ? scheme.primary : scheme.outline,
                            size: 20,
                          ),
                          title: Text(
                            model.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: selected
                                  ? scheme.primary
                                  : scheme.onSurface,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                          subtitle: _ModelMeta(model: model),
                          trailing: model.isLoaded
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.primary.withValues(
                                      alpha: 0.14,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'в памяти',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.primary,
                                    ),
                                  ),
                                )
                              : null,
                          onTap: () => _choose(model),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Контекст, TTL и параметры загрузки — в меню «Запуск модели» '
                'на экране чата.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelMeta extends StatelessWidget {
  const _ModelMeta({required this.model});

  final LmModelInfo model;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11.5,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final parts = <String>[
      if (model.parameters != null && model.parameters!.isNotEmpty)
        model.parameters!,
      if (model.quantization != null && model.quantization!.isNotEmpty)
        model.quantization!,
      if (model.maxContextLength != null)
        L10n.tf('контекст до {value}', {
          'value': formatNumber(model.maxContextLength!),
        }),
      if (model.sizeBytes != null) formatSize(model.sizeBytes),
      if (model.vision) 'vision',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

String serverLabel(ServerConfig server) {
  final base = server.normalizedBase;
  return base.replaceFirst('http://', '').replaceFirst('https://', '');
}
