import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/app_state.dart';
import 'package:lm_chat/models.dart';
import 'package:lm_chat/voice_input.dart';
import 'package:lm_chat/widgets/params_sheet.dart';
import 'package:provider/provider.dart';

void main() {
  group('ResponseFormat', () {
    test('plain text adds nothing to the request', () {
      expect(const ResponseFormat().requestFields(), isNull);
      expect(const ResponseFormat().isStructured, isFalse);
      expect(const ResponseFormat().validationError, isNull);
    });

    test('JSON mode asks for a permissive object schema', () {
      final fields = const ResponseFormat(mode: ResponseFormatMode.json)
          .requestFields()!;
      final format = fields['response_format'] as Map<String, dynamic>;
      expect(format['type'], 'json_schema');
      final schema = format['json_schema'] as Map<String, dynamic>;
      expect(schema['schema'], {'type': 'object'});
      expect(schema['strict'], false);
    });

    test('schema mode sends the parsed schema', () {
      const source =
          '{"type":"object","properties":{"answer":{"type":"string"}},'
          '"required":["answer"]}';
      final fields = const ResponseFormat(
        mode: ResponseFormatMode.jsonSchema,
        schema: source,
      ).requestFields()!;
      final format = fields['response_format'] as Map<String, dynamic>;
      final schema = format['json_schema'] as Map<String, dynamic>;
      expect(schema['name'], 'response');
      expect(schema['strict'], true);
      expect((schema['schema'] as Map<String, dynamic>)['required'], [
        'answer',
      ]);
    });

    test('empty or broken schema is rejected before sending', () {
      const empty = ResponseFormat(mode: ResponseFormatMode.jsonSchema);
      expect(empty.validationError, 'Введите JSON-схему ответа');
      expect(empty.requestFields(), isNull);

      const broken = ResponseFormat(
        mode: ResponseFormatMode.jsonSchema,
        schema: '{not json',
      );
      expect(broken.validationError, 'Схема ответа — некорректный JSON');
      expect(broken.requestFields(), isNull);
    });

    test('grammar mode sends the raw GBNF field', () {
      const format = ResponseFormat(
        mode: ResponseFormatMode.grammar,
        grammar: 'root ::= "да" | "нет"',
      );
      expect(format.requestFields(), {'grammar': 'root ::= "да" | "нет"'});
      expect(format.validationError, isNull);

      const empty = ResponseFormat(mode: ResponseFormatMode.grammar);
      expect(empty.validationError, 'Введите GBNF-грамматику');
      expect(empty.requestFields(), isNull);
    });

    test('format and schema survive json round trip', () {
      const format = ResponseFormat(
        mode: ResponseFormatMode.jsonSchema,
        schema: '{"type":"object"}',
        grammar: 'root ::= "x"',
      );
      final restored = ResponseFormat.fromJson(format.toJson());
      expect(restored, format);
    });

    test('chat and app defaults keep the response format', () {
      final chat = ChatSession(
        id: 'chat',
        serverId: 'server',
        model: 'model',
        responseFormat: const ResponseFormat(
          mode: ResponseFormatMode.grammar,
          grammar: 'root ::= "ok"',
        ),
        topK: 64,
        repeatPenalty: 1.1,
      );
      final restoredChat = ChatSession.fromJson(chat.toJson());
      expect(restoredChat.responseFormat.mode, ResponseFormatMode.grammar);
      expect(restoredChat.responseFormat.grammar, 'root ::= "ok"');
      expect(restoredChat.topK, 64);
      expect(restoredChat.repeatPenalty, 1.1);

      final data = AppData(
        defaultResponseFormat: const ResponseFormat(
          mode: ResponseFormatMode.json,
        ),
        defaultTopK: 64,
        defaultRepeatPenalty: 1.1,
      );
      final restoredData = AppData.fromJson(data.toJson());
      expect(restoredData.defaultResponseFormat.mode, ResponseFormatMode.json);
      expect(restoredData.defaultTopK, 64);
      expect(restoredData.defaultRepeatPenalty, 1.1);
      expect(AppData.currentSchemaVersion, 15);
    });
  });

  group('applyDictation', () {
    test('inserts words at the cursor', () {
      final edit = applyDictation(
        value: const TextEditingValue(
          text: 'Привет, ',
          selection: TextSelection.collapsed(offset: 8),
        ),
        range: const TextRange.collapsed(8),
        words: 'как дела',
      );
      expect(edit.value.text, 'Привет, как дела');
      expect(edit.value.selection.baseOffset, 16);
      expect(edit.range, const TextRange(start: 8, end: 16));
    });

    test('replaces the previous partial result instead of appending it', () {
      final first = applyDictation(
        value: const TextEditingValue(text: ''),
        range: const TextRange.collapsed(0),
        words: 'привет',
      );
      final second = applyDictation(
        value: first.value,
        range: first.range,
        words: 'привет мир',
      );
      expect(second.value.text, 'привет мир');
    });

    test('adds a space when continuing an existing word', () {
      final edit = applyDictation(
        value: const TextEditingValue(
          text: 'скажи',
          selection: TextSelection.collapsed(offset: 5),
        ),
        range: const TextRange.collapsed(5),
        words: 'ещё',
      );
      expect(edit.value.text, 'скажи ещё');
      expect(edit.range, const TextRange(start: 5, end: 9));
    });

    test('does not add a space before punctuation', () {
      final edit = applyDictation(
        value: const TextEditingValue(
          text: 'готово',
          selection: TextSelection.collapsed(offset: 6),
        ),
        range: const TextRange.collapsed(6),
        words: ', продолжай',
      );
      expect(edit.value.text, 'готово, продолжай');
    });

    test('keeps the text after a selection', () {
      final edit = applyDictation(
        value: const TextEditingValue(
          text: 'начало конец',
          selection: TextSelection(baseOffset: 7, extentOffset: 12),
        ),
        range: const TextRange(start: 7, end: 12),
        words: 'середина',
      );
      expect(edit.value.text, 'начало середина');
    });

    test('empty recognition leaves the text untouched', () {
      const value = TextEditingValue(
        text: 'текст',
        selection: TextSelection.collapsed(offset: 5),
      );
      final edit = applyDictation(
        value: value,
        range: const TextRange.collapsed(5),
        words: '',
      );
      expect(edit.value, value);
      expect(edit.range, const TextRange.collapsed(5));
    });
  });

  group('speech helpers', () {
    test('locale follows the app language', () {
      expect(voiceLocaleFor(english: false), 'ru_RU');
      expect(voiceLocaleFor(english: true), 'en_US');
    });

    test('common recognizer errors are human readable', () {
      expect(speechErrorMessage('error_no_match'), contains('Речь'));
      expect(speechErrorMessage('error_permission'), contains('микрофон'));
      expect(
        speechErrorMessage('error_language_not_supported'),
        contains('язык'),
      );
      expect(
        speechErrorMessage('error_unknown_thing'),
        contains('error_unknown_thing'),
      );
    });
  });

  testWidgets('chat parameters save a JSON schema format', (tester) async {
    final state = AppState();
    var disposed = false;
    void disposeState() {
      if (disposed) return;
      disposed = true;
      state.dispose();
    }

    addTearDown(disposeState);
    final chat = ChatSession(id: 'chat', serverId: 'server', model: 'model');
    state.data.chats.add(chat);
    state.activeChat = chat;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showChatParams(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Формат ответа'), findsOneWidget);

    await tester.tap(find.text('JSON по схеме'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).at(1),
      '{"type":"object","properties":{"a":{"type":"string"}}}',
    );
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(chat.responseFormat.mode, ResponseFormatMode.jsonSchema);
    expect(chat.responseFormat.schema, contains('"a"'));
    // Cancel the debounced history save so no timer outlives the test.
    disposeState();
  });
}
