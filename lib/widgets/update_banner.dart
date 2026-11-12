import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../updater.dart';
import 'markdown_view.dart';

UpdateService? readUpdateService(BuildContext context) {
  try {
    return context.read<UpdateService>();
  } on ProviderNotFoundException {
    return null;
  }
}

UpdateService? _watchUpdateService(BuildContext context) {
  try {
    return context.watch<UpdateService>();
  } on ProviderNotFoundException {
    return null;
  }
}

class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final service = _watchUpdateService(context);
    if (service == null) return const SizedBox.shrink();
    final state = context.watch<AppState>();
    final info = service.available;
    if (info == null || !service.canInstallHere) return const SizedBox.shrink();
    if (state.data.skippedUpdateTag == info.tag) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.system_update_alt_rounded,
            color: scheme.onPrimaryContainer,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              L10n.tf('Доступно обновление {version}', {
                'version': info.version.toString(),
              }),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: scheme.onPrimaryContainer,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => showUpdateSheet(context, info),
            child: Text(L10n.t('Обновить приложение')),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () {
              state.skipUpdate(info.tag);
              service.dismiss();
            },
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: scheme.onPrimaryContainer,
            ),
            tooltip: L10n.t('Позже'),
          ),
        ],
      ),
    );
  }
}

class UpdateSettingsTile extends StatelessWidget {
  const UpdateSettingsTile({super.key});

  Future<void> _check(BuildContext context) async {
    final service = context.read<UpdateService>();
    await service.check();
    if (!context.mounted) return;
    final info = service.available;
    if (info != null) {
      await showUpdateSheet(context, info);
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(service.error ?? L10n.t('Обновлений нет'))),
      );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final service = _watchUpdateService(context);
    if (service == null) {
      return Card(
        child: SwitchListTile(
          secondary: const Icon(Icons.update_rounded),
          title: Text(L10n.t('Проверять обновления')),
          subtitle: Text(
            L10n.t('Автоматически раз в несколько часов через GitHub Releases'),
          ),
          value: state.data.autoCheckUpdates,
          onChanged: state.setAutoCheckUpdates,
        ),
      );
    }
    final info = service.available;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.update_rounded),
            title: Text(L10n.t('Проверять обновления')),
            subtitle: Text(
              L10n.t(
                'Автоматически раз в несколько часов через GitHub Releases',
              ),
            ),
            value: state.data.autoCheckUpdates,
            onChanged: state.setAutoCheckUpdates,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: Text(L10n.t('Проверить обновления')),
            subtitle: Text(
              service.checking
                  ? L10n.t('Проверка обновлений…')
                  : info != null
                  ? L10n.tf('Доступна версия {version}', {
                      'version': info.version.toString(),
                    })
                  : L10n.t('Проверить наличие новой версии'),
            ),
            trailing: service.checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right_rounded),
            onTap: service.checking ? null : () => _check(context),
          ),
        ],
      ),
    );
  }
}

Future<void> showUpdateSheet(BuildContext context, UpdateInfo info) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _UpdateSheet(info: info),
  );
}

class _UpdateSheet extends StatelessWidget {
  const _UpdateSheet({required this.info});

  final UpdateInfo info;

  @override
  Widget build(BuildContext context) {
    final service = context.watch<UpdateService>();
    final state = context.read<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final current = FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data == null
            ? ''
            : '${snapshot.data!.version}+${snapshot.data!.buildNumber}';
        return Text(
          version.isEmpty
              ? L10n.tf('Новая версия: {version}', {
                  'version': info.version.toString(),
                })
              : '${L10n.tf('Текущая версия: {version}', {'version': version})}'
                    '  →  ${info.version}',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        );
      },
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L10n.t('Обновление LM Chat'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          current,
          if (info.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              L10n.t('Заметки к релизу'),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 240),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(child: MarkdownView(info.notes)),
            ),
          ],
          if (service.installing) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: service.progress <= 0 ? null : service.progress,
            ),
            const SizedBox(height: 6),
            Text(
              service.progress > 0 && service.progress < 1
                  ? L10n.tf('Скачивание: {percent}%', {
                      'percent': (service.progress * 100).round().toString(),
                    })
                  : L10n.t('Установка…'),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
          if (service.status != null) ...[
            const SizedBox(height: 12),
            Text(
              service.status!,
              style: TextStyle(fontSize: 12.5, color: scheme.primary),
            ),
          ],
          if (service.error != null) ...[
            const SizedBox(height: 12),
            Text(
              service.error!,
              style: TextStyle(fontSize: 12.5, color: scheme.error),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              OutlinedButton(
                onPressed: service.installing
                    ? null
                    : () {
                        state.skipUpdate(info.tag);
                        service.dismiss();
                        Navigator.pop(context);
                      },
                child: Text(L10n.t('Позже')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: service.installing
                      ? null
                      : () async {
                          try {
                            await service.install();
                          } catch (_) {
                            // The service exposes a readable error below.
                          }
                        },
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(
                    service.installing
                        ? L10n.t('Установка…')
                        : L10n.t('Скачать и установить'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            L10n.t(
              'Файл скачивается с GitHub и проверяется по SHA-256 перед установкой.',
            ),
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
