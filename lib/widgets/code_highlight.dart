import 'package:flutter/material.dart';

/// Kind of a highlighted token inside a fenced code block.
enum CodeTokenKind { plain, keyword, string, comment, number, type, function }

class CodeToken {
  const CodeToken(this.text, this.kind);

  final String text;
  final CodeTokenKind kind;
}

/// A small dependency-free highlighter for the languages that appear most
/// often in model answers. Unknown languages get a conservative C-like set of
/// rules, so strings, comments and numbers are still highlighted.
List<CodeToken> tokenizeCode(String code, {String language = ''}) {
  final rules = _LanguageRules.forName(language);
  final tokens = <CodeToken>[];
  final buffer = StringBuffer();

  void flushPlain() {
    if (buffer.isEmpty) return;
    tokens.add(CodeToken(buffer.toString(), CodeTokenKind.plain));
    buffer.clear();
  }

  void add(String text, CodeTokenKind kind) {
    if (text.isEmpty) return;
    flushPlain();
    tokens.add(CodeToken(text, kind));
  }

  var i = 0;
  while (i < code.length) {
    final commentEnd = rules.commentEnd(code, i);
    if (commentEnd != null) {
      add(code.substring(i, commentEnd), CodeTokenKind.comment);
      i = commentEnd;
      continue;
    }

    final char = code[i];
    if (char == "'" || char == '"' || (rules.backticks && char == '`')) {
      final end = _stringEnd(code, i, rules);
      add(code.substring(i, end), CodeTokenKind.string);
      i = end;
      continue;
    }

    final number = _numberPattern.matchAsPrefix(code, i);
    if (number != null) {
      add(number[0]!, CodeTokenKind.number);
      i += number[0]!.length;
      continue;
    }

    final identifier = _identifierPattern.matchAsPrefix(code, i);
    if (identifier != null) {
      final word = identifier[0]!;
      final kind = _classify(word, code, i);
      if (kind == CodeTokenKind.plain) {
        buffer.write(word);
      } else {
        add(word, kind);
      }
      i += word.length;
      continue;
    }

    buffer.write(char);
    i++;
  }
  flushPlain();
  return tokens;
}

final RegExp _numberPattern = RegExp(
  r'(?:0[xX][0-9a-fA-F]+|0[bB][01]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)',
);
final RegExp _identifierPattern = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');

CodeTokenKind _classify(String word, String code, int start) {
  if (_keywords.contains(word) || _keywords.contains(word.toLowerCase())) {
    return CodeTokenKind.keyword;
  }
  var next = start + word.length;
  while (next < code.length && _isSpace(code[next])) {
    next++;
  }
  if (next < code.length && code[next] == '(') {
    return CodeTokenKind.function;
  }
  final first = word[0];
  if (first == first.toUpperCase() &&
      first != first.toLowerCase() &&
      word != word.toUpperCase()) {
    return CodeTokenKind.type;
  }
  return CodeTokenKind.plain;
}

bool _isSpace(String char) =>
    char == ' ' || char == '\t' || char == '\n' || char == '\r';

int _stringEnd(String code, int start, _LanguageRules rules) {
  final quote = code[start];
  if (rules.tripleQuotes && code.startsWith('$quote$quote$quote', start)) {
    final close = '$quote$quote$quote';
    final end = code.indexOf(close, start + 3);
    return end == -1 ? code.length : end + close.length;
  }
  var i = start + 1;
  while (i < code.length) {
    final char = code[i];
    if (char == r'\' && i + 1 < code.length) {
      i += 2;
      continue;
    }
    if (char == quote) return i + 1;
    if (char == '\n' && quote != '`') {
      return i;
    }
    i++;
  }
  return code.length;
}

class _LanguageRules {
  const _LanguageRules({
    this.slashComments = true,
    this.hashComments = false,
    this.dashComments = false,
    this.blockComments = true,
    this.backticks = false,
    this.tripleQuotes = false,
  });

  final bool slashComments;
  final bool hashComments;
  final bool dashComments;
  final bool blockComments;
  final bool backticks;
  final bool tripleQuotes;

  int? commentEnd(String code, int start) {
    if (slashComments && code.startsWith('//', start)) {
      final end = code.indexOf('\n', start);
      return end == -1 ? code.length : end;
    }
    if (hashComments && code.startsWith('#', start)) {
      final end = code.indexOf('\n', start);
      return end == -1 ? code.length : end;
    }
    if (dashComments && code.startsWith('--', start)) {
      final end = code.indexOf('\n', start);
      return end == -1 ? code.length : end;
    }
    if (blockComments && code.startsWith('/*', start)) {
      final end = code.indexOf('*/', start + 2);
      return end == -1 ? code.length : end + 2;
    }
    return null;
  }

