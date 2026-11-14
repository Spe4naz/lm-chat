import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../format_utils.dart';
import '../l10n_text.dart';
import '../models.dart';
import '../theme.dart';
import 'markdown_view.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.onDelete,
    this.onSelectVersion,
    this.onShowVersions,
    this.onShowStats,
    this.onEdit,
    this.onResume,
    this.onContinue,
    this.showRetry = false,
    this.showContinue = false,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelection,
    this.onStartSelection,
  });

  final ChatMessage message;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;

  /// Called with the 1-based number of the version to show.
  final ValueChanged<int>? onSelectVersion;

  /// Opens the full list of saved versions.
  final VoidCallback? onShowVersions;

  /// Opens the token/speed/time card for this answer.
  final VoidCallback? onShowStats;

  /// Opens the editor for the answer that is currently shown.
  final VoidCallback? onEdit;

  /// Re-attaches to a bridge job that is still generating this answer.
  final VoidCallback? onResume;

  /// Appends more text to a finished answer.
  final VoidCallback? onContinue;

  final bool showRetry;
  final bool showContinue;

  /// Multi-select mode for exporting only part of the conversation.
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggleSelection;

  /// Starts multi-select mode from a long press on this message.
  final VoidCallback? onStartSelection;

  @override
  Widget build(BuildContext context) {
    final content = message.isUser
        ? _buildUser(context)
        : _buildAssistant(context);
    if (!selectionMode && onStartSelection == null) return content;

    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectionMode)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Checkbox(
              value: selected,
              onChanged: onToggleSelection == null
                  ? null
                  : (_) => onToggleSelection!(),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              semanticLabel: L10n.t('Выбрать сообщение'),
            ),
          ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: selectionMode ? null : onStartSelection,
            onTap: selectionMode ? onToggleSelection : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              decoration: BoxDecoration(
                color: selectionMode && selected
                    ? scheme.primary.withValues(alpha: 0.07)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: IgnorePointer(ignoring: selectionMode, child: content),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUser(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = AppDensity.isCompact(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: EdgeInsets.only(top: compact ? 6 : 10, bottom: 2, left: 48),
            padding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: compact ? 8 : 11,
            ),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(6),
              ),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (message.attachments.isNotEmpty)
                  _UserAttachments(attachments: message.attachments),
                if (message.content.trim().isNotEmpty)
                  SelectableText(
                    message.content,
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Wrap(
            spacing: 2,
            children: [
              _BubbleAction(
                icon: Icons.copy_rounded,
                tooltip: L10n.t('Копировать'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: message.content));
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(content: Text('Скопировано')),
                    );
                },
              ),
              _UserMessageMenu(
                hasContent: message.content.trim().isNotEmpty,
                onEdit: onEdit,
                onDelete: onDelete,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAssistant(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = AppDensity.isCompact(context);
    final hasContent = message.displayContent.trim().isNotEmpty;
    final showStats = !message.streaming && message.hasStats;

    return Padding(
      padding: EdgeInsets.only(
        top: compact ? 8 : 12,
        bottom: compact ? 2 : 4,
        right: 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AssistantHeader(message: message),
          if (message.displayToolCalls.isNotEmpty)
            _ToolCallsPanel(
              calls: message.displayToolCalls,
              live: message.streaming,
            ),
          if (message.displayReasoning.trim().isNotEmpty)
            _ReasoningPanel(text: message.displayReasoning),
          if (hasContent)
            message.streaming
                ? SelectableText(
                    '${message.displayContent} ▍',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: scheme.onSurface,
                    ),
                  )
                : MarkdownView(message.displayContent)
          else if (message.streaming)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: message.status == null
                  ? const _TypingDots()
                  : _StatusLine(text: message.status!),
            ),
          if (message.streaming) _LiveStats(message: message),
          if (message.hasVersions && !message.streaming)
            _VersionBar(
              message: message,
              onSelect: onSelectVersion,
              onShow: onShowVersions,
            ),
          if (message.displayError != null)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 18, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      message.displayError!,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (message.displayNotice != null)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.tertiary.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: scheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      message.displayNotice!,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!message.streaming &&
              (hasContent ||
                  message.displayError != null ||
                  message.displayNotice != null ||
                  message.hasPendingJob))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 2,
                children: [
                  if (message.displayEditedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 4, left: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.edit_note_rounded,
                            size: 15,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            'изменено',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (showStats && onShowStats != null)
                    TextButton.icon(
                      onPressed: onShowStats,
                      icon: const Icon(Icons.speed_rounded, size: 15),
                      label: Text(_statsLabel(message)),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  if (hasContent)
                    _BubbleAction(
                      icon: Icons.copy_rounded,
                      tooltip: L10n.t('Копировать'),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: message.displayContent),
                        );
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            const SnackBar(content: Text('Скопировано')),
                          );
                      },
                    ),
                  _MessageMenu(
                    message: message,
                    hasContent: hasContent,
                    showRetry: showRetry,
                    showContinue: showContinue,
                    onRetry: onRetry,
                    onResume: onResume,
                    onContinue: onContinue,
                    onEdit: onEdit,
                    onDelete: onDelete,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AssistantHeader extends StatelessWidget {
  const _AssistantHeader({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final model = message.displayModel;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 13,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              model.isEmpty ? 'LM Studio' : model,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatClock(message.displayCreatedAt),
            style: TextStyle(
              fontSize: 10.5,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserMessageMenu extends StatelessWidget {
  const _UserMessageMenu({
    required this.hasContent,
    this.onEdit,
    this.onDelete,
  });

  final bool hasContent;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = <PopupMenuEntry<String>>[];
    if (hasContent && onEdit != null) {
      items.add(
        const PopupMenuItem(
          value: 'edit',
          child: _MenuRow(icon: Icons.edit_outlined, label: 'Редактировать'),
        ),
      );
    }
    if (onDelete != null) {
      items.add(
        PopupMenuItem(
          value: 'delete',
          child: _MenuRow(
            icon: Icons.delete_outline_rounded,
            label: 'Удалить',
            color: scheme.error,
          ),
        ),
      );
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: L10n.t('Действия'),
      icon: const Icon(Icons.more_horiz_rounded, size: 19),
      onSelected: (value) {
        if (value == 'edit') onEdit?.call();
        if (value == 'delete') onDelete?.call();
      },
      itemBuilder: (_) => items,
    );
  }
}

class _MessageMenu extends StatelessWidget {
  const _MessageMenu({
    required this.message,
    required this.hasContent,
    required this.showRetry,
    required this.showContinue,
    this.onRetry,
    this.onResume,
    this.onContinue,
    this.onEdit,
    this.onDelete,
  });

  final ChatMessage message;
  final bool hasContent;
  final bool showRetry;
  final bool showContinue;
  final VoidCallback? onRetry;
  final VoidCallback? onResume;
  final VoidCallback? onContinue;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = <PopupMenuEntry<String>>[];
    void add(String value, IconData icon, String label, [Color? color]) {
      items.add(
        PopupMenuItem(
          value: value,
          child: _MenuRow(icon: icon, label: label, color: color),
        ),
      );
    }

    if (message.hasPendingJob && onResume != null) {
      add('resume', Icons.download_rounded, 'Догрузить ответ');
    }
    if (showContinue &&
        message.viewingLatest &&
        hasContent &&
        onContinue != null) {
      add('continue', Icons.play_arrow_rounded, 'Продолжить ответ');
    }
    if (showRetry && message.viewingLatest && onRetry != null) {
      add('retry', Icons.refresh_rounded, 'Сгенерировать заново');
    }
    if (hasContent && onEdit != null) {
      add('edit', Icons.edit_outlined, 'Редактировать ответ');
    }
    if (items.isNotEmpty && onDelete != null) {
      items.add(const PopupMenuDivider());
    }
    if (onDelete != null) {
      add(
        'delete',
        Icons.delete_outline_rounded,
        'Удалить сообщение',
        scheme.error,
      );
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      tooltip: L10n.t('Действия'),
      icon: const Icon(Icons.more_horiz_rounded, size: 19),
      onSelected: (value) {
        switch (value) {
          case 'resume':
            onResume?.call();
          case 'continue':
            onContinue?.call();
          case 'retry':
            onRetry?.call();
          case 'edit':
            onEdit?.call();
          case 'delete':
            onDelete?.call();
        }
      },
      itemBuilder: (_) => items,
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = color ?? scheme.onSurface;
    return Row(
      children: [
        Icon(icon, size: 18, color: tint),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: tint),
          ),
        ),
      ],
    );
  }
}

String _formatClock(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

String _statsLabel(ChatMessage message) {
  final speed = message.displayTokensPerSecond;
  final time = formatGenerationTime(message.displayGenerationMs);
  final prefix = message.displayTokensEstimated ? '≈ ' : '';
  if (speed != null && time.isNotEmpty) {
    return '$prefix${speed.toStringAsFixed(1)} tok/s · $time';
  }
  if (time.isNotEmpty) return time;
  final tokens = message.displayCompletionTokens;
  if (tokens != null && tokens > 0) {
    return L10n.tf('{tokens} ток.', {
      'tokens': '$prefix${formatNumber(tokens)}',
    });
  }
  return L10n.t('Статистика');
}

class _VersionBar extends StatelessWidget {
  const _VersionBar({required this.message, this.onSelect, this.onShow});

  final ChatMessage message;
  final ValueChanged<int>? onSelect;
  final VoidCallback? onShow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = message.displayedVersionNumber;
    final count = message.versionCount;
    final isOld = !message.viewingLatest;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.only(left: 10, right: 2, top: 2, bottom: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isOld
              ? scheme.primary.withValues(alpha: 0.45)
              : scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history_rounded,
            size: 15,
            color: isOld ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            isOld
                ? L10n.tf('Вариант {current} из {count} — старый', {
                    'current': current,
                    'count': count,
                  })
                : L10n.tf('Вариант {current} из {count}', {
                    'current': current,
                    'count': count,
                  }),
            style: TextStyle(
              fontSize: 12,
              fontWeight: isOld ? FontWeight.w600 : FontWeight.w500,
              color: isOld ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
          _VersionAction(
            icon: Icons.chevron_left_rounded,
            tooltip: L10n.t('Предыдущий вариант'),
            onPressed: current > 1 && onSelect != null
                ? () => onSelect!(current - 1)
                : null,
          ),
          _VersionAction(
            icon: Icons.chevron_right_rounded,
            tooltip: L10n.t('Следующий вариант'),
            onPressed: current < count && onSelect != null
                ? () => onSelect!(current + 1)
                : null,
          ),
          _VersionAction(
            icon: Icons.list_rounded,
            tooltip: L10n.t('Все варианты'),
            onPressed: onShow,
          ),
        ],
      ),
    );
  }
}

class _VersionAction extends StatelessWidget {
  const _VersionAction({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      disabledColor: Theme.of(context).colorScheme.onSurfaceVariant
          .withValues(alpha: 0.3),
    );
  }
}

class _BubbleAction extends StatelessWidget {
  const _BubbleAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}

class _UserAttachments extends StatelessWidget {
  const _UserAttachments({required this.attachments});

  final List<ChatAttachment> attachments;

  void _open(BuildContext context, ChatAttachment attachment) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Center(
                child: Image.memory(
                  attachment.bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                tooltip: L10n.t('Закрыть'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: WrapAlignment.end,
      children: [
        for (final attachment in attachments)
          Semantics(
            label: L10n.t('Открыть изображение'),
            button: true,
            child: GestureDetector(
              onTap: () => _open(context, attachment),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  attachment.bytes,
                  width: 150,
                  height: 150,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 150,
                    height: 150,
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LiveStats extends StatelessWidget {
  const _LiveStats({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final started = message.generationStartedAt;
    if (started == null) return const SizedBox.shrink();

    final elapsedMs = DateTime.now().difference(started).inMilliseconds;
    final tokens =
        estimateTokens(message.content) + estimateTokens(message.reasoning);
    final speed = elapsedMs > 0 ? tokens * 1000 / elapsedMs : 0.0;
    final waiting =
        message.firstTokenMs == null &&
        message.content.isEmpty &&
        message.reasoning.isEmpty;
    final text = waiting
        ? L10n.tf('Ждём первый токен · {time}', {
            'time': formatGenerationTime(elapsedMs),
          })
        : L10n.tf('{tokens} ток. · {speed} tok/s · {time}', {
            'tokens': tokens,
            'speed': speed.toStringAsFixed(1),
            'time': formatGenerationTime(elapsedMs),
          });

    return Semantics(
      container: true,
      liveRegion: true,
      label: text,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolCallsPanel extends StatelessWidget {
  const _ToolCallsPanel({required this.calls, required this.live});

  final List<ToolCallRecord> calls;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final running = calls.any((call) => call.isRunning);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.of(context).reasoning,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
            child: Row(
              children: [
                Icon(
                  Icons.extension_rounded,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  L10n.tf('Инструменты: {count}', {'count': '${calls.length}'}),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (live && running) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (final call in calls)
            _ToolCallTile(key: ObjectKey(call), call: call),
          const SizedBox(height: 3),
        ],
      ),
    );
  }
}

class _ToolCallTile extends StatefulWidget {
  const _ToolCallTile({super.key, required this.call});

  final ToolCallRecord call;

  @override
  State<_ToolCallTile> createState() => _ToolCallTileState();
}

class _ToolCallTileState extends State<_ToolCallTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final call = widget.call;
    final statusColor = call.isFailure
        ? scheme.error
        : call.isRunning
        ? scheme.primary
        : AppColors.of(context).success;
    final title = call.name.isEmpty
        ? L10n.t('Инструмент')
        : L10n.t(toolDisplayName(call.name));
    final hint = call.isFailure && call.error.isNotEmpty
        ? call.error
        : call.summary;
    final duration = call.durationMs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            child: Row(
              children: [
                _ToolStatusIcon(call: call, color: statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      if (hint.isNotEmpty)
                        Text(
                          hint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.3,
                            color: call.isFailure
                                ? scheme.error
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (duration != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      _toolDurationLabel(duration),
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                Icon(
                  _open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (call.name.isNotEmpty &&
                    toolDisplayName(call.name) != call.name)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 2),
                    child: Text(
                      L10n.tf('Инструмент: {name}', {'name': call.name}),
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (call.arguments.trim().isNotEmpty)
                  _ToolDetail(label: L10n.t('Аргументы'), text: call.arguments),
                if (call.isFailure && call.error.isNotEmpty)
                  _ToolDetail(
                    label: L10n.t('Ошибка'),
                    text: call.error,
                    color: scheme.error,
                  ),
                if (!call.isFailure && call.readableOutput.isNotEmpty)
                  _ToolDetail(
                    label: L10n.t('Результат'),
                    text: call.readableOutput,
                  ),
                if (call.isRunning)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      L10n.t('Инструмент выполняется…'),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ToolStatusIcon extends StatelessWidget {
  const _ToolStatusIcon({required this.call, required this.color});

  final ToolCallRecord call;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (call.isRunning) {
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 1.8, color: color),
      );
    }
    return Icon(
      call.isFailure ? Icons.error_outline_rounded : Icons.check_circle_rounded,
      size: 16,
      color: color,
    );
  }
}

class _ToolDetail extends StatelessWidget {
  const _ToolDetail({required this.label, required this.text, this.color});

  final String label;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = text.length > 4000 ? '${text.substring(0, 4000)}\n…' : text;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.of(context).code,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              letterSpacing: 0.3,
              fontWeight: FontWeight.w600,
              color: color ?? scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(
            shown,
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 12,
              height: 1.45,
              color: color ?? scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

String _toolDurationLabel(int millis) {
  if (millis < 1000) return '$millis мс';
  final seconds = millis / 1000;
  if (seconds < 60) return '${seconds.toStringAsFixed(1)} с';
  final minutes = (seconds / 60).floor();
  final rest = (seconds % 60).round();
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}

class _ReasoningPanel extends StatefulWidget {
  const _ReasoningPanel({required this.text});

  final String text;

  @override
  State<_ReasoningPanel> createState() => _ReasoningPanelState();
}

class _ReasoningPanelState extends State<_ReasoningPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.of(context).reasoning,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Размышления',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: SelectableText(
                widget.text,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 13,
          height: 13,
          child: CircularProgressIndicator(strokeWidth: 2, color: color),
        ),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(fontSize: 13, color: color)),
      ],
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final phase = (_controller.value + index / 3) % 1.0;
            final strength = 1 - (phase * 2 - 1).abs();
            return Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.25 + 0.65 * strength),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
