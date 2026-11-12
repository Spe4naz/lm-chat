import 'package:flutter/material.dart' hide Text;

import '../l10n_text.dart';

import '../models.dart';

/// Shows every saved answer of one message, newest first.
///
/// [onSelect] and [onDelete] receive the 1-based version number; the newest
/// answer is number [ChatMessage.versionCount].
Future<void> showVersionsSheet(
  BuildContext context, {
  required ChatMessage message,
  required ValueChanged<int> onSelect,
  required ValueChanged<int> onDelete,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _VersionsSheet(
      message: message,
      onSelect: onSelect,
      onDelete: onDelete,
    ),
  );
}

class _VersionsSheet extends StatefulWidget {
  const _VersionsSheet({
    required this.message,
    required this.onSelect,
    required this.onDelete,
  });

  final ChatMessage message;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onDelete;

  @override
  State<_VersionsSheet> createState() => _VersionsSheetState();
}

class _VersionsSheetState extends State<_VersionsSheet> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message = widget.message;
    final count = message.versionCount;
    final selected = message.displayedVersionNumber;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 20,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Варианты ответа',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    count == 1
                        ? L10n.t('Сохранён один ответ')
                        : L10n.tf(
                            'Сохранено ответов: {count}. Предыдущие варианты остаются на телефоне.',
                            {'count': count},
                          ),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: count,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final number = count - index;
                  return _VersionTile(
                    message: message,
                    number: number,
                    isLatest: number == count,
                    isSelected: number == selected,
                    onSelect: () {
                      widget.onSelect(number);
                      Navigator.of(context).pop();
                    },
                    onDelete: number == count
                        ? null
                        : () {
                            widget.onDelete(number);
                            setState(() {});
                            if (message.versionCount == 1) {
                              Navigator.of(context).pop();
                            }
                          },
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

class _VersionTile extends StatelessWidget {
  const _VersionTile({
    required this.message,
    required this.number,
    required this.isLatest,
    required this.isSelected,
    required this.onSelect,
    this.onDelete,
  });

  final ChatMessage message;
  final int number;
  final bool isLatest;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final variant = message.variantAt(number);
    final content = variant.content.trim();
    final reasoning = variant.reasoning.trim();
    final error = variant.error?.trim();
    final preview = content.isNotEmpty
        ? content
        : reasoning.isNotEmpty
        ? reasoning
        : error?.isNotEmpty == true
        ? error!
        : L10n.t('Пустой ответ');

    final meta = <String>[
      if (variant.model.isNotEmpty) variant.model,
      _formatDate(variant.createdAt),
      if (variant.editedAt != null) L10n.t('изменён'),
      if (error?.isNotEmpty == true) L10n.t('ошибка'),
    ];

    return InkWell(
      onTap: onSelect,
      child: Container(
        color: isSelected
            ? scheme.primaryContainer.withValues(alpha: 0.25)
            : null,
        padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        L10n.tf('Вариант {number}', {'number': number}),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? scheme.primary : scheme.onSurface,
                        ),
                      ),
                      if (isLatest) ...[
                        const SizedBox(width: 8),
                        _Badge(text: L10n.t('новый'), scheme: scheme),
                      ],
                      if (isSelected) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.check_circle_rounded,
                          size: 15,
                          color: scheme.primary,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      meta.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                tooltip: L10n.t('Удалить вариант'),
                color: scheme.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day.$month $hour:$minute';
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.scheme});

  final String text;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: scheme.primary,
        ),
      ),
    );
  }
}
