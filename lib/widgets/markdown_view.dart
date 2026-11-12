import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../l10n_text.dart';
import '../theme.dart';
import 'code_highlight.dart';

class MarkdownView extends StatelessWidget {
  const MarkdownView(this.data, {super.key});

  final String data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyMedium ?? const TextStyle();

    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: body.copyWith(fontSize: 15, height: 1.5, color: scheme.onSurface),
        h1: body.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        h2: body.copyWith(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        h3: body.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        code: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 13,
          color: scheme.onSurface,
          backgroundColor: scheme.surfaceContainerHighest,
        ),
        codeblockPadding: EdgeInsets.zero,
        codeblockDecoration: const BoxDecoration(),
        blockquoteDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          border: Border(left: BorderSide(color: scheme.primary, width: 3)),
          borderRadius: BorderRadius.circular(8),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        listBullet: body.copyWith(fontSize: 15, color: scheme.onSurface),
        tableBorder: TableBorder.all(
          color: scheme.outlineVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
        blockSpacing: 10,
      ),
      builders: {'pre': _CodeBlockBuilder()},
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    var language = '';
    for (final child in element.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'code') {
        final className = child.attributes['class'] ?? '';
        if (className.startsWith('language-')) {
          language = className.substring('language-'.length);
        }
        break;
      }
    }
    return _CodeBlock(code: element.textContent, language: language);
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code, required this.language});

  final String code;
  final String language;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = scheme.outlineVariant.withValues(alpha: 0.45);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.of(context).code,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Row(
              children: [
                Text(
                  language.isEmpty ? 'code' : language,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(content: Text('Код скопирован')),
                      );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                  tooltip: L10n.t('Копировать код'),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText.rich(
              TextSpan(
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 13,
                  height: 1.5,
                ),
                children: buildCodeSpans(
                  code,
                  language: language,
                  baseStyle: const TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 13,
                    height: 1.5,
                  ),
                  context: context,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
