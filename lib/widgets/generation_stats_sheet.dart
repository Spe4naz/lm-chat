import 'package:flutter/material.dart' hide Text;

import '../app_state.dart';
import '../format_utils.dart';
import '../l10n_text.dart';
import '../models.dart';

/// Opens a compact card with token counts, speed and time of one answer.
Future<void> showGenerationStats(
  BuildContext context, {
  required ChatMessage message,
  ContextUsage? contextUsage,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _StatsSheet(message: message, contextUsage: contextUsage),
  );
}

class _StatsSheet extends StatelessWidget {
  const _StatsSheet({required this.message, this.contextUsage});

  final ChatMessage message;
  final ContextUsage? contextUsage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final estimated = message.displayTokensEstimated;
    final speed = message.displayTokensPerSecond;
    final time = formatGenerationTime(message.displayGenerationMs);
    final completion = message.displayCompletionTokens;
    final prompt = message.displayPromptTokens;
    final total = message.displayTotalTokens;
    final prefix = estimated ? '≈ ' : '';

    String tokens(int? value) =>
        value == null ? '—' : '$prefix${formatNumber(value)}';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.speed_rounded, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Статистика ответа',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    label: 'Скорость',
                    value: speed == null
                        ? '—'
                        : '$prefix${speed.toStringAsFixed(1)}',
                    unit: 'tok/s',
                    scheme: scheme,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricTile(
                    label: 'Время',
                    value: time.isEmpty ? '—' : time,
                    unit: 'от запроса до конца',
                    scheme: scheme,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 10),
            _StatRow(
              label: 'Модель',
              value: message.displayModel.isEmpty ? '—' : message.displayModel,
            ),
            _StatRow(
              label: 'Вариант',
              value: L10n.tf('{current} из {count}', {
                'current': message.displayedVersionNumber,
                'count': message.versionCount,
              }),
            ),
            _StatRow(
              label: 'Первый токен',
              value:
                  message.displayFirstTokenMs == null ||
                      message.displayFirstTokenMs! <= 0
                  ? '—'
                  : formatGenerationTime(message.displayFirstTokenMs),
            ),
            _StatRow(label: 'Токены запроса', value: tokens(prompt)),
            _StatRow(label: 'Токены ответа', value: tokens(completion)),
            _StatRow(label: 'Всего токенов', value: tokens(total)),
            if (contextUsage != null) ...[
              const SizedBox(height: 6),
              const Divider(height: 1),
              const SizedBox(height: 10),
              _StatRow(
                label: 'Контекст занят',
                value:
                    '${contextUsage!.estimated ? '≈ ' : ''}${formatNumber(contextUsage!.used)} / ${formatNumber(contextUsage!.limit)}',
              ),
              _StatRow(
                label: 'Осталось контекста',
                value: formatNumber(contextUsage!.remaining),
              ),
              _StatRow(label: 'Лимит из', value: contextUsage!.source),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    estimated ? Icons.info_outline : Icons.check_circle_outline,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      estimated
                          ? 'LM Studio не вернула точный usage — токены '
                                'посчитаны приблизительно по символам.'
                          : 'Токены возвращены LM Studio и совпадают с '
                                'использованием контекста.',
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
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.scheme,
  });

  final String label;
  final String value;
  final String unit;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          Text(
            unit,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
