import 'package:flutter/material.dart' hide Text;

import '../app_state.dart';
import '../format_utils.dart';
import '../l10n_text.dart';
import '../theme.dart';

/// Slim strip above the composer: how much context window is still free.
class ContextIndicator extends StatelessWidget {
  const ContextIndicator({super.key, required this.usage, this.onTap});

  final ContextUsage usage;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final free = 1 - usage.fraction;
    final color = free <= 0.1
        ? scheme.error
        : free <= 0.2
        ? colors.warning
        : scheme.onSurfaceVariant;
    final text = L10n.tf(
      'Контекст: {estimated}осталось {remaining} из {limit}',
      {
        'estimated': usage.estimated ? '≈ ' : '',
        'remaining': formatNumber(usage.remaining),
        'limit': formatNumber(usage.limit),
      },
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.memory_rounded, size: 13, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${(usage.fraction * 100).round()}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: color,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.info_outline_rounded, size: 13, color: color),
              ],
            ),
            if (usage.fraction >= 0.7) ...[
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: usage.fraction,
                  minHeight: 2,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Explains where the context numbers come from.
Future<void> showContextDetails(BuildContext context, ContextUsage usage) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.memory_rounded, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Контекст модели',
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: usage.fraction,
                  minHeight: 8,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    usage.fraction >= 0.9
                        ? scheme.error
                        : usage.fraction >= 0.8
                        ? AppColors.of(context).warning
                        : scheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _ContextRow(
                label: 'Осталось',
                value: L10n.tf('{tokens} токенов', {
                  'tokens':
                      '${usage.estimated ? '≈ ' : ''}${formatNumber(usage.remaining)}',
                }),
                strong: true,
              ),
              _ContextRow(label: 'Занято', value: formatNumber(usage.used)),
              _ContextRow(label: 'Лимит', value: formatNumber(usage.limit)),
              _ContextRow(label: 'Источник лимита', value: usage.source),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  usage.estimated
                      ? 'Часть подсчёта приблизительная: LM Studio не вернула '
                            'точный usage, либо после последнего ответа появились '
                            'новые сообщения. Цифры обновятся после следующего '
                            'ответа.'
                      : 'Занято = системный промпт + все сообщения + последний '
                            'ответ. Когда остаток закончится, начните новый чат '
                            'или увеличьте контекст в настройках запуска.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ContextRow extends StatelessWidget {
  const _ContextRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: strong ? 15 : 13,
              fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
              color: strong ? scheme.primary : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
