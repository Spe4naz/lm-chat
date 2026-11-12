import 'package:flutter/material.dart' hide Text;

import '../app_state.dart';
import '../l10n_text.dart';

/// Asks which chats from an imported JSON should be added.
///
/// Returns null when the user cancels, otherwise a set of 0-based indexes into
/// [ImportPreview.chats].
Future<Set<int>?> showImportPreview(
  BuildContext context,
  ImportPreview preview,
) {
  return showModalBottomSheet<Set<int>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ImportPreviewSheet(preview: preview),
  );
}

class _ImportPreviewSheet extends StatefulWidget {
  const _ImportPreviewSheet({required this.preview});

  final ImportPreview preview;

  @override
  State<_ImportPreviewSheet> createState() => _ImportPreviewSheetState();
}

class _ImportPreviewSheetState extends State<_ImportPreviewSheet> {
  late Set<int> _selected = {
    for (var i = 0; i < widget.preview.chats.length; i++) i,
  };

  void _toggle(int index, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(index);
      } else {
        _selected.remove(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = widget.preview;
    final allSelected = _selected.length == preview.chats.length;

    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Импорт истории',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    if (allSelected) {
                      _selected.clear();
                    } else {
                      _selected = {
                        for (var i = 0; i < preview.chats.length; i++) i,
                      };
                    }
                  }),
                  child: Text(allSelected ? 'Снять все' : 'Выбрать все'),
                ),
              ],
            ),
            Text(
              L10n.tf('Чатов: {chats} · сообщений: {messages}', {
                'chats': preview.chats.length,
                'messages': preview.messageCount,
              }),
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            if (preview.servers.isNotEmpty || preview.templates.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  [
                    if (preview.servers.isNotEmpty)
                      L10n.tf('серверов: {count}', {
                        'count': preview.servers.length,
                      }),
                    if (preview.templates.isNotEmpty)
                      L10n.tf('промптов: {count}', {
                        'count': preview.templates.length,
                      }),
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: preview.chats.length,
                itemBuilder: (context, index) {
                  final chat = preview.chats[index];
                  final selected = _selected.contains(index);
                  return CheckboxListTile(
                    value: selected,
                    onChanged: (value) => _toggle(index, value ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      chat.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${chat.messages.length} сообщений'
                      '${chat.model.isEmpty ? '' : ' · ${chat.model}'}'
                      '${chat.archived ? ' · архив' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    contentPadding: EdgeInsets.zero,
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_selected),
                child: Text(
                  _selected.isEmpty
                      ? L10n.t('Выберите чаты')
                      : L10n.tf('Импортировать ({count})', {
                          'count': _selected.length,
                        }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
