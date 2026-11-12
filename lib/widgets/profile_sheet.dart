import 'package:flutter/material.dart' hide Text;

import '../l10n_text.dart';
import '../profile.dart';
import '../theme.dart';

/// Asks which sections of a profile should be applied.
///
/// Returns null when the user cancels.
Future<ProfileImportOptions?> showProfileImportSheet(
  BuildContext context,
  ProfilePreview preview,
) {
  return showModalBottomSheet<ProfileImportOptions>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ProfileImportSheet(preview: preview),
  );
}

class _ProfileImportSheet extends StatefulWidget {
  const _ProfileImportSheet({required this.preview});

  final ProfilePreview preview;

  @override
  State<_ProfileImportSheet> createState() => _ProfileImportSheetState();
}

class _ProfileImportSheetState extends State<_ProfileImportSheet> {
  bool _servers = true;
  bool _generation = true;
  bool _appearance = true;
  bool _prompts = true;

  bool get _any =>
      (_servers && widget.preview.serverCount > 0) ||
      _generation ||
      _appearance ||
      (_prompts && widget.preview.promptCount > 0);

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final scheme = Theme.of(context).colorScheme;
    final hasServers = preview.serverCount > 0;
    final hasPrompts = preview.promptCount > 0;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Профиль с другого устройства',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              L10n.tf('Серверов: {servers} · промптов: {prompts}', {
                'servers': preview.serverCount,
                'prompts': preview.promptCount,
              }),
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            if (preview.sourceName != null && preview.sourceName!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  preview.sourceName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Что перенести',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            if (hasServers)
              _SectionCheck(
                value: _servers,
                onChanged: (value) => setState(() => _servers = value),
                icon: Icons.dns_outlined,
                title: 'Серверы и адреса',
                subtitle: L10n.tf('{count} сервер(ов)', {
                  'count': preview.serverCount,
                }),
              ),
            _SectionCheck(
              value: _generation,
              onChanged: (value) => setState(() => _generation = value),
              icon: Icons.tune_rounded,
              title: 'Параметры генерации',
              subtitle: L10n.t(
                'Temperature, top-p, top-k, repeat penalty и системный промпт',
              ),
            ),
            _SectionCheck(
              value: _appearance,
              onChanged: (value) => setState(() => _appearance = value),
              icon: Icons.palette_outlined,
              title: 'Оформление и язык',
              subtitle: L10n.t('Тема, шрифт, плотность и размер текста'),
            ),
            if (hasPrompts)
              _SectionCheck(
                value: _prompts,
                onChanged: (value) => setState(() => _prompts = value),
                icon: Icons.bookmarks_outlined,
                title: 'Пользовательские промпты',
                subtitle: L10n.tf('{count} промпт(ов)', {
                  'count': preview.promptCount,
                }),
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 18,
                    color: AppColors.of(context).success,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Токены доступа не входят в профиль. После импорта '
                      'введите их заново на этом устройстве.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _any
                  ? () => Navigator.of(context).pop(
                      ProfileImportOptions(
                        servers: _servers && hasServers,
                        generation: _generation,
                        appearance: _appearance,
                        prompts: _prompts && hasPrompts,
                      ),
                    )
                  : null,
              child: Text(
                _any ? L10n.t('Импортировать') : L10n.t('Выберите раздел'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCheck extends StatelessWidget {
  const _SectionCheck({
    required this.value,
    required this.onChanged,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CheckboxListTile(
      value: value,
      onChanged: (selected) => onChanged(selected ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
