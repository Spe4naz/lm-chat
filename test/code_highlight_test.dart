import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/widgets/code_highlight.dart';

String _joined(List<CodeToken> tokens) =>
    tokens.map((token) => token.text).join();

CodeToken _token(List<CodeToken> tokens, String text) =>
    tokens.firstWhere((token) => token.text == text);

void main() {
  test(
    'Dart code keeps its text and highlights keywords, strings and numbers',
    () {
      const code = '''
// greet the user
final name = 'Ada';
int answer = 42;
print(name);
''';

      final tokens = tokenizeCode(code, language: 'dart');

      expect(_joined(tokens), code);
      expect(_token(tokens, 'final').kind, CodeTokenKind.keyword);
      expect(_token(tokens, 'int').kind, CodeTokenKind.keyword);
      expect(_token(tokens, "'Ada'").kind, CodeTokenKind.string);
      expect(_token(tokens, '42').kind, CodeTokenKind.number);
      expect(_token(tokens, '// greet the user').kind, CodeTokenKind.comment);
      expect(_token(tokens, 'print').kind, CodeTokenKind.function);
    },
  );

  test('Python hash comments and triple quotes are recognized', () {
    const code = '''
# explain
def greet(name):
    return """hello""" + name
''';

    final tokens = tokenizeCode(code, language: 'python');

    expect(_joined(tokens), code);
    expect(_token(tokens, '# explain').kind, CodeTokenKind.comment);
    expect(_token(tokens, 'def').kind, CodeTokenKind.keyword);
    expect(_token(tokens, 'return').kind, CodeTokenKind.keyword);
    expect(_token(tokens, '"""hello"""').kind, CodeTokenKind.string);
  });

  test('SQL dash comments and keywords are recognized', () {
    const code = 'SELECT id FROM users -- all users\nWHERE id = 7;';

    final tokens = tokenizeCode(code, language: 'sql');

    expect(_joined(tokens), code);
    expect(_token(tokens, 'SELECT').kind, CodeTokenKind.keyword);
    expect(_token(tokens, 'FROM').kind, CodeTokenKind.keyword);
    expect(_token(tokens, '-- all users').kind, CodeTokenKind.comment);
    expect(_token(tokens, '7').kind, CodeTokenKind.number);
  });

  test('JavaScript template strings may span lines', () {
    const code = 'const text = `one\ntwo`;\n// done';

    final tokens = tokenizeCode(code, language: 'javascript');

    expect(_joined(tokens), code);
    expect(_token(tokens, '`one\ntwo`').kind, CodeTokenKind.string);
    expect(_token(tokens, '// done').kind, CodeTokenKind.comment);
  });

  test('code without a language still highlights strings and numbers', () {
    const code = "answer = 'yes';\nvalue = 12;";

    final tokens = tokenizeCode(code);

    expect(_joined(tokens), code);
    expect(_token(tokens, "'yes'").kind, CodeTokenKind.string);
    expect(_token(tokens, '12').kind, CodeTokenKind.number);
  });

  test('unterminated strings do not drop the rest of the text', () {
    const code = "broken = 'value";

    final tokens = tokenizeCode(code, language: 'python');

    expect(_joined(tokens), code);
    expect(_token(tokens, "'value").kind, CodeTokenKind.string);
  });
}
