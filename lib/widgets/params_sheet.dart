import 'package:flutter/material.dart' hide Text;
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../format_utils.dart';
import '../l10n_text.dart';
import '../models.dart';
import 'model_settings_sheet.dart';
import 'prompt_library_sheet.dart';

Future<void> showChatParams(
  BuildContext context, {
  bool defaults = false,
}) async {
  final state = context.read<AppState>();
  final chat = state.activeChat;
  if (!defaults && chat == null) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ParamsSheet(chat: chat, defaults: defaults),
  );
}

class _ParamsSheet extends StatefulWidget {
  const _ParamsSheet({required this.chat, required this.defaults});

  final ChatSession? chat;
  final bool defaults;

  @override
  State<_ParamsSheet> createState() => _ParamsSheetState();
}

class _ParamsSheetState extends State<_ParamsSheet> {
  late double _temperature;
  late double _topP;
  late int _topK;
  late double _repeatPenalty;
  late final TextEditingController _maxTokens;
  late final TextEditingController _system;
  late ResponseFormatMode _formatMode;
  late final TextEditingController _schema;
  late final TextEditingController _grammar;
  String? _formatError;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    final chat = widget.chat;
    _temperature = widget.defaults
        ? state.data.defaultTemperature
        : (chat?.temperature ?? state.data.defaultTemperature);
    _topP = widget.defaults
        ? state.data.defaultTopP
        : (chat?.topP ?? state.data.defaultTopP);
    _topK = widget.defaults
        ? state.data.defaultTopK
        : (chat?.topK ?? state.data.defaultTopK);
    _repeatPenalty = widget.defaults
        ? state.data.defaultRepeatPenalty
        : (chat?.repeatPenalty ?? state.data.defaultRepeatPenalty);
    final maxTokens = widget.defaults
        ? state.data.defaultMaxTokens
        : (chat?.maxTokens ?? state.data.defaultMaxTokens);
    _maxTokens = TextEditingController(
      text: maxTokens > 0 ? maxTokens.toString() : '',
    );
    _system = TextEditingController(
      text: widget.defaults
          ? state.data.defaultSystemPrompt
          : (chat?.systemPrompt ?? ''),
    );
    final format = widget.defaults
        ? state.data.defaultResponseFormat
        : (chat?.responseFormat ?? state.data.defaultResponseFormat);
    _formatMode = format.mode;
    _schema = TextEditingController(text: format.schema);
    _grammar = TextEditingController(text: format.grammar);
  }

  @override
  void dispose() {
    _maxTokens.dispose();
    _system.dispose();
    _schema.dispose();
    _grammar.dispose();
    super.dispose();
  }

  void _reset() {
    final state = context.read<AppState>();
    setState(() {
      _temperature = state.data.defaultTemperature;
      _topP = state.data.defaultTopP;
      _topK = state.data.defaultTopK;
      _repeatPenalty = state.data.defaultRepeatPenalty;
      _maxTokens.text = state.data.defaultMaxTokens > 0
          ? state.data.defaultMaxTokens.toString()
          : '';
      _system.text = state.data.defaultSystemPrompt;
      final format = state.data.defaultResponseFormat;
      _formatMode = format.mode;
      _schema.text = format.schema;
      _grammar.text = format.grammar;
      _formatError = null;
    });
  }

  void _save() {
    if (!_apply()) return;
    Navigator.of(context).pop();
  }

  /// Persists the fields without closing the sheet, so opening the launch
  /// settings afterwards does not discard unsaved edits.
  bool _apply() {
    final state = context.read<AppState>();
    final maxTokens = int.tryParse(_maxTokens.text.trim()) ?? -1;
    final format = ResponseFormat(
      mode: _formatMode,
      schema: _schema.text,
      grammar: _grammar.text,
    );
    final error = format.validationError;
    if (error != null) {
      setState(() => _formatError = L10n.t(error));
      return false;
    }
    setState(() => _formatError = null);
    if (widget.defaults) {
      state.updateDefaults(
        temperature: _temperature,
        topP: _topP,
        topK: _topK,
        repeatPenalty: _repeatPenalty,
        maxTokens: maxTokens,
        systemPrompt: _system.text,
        responseFormat: format,
      );
    } else {
      state.updateChatParams(
        widget.chat!,
        temperature: _temperature,
        topP: _topP,
        topK: _topK,
        repeatPenalty: _repeatPenalty,
        maxTokens: maxTokens,
        systemPrompt: _system.text,
        responseFormat: format,
      );
    }
    return true;
  }

  void _openLaunch() {
    if (!_apply()) return;
    showModelSettings(context, defaults: widget.defaults);
  }

  void _fillSchemaExample() {
    setState(() {
      _schema.text =
          '{\n'
          '  "type": "object",\n'
          '  "properties": {\n'
          '    "answer": { "type": "string" }\n'
          '  },\n'
          '  "required": ["answer"],\n'
          '  "additionalProperties": false\n'
          '}';
      _formatError = null;
    });
  }

  void _selectFormat(ResponseFormatMode mode) {
    setState(() {
      _formatMode = mode;
      _formatError = null;
    });
  }

  Future<void> _pickPrompt() async {
    await showPromptLibrary(
      context,
      onSelect: (content) => setState(() => _system.text = content),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final launch = widget.defaults
        ? state.data.defaultLaunch
        : (widget.chat?.launch ?? state.data.defaultLaunch);
    final launchSummary = [
      launch.loadOnDemand ? 'по требованию' : 'заранее',
      'контекст: ${formatContext(launch.contextLength)}',
      if (launch.gpuRatio != null) 'GPU: ${formatGpuRatio(launch.gpuRatio)}',
      if (launch.ttlSeconds != null)
        'TTL: ${formatDuration(launch.ttlSeconds)}',
    ].join(' · ');
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
            Text(
              widget.defaults ? 'Параметры по умолчанию' : 'Параметры чата',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Значения применяются к новым сообщениям',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            _SliderRow(
              label: 'Temperature',
              value: _temperature,
              min: 0,
              max: 2,
              divisions: 40,
              onChanged: (v) => setState(() => _temperature = v),
            ),
            _SliderRow(
              label: 'Top P',
              value: _topP,
              min: 0,
              max: 1,
              divisions: 20,
              onChanged: (v) => setState(() => _topP = v),
            ),
            _SliderRow(
              label: 'Top K',
              value: _topK.toDouble(),
              min: 0,
              max: 100,
              divisions: 100,
              format: (value) =>
                  value <= 0 ? L10n.t('авто') : value.toStringAsFixed(0),
              onChanged: (v) => setState(() => _topK = v.round()),
            ),
            _SliderRow(
              label: 'Repeat penalty',
              value: _repeatPenalty,
              min: 1,
              max: 1.3,
              divisions: 6,
              format: (value) =>
                  value <= 1.001 ? L10n.t('выкл') : value.toStringAsFixed(2),
              onChanged: (v) => setState(() => _repeatPenalty = v),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Gemma: temperature 1.0, top_p 0.95, top_k 64, '
                      'repeat penalty 1.1',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _temperature = 1;
                      _topP = 0.95;
                      _topK = 64;
                      _repeatPenalty = 1.1;
                    }),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Применить'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _maxTokens,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Max tokens',
                hintText: L10n.t('Пусто или -1 — без ограничения'),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Формат ответа',
              style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _FormatChip(
                  label: 'Обычный текст',
                  selected: _formatMode == ResponseFormatMode.text,
                  onTap: () => _selectFormat(ResponseFormatMode.text),
                ),
                _FormatChip(
                  label: 'JSON',
                  selected: _formatMode == ResponseFormatMode.json,
                  onTap: () => _selectFormat(ResponseFormatMode.json),
                ),
                _FormatChip(
                  label: 'JSON по схеме',
                  selected: _formatMode == ResponseFormatMode.jsonSchema,
                  onTap: () => _selectFormat(ResponseFormatMode.jsonSchema),
                ),
                _FormatChip(
                  label: 'GBNF',
                  selected: _formatMode == ResponseFormatMode.grammar,
                  onTap: () => _selectFormat(ResponseFormatMode.grammar),
                ),
              ],
            ),
            if (_formatMode == ResponseFormatMode.json)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Модель вернёт только JSON-объект.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (_formatMode == ResponseFormatMode.jsonSchema) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'JSON Schema. LM Studio превращает её в грамматику '
                      'для GGUF-моделей.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _fillSchemaExample,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Пример'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _schema,
                minLines: 5,
                maxLines: 12,
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 12.5,
                ),
                onChanged: (_) {
                  if (_formatError != null) {
                    setState(() => _formatError = null);
                  }
                },
                decoration: InputDecoration(
                  labelText: 'JSON Schema',
                  hintText: '{"type": "object", "properties": {…}}',
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                  errorText: _formatError,
                ),
              ),
            ],
            if (_formatMode == ResponseFormatMode.grammar) ...[
              const SizedBox(height: 8),
              Text(
                'GBNF-грамматика. Поддерживается llama.cpp-совместимыми '
                'серверами; LM Studio может проигнорировать это поле.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _grammar,
                minLines: 4,
                maxLines: 10,
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 12.5,
                ),
                onChanged: (_) {
                  if (_formatError != null) {
                    setState(() => _formatError = null);
                  }
                },
                decoration: InputDecoration(
                  labelText: 'GBNF',
                  hintText: 'root ::= "да" | "нет"',
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                  errorText: _formatError,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'System prompt',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _pickPrompt,
                  icon: const Icon(Icons.bookmarks_outlined, size: 17),
                  label: const Text('Из библиотеки'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _system,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: L10n.t('Например: отвечай кратко и по-русски'),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.memory_rounded),
              title: const Text('Запуск модели'),
              subtitle: Text(
                launchSummary,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _openLaunch,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton(onPressed: _reset, child: const Text('Сбросить')),
                const Spacer(),
                FilledButton(onPressed: _save, child: const Text('Сохранить')),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _FormatChip extends StatelessWidget {
  const _FormatChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.format,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final String Function(double value)? format;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 14)),
            const Spacer(),
            Text(
              format?.call(value) ?? value.toStringAsFixed(2),
              style: TextStyle(
                fontSize: 13,
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