  static _LanguageRules forName(String raw) {
    final name = raw
        .toLowerCase()
        .trim()
        .split(RegExp(r'[\s,;]+'))
        .firstWhere((part) => part.isNotEmpty, orElse: () => '');

    return switch (name) {
      'py' || 'python' || 'python3' => const _LanguageRules(
        slashComments: false,
        blockComments: false,
        hashComments: true,
        tripleQuotes: true,
      ),
      'sh' ||
      'bash' ||
      'shell' ||
      'zsh' ||
      'powershell' ||
      'ps1' ||
      'yaml' ||
      'yml' ||
      'toml' ||
      'ini' ||
      'conf' ||
      'dockerfile' => const _LanguageRules(
        slashComments: false,
        blockComments: false,
        hashComments: true,
      ),
      'ruby' || 'rb' => const _LanguageRules(
        slashComments: false,
        blockComments: false,
        hashComments: true,
      ),
      'php' => const _LanguageRules(hashComments: true),
      'sql' => const _LanguageRules(slashComments: false, dashComments: true),
      'js' ||
      'javascript' ||
      'jsx' ||
      'ts' ||
      'typescript' ||
      'tsx' ||
      'node' => const _LanguageRules(backticks: true),
      'json' => const _LanguageRules(
        slashComments: false,
        blockComments: false,
      ),
      'html' ||
      'xml' ||
      'svg' => const _LanguageRules(slashComments: false, blockComments: false),
      'text' || 'txt' || 'plain' || 'plaintext' || 'md' || 'markdown' =>
        const _LanguageRules(slashComments: false, blockComments: false),
      _ => const _LanguageRules(backticks: true),
    };
  }
}

const Set<String> _keywords = {
  'abstract',
  'and',
  'as',
  'assert',
  'async',
  'auto',
  'await',
  'base',
  'bool',
  'break',
  'byte',
  'case',
  'catch',
  'char',
  'class',
  'const',
  'continue',
  'crate',
  'debugger',
  'default',
  'def',
  'defer',
  'del',
  'delete',
  'distinct',
  'do',
  'double',
  'dynamic',
  'elif',
  'else',
  'end',
  'enum',
  'except',
  'exists',
  'explicit',
  'export',
  'extends',
  'extension',
  'extern',
  'false',
  'final',
  'finally',
  'float',
  'fn',
  'for',
  'from',
  'func',
  'function',
  'get',
  'global',
  'go',
  'group',
  'having',
  'if',
  'impl',
  'implements',
  'import',
  'in',
  'inner',
  'insert',
  'instanceof',
  'int',
  'interface',
  'internal',
  'into',
  'is',
  'join',
  'lambda',
  'late',
  'left',
  'let',
  'like',
  'limit',
  'long',
  'loop',
  'map',
  'match',
  'max',
  'min',
  'mod',
  'mut',
  'namespace',
  'new',
  'nil',
  'nonlocal',
  'not',
  'null',
  'of',
  'offset',
  'on',
  'operator',
  'or',
  'order',
  'outer',
  'override',
  'package',
  'pass',
  'private',
  'protected',
  'pub',
  'public',
  'raise',
  'readonly',
  'ref',
  'require',
  'required',
  'return',
  'right',
  'sealed',
  'select',
  'self',
  'set',
  'short',
  'signed',
  'sizeof',
  'static',
  'struct',
  'sum',
  'super',
  'switch',
  'table',
  'template',
  'then',
  'this',
  'throw',
  'true',
  'try',
  'type',
  'typedef',
  'typename',
  'union',
  'unsigned',
  'update',
  'use',
  'using',
  'values',
  'var',
  'virtual',
  'void',
  'when',
  'where',
  'while',
  'with',
  'yield',
  'avg',
  'count',
  'all',
  'between',
  'alter',
  'create',
  'drop',
};

class CodePalette {
  const CodePalette({
    required this.plain,
    required this.keyword,
    required this.string,
    required this.comment,
    required this.number,
    required this.type,
    required this.function,
  });

  final Color plain;
  final Color keyword;
  final Color string;
  final Color comment;
  final Color number;
  final Color type;
  final Color function;

  factory CodePalette.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CodePalette(
      plain: scheme.onSurface,
      keyword: dark ? const Color(0xFFC792EA) : const Color(0xFF7B3FA0),
      string: dark ? const Color(0xFFA5D6A7) : const Color(0xFF2E7D32),
      comment: scheme.onSurfaceVariant.withValues(alpha: 0.78),
      number: dark ? const Color(0xFFF2A65A) : const Color(0xFFA65300),
      type: dark ? const Color(0xFF82AAFF) : const Color(0xFF1B5FBF),
      function: dark ? const Color(0xFF61C8D8) : const Color(0xFF006A75),
    );
  }

  TextStyle styleFor(CodeTokenKind kind, TextStyle base) {
    final color = switch (kind) {
      CodeTokenKind.plain => plain,
      CodeTokenKind.keyword => keyword,
      CodeTokenKind.string => string,
      CodeTokenKind.comment => comment,
      CodeTokenKind.number => number,
      CodeTokenKind.type => type,
      CodeTokenKind.function => function,
    };
    return base.copyWith(
      color: color,
      fontStyle: kind == CodeTokenKind.comment ? FontStyle.italic : null,
      fontWeight: kind == CodeTokenKind.keyword
          ? FontWeight.w600
          : FontWeight.w400,
    );
  }
}

/// Converts highlighted tokens into spans for [SelectableText.rich].
List<TextSpan> buildCodeSpans(
  String code, {
  required String language,
  required TextStyle baseStyle,
  required BuildContext context,
}) {
  final palette = CodePalette.of(context);
  return [
    for (final token in tokenizeCode(code, language: language))
      TextSpan(
        text: token.text,
        style: palette.styleFor(token.kind, baseStyle),
      ),
  ];
}
