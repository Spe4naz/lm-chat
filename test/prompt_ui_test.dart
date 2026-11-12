import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/app_state.dart';
import 'package:lm_chat/l10n.dart';
import 'package:lm_chat/models.dart';
import 'package:lm_chat/widgets/prompt_library_sheet.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => L10n.setLanguage('ru'));

  testWidgets('prompt picker returns the fully translated built-in prompt', (
    tester,
  ) async {
    L10n.setLanguage('en');
    final state = AppState();
    addTearDown(state.dispose);
    String? selected;

    await _pumpLibrary(tester, state, (value) => selected = value);
    await tester.tap(find.text('Short and to the point'));
    await tester.pumpAndSettle();

    expect(selected, contains('Answer briefly and to the point.'));
    expect(selected, isNot(contains('Отвечай')));
    expect(selected, isNot(contains('вступлений')));
  });

  testWidgets('prompt picker keeps custom prompt text verbatim', (
    tester,
  ) async {
    L10n.setLanguage('en');
    final state = AppState();
    addTearDown(state.dispose);
    const custom = 'Не выдумывай API, которых нет.';
    state.data.promptTemplates.add(
      const PromptTemplate(id: 'custom', name: 'My prompt', content: custom),
    );
    String? selected;

    await _pumpLibrary(tester, state, (value) => selected = value);
    await tester.enterText(find.byType(TextField).first, 'My prompt');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'My prompt'));
    await tester.pumpAndSettle();

    expect(selected, custom);
  });
}

Future<void> _pumpLibrary(
  WidgetTester tester,
  AppState state,
  ValueChanged<String> onSelect,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPromptLibrary(context, onSelect: onSelect),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
