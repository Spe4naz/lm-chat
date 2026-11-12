import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_log.dart';
import '../app_state.dart';
import '../l10n_text.dart';
import '../theme.dart';

/// Shows the in-memory app log and the current server/model state.
///
/// Useful when a user reports "the answer hangs" or "the bridge does not
/// load": the screen contains no prompts, API keys or bridge tokens.
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: AppLog.instance.asText()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Лог скопирован')));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final server = state.activeServer;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Диагностика'),
        actions: [
          IconButton(
            onPressed: () => _copy(context),
            icon: const Icon(Icons.copy_rounded),
            tooltip: L10n.t('Скопировать лог'),
          ),
          IconButton(
            onPressed: AppLog.instance.clear,
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: L10n.t('Очистить лог'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListenableBuilder(
            listenable: AppLog.instance,
            builder: (context, _) {
              final entries = AppLog.instance.entries.reversed.toList();
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _InfoRow(
                            label: 'Сервер',
                            value: server == null
                                ? 'не выбран'
                                : '${server.name} · ${server.normalizedBase}',
                          ),
                          if (server != null && server.hasBridge)
                            _InfoRow(
                              label: 'Мостик',
                              value: server.normalizedBridge,
                            ),
                          _InfoRow(
                            label: 'Моделей в кэше',
                            value: server == null
                                ? '0'
                                : '${state.modelsFor(server.id).length}',
                          ),
                          const _InfoRow(
                            label: 'Версия',
                            value: 'LM Chat 1.7.1',
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Лог хранится только в памяти и очищается при '
                            'закрытии приложения.',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 36,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Пока нет записей',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    )
                  else
                    ...entries.map((entry) => _LogTile(entry: entry)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (entry.level) {
      LogLevel.info => (Icons.info_outline_rounded, scheme.primary),
      LogLevel.warning => (
        Icons.warning_amber_rounded,
        AppColors.of(context).warning,
      ),
      LogLevel.error => (Icons.error_outline_rounded, scheme.error),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        entry.formattedTime,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.message,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (entry.detail != null && entry.detail!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: SelectableText(
                        entry.detail!,
                        style: TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 11.5,
                          height: 1.45,
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
