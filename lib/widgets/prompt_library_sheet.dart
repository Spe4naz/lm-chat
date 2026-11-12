import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart' hide Text;
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n_text.dart';
import '../models.dart';

/// Shows built-in and user prompt templates.
///
/// With [onSelect] the sheet works as a picker: tapping a template returns its
/// content to the caller. Without it the sheet manages the library and opens a
/// preview on tap.
Future<void> showPromptLibrary(
  BuildContext context, {
  ValueChanged<String>? onSelect,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PromptLibrarySheet(onSelect: onSelect),
  );
}

class _PromptLibrarySheet extends StatefulWidget {
  const _PromptLibrarySheet({this.onSelect});

  final ValueChanged<String>? onSelect;

  @override
  State<_PromptLibrarySheet> createState() => _PromptLibrarySheetState();
}

class _PromptLibrarySheetState extends State<_PromptLibrarySheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<PromptTemplate> _filtered(List<PromptTemplate> templates) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return templates;
    return templates
        .where(
          (template) =>
              _name(template).toLowerCase().contains(query) ||
              _content(template).toLowerCase().contains(query),
        )
        .toList();
  }

  /// Built-in templates are localized; user prompts stay verbatim so a
  /// fragment of another translation can never rewrite them.
  String _name(PromptTemplate template) =>
      template.builtIn ? L10n.t(template.name) : template.name;

  String _content(PromptTemplate template) =>
      template.builtIn ? L10n.t(template.content) : template.content;

  void _use(PromptTemplate template) {
    final content = _content(template);
    if (widget.onSelect != null) {
      widget.onSelect!(content);
      Navigator.of(context).pop();
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: material.Text(_name(template)),
        content: SingleChildScrollView(child: SelectableText(content)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Future<void> _edit([PromptTemplate? template]) async {
    final result = await showDialog<PromptTemplate>(
      context: context,
      builder: (_) => _PromptEditorDialog(template: template),
    );
    if (!mounted || result == null) return;
    final state = context.read<AppState>();
    if (template == null) {
      state.addPromptTemplate(result);
    } else {
      state.updatePromptTemplate(result);
    }
  }

  Future<void> _delete(PromptTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить шаблон?'),
        content: material.Text(
          L10n.tf('«{name}» будет удалён.', {'name': template.name}),
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
      context.read<AppState>().deletePromptTemplate(template.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final templates = _filtered(state.allPromptTemplates);

    return FractionallySizedBox(
      heightFactor: 0.82,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  widget.onSelect == null ? 'Библиотека промптов' : 'Промпты',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _edit(),
                  icon: const Icon(Icons.add_rounded),
                  tooltip: L10n.t('Новый шаблон'),
                ),
              ],
            ),
            Text(
              widget.onSelect == null
                  ? 'Встроенные шаблоны и ваши собственные'
                  : 'Выберите готовый системный промпт',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: L10n.t('Поиск по названию или тексту'),
                prefixIcon: Icon(Icons.search_rounded, size: 20),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: templates.isEmpty
                  ? Center(
                      child: Text(
                        _query.isEmpty
                            ? 'Пока нет шаблонов'
                            : 'Ничего не найдено',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      itemCount: templates.length,
                      itemBuilder: (context, index) {
                        final template = templates[index];
                        final name = _name(template);
                        final content = _content(template);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            leading: Icon(
                              template.builtIn
                                  ? Icons.auto_awesome_rounded
                                  : Icons.bookmark_outline_rounded,
                              color: template.builtIn
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                            title: material.Text(name),
                            subtitle: material.Text(
                              content,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: template.builtIn
                                ? null
                                : PopupMenuButton<String>(
                                    onSelected: (value) {
                                      switch (value) {
                                        case 'edit':
                                          _edit(template);
                                        case 'delete':
                                          _delete(template);
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Изменить'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Удалить'),
                                      ),
                                    ],
                                  ),
                            onTap: () => _use(template),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptEditorDialog extends StatefulWidget {
  const _PromptEditorDialog({this.template});

  final PromptTemplate? template;

  @override
  State<_PromptEditorDialog> createState() => _PromptEditorDialogState();
}

class _PromptEditorDialogState extends State<_PromptEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _content;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.template?.name ?? '');
    _content = TextEditingController(text: widget.template?.content ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _content.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final content = _content.text.trim();
    if (name.isEmpty || content.isEmpty) return;
    Navigator.pop(
      context,
      PromptTemplate(
        id: widget.template?.id ?? newId(),
        name: name,
        content: content,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.template == null ? 'Новый шаблон' : 'Изменить шаблон'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(labelText: L10n.t('Название')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _content,
              minLines: 4,
              maxLines: 10,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: L10n.t('Системный промпт'),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(onPressed: _save, child: const Text('Сохранить')),
      ],
    );
  }
}
