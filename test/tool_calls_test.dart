import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/models.dart';
import 'package:lm_chat/widgets/message_bubble.dart';

void main() {
  group('applyToolCallEvent', () {
    test('walks a call from start to success', () {
      final calls = <ToolCallRecord>[];
      applyToolCallEvent(
        calls,
        const ToolCallEvent(kind: ToolCallEventKind.start, name: 'fs_mkdir'),
      );
      expect(calls, hasLength(1));
      expect(calls.single.isRunning, isTrue);

      applyToolCallEvent(
        calls,
        const ToolCallEvent(
          kind: ToolCallEventKind.arguments,
          name: 'fs_mkdir',
          arguments: '{"path":"lmchat-test"}',
        ),
      );
      expect(calls.single.arguments, contains('lmchat-test'));

      applyToolCallEvent(
        calls,
        const ToolCallEvent(
          kind: ToolCallEventKind.success,
          name: 'fs_mkdir',
          arguments: '{"path":"lmchat-test"}',
          output: '[{"type":"text","text":"created"}]',
        ),
      );
      expect(calls.single.status, ToolCallStatus.success);
      expect(calls.single.isRunning, isFalse);
      expect(calls.single.readableOutput, 'created');
      expect(calls.single.durationMs, isNotNull);
    });

    test('a failure without start still produces a record', () {
      final calls = <ToolCallRecord>[];
      applyToolCallEvent(
        calls,
        const ToolCallEvent(
          kind: ToolCallEventKind.failure,
          name: 'open_browser',
          error: 'Cannot find tool with name open_browser.',
        ),
      );
      expect(calls, hasLength(1));
      expect(calls.single.isFailure, isTrue);
      expect(calls.single.error, contains('Cannot find'));
    });

    test('an unnamed start is named by tool_call.name', () {
      final calls = <ToolCallRecord>[];
      applyToolCallEvent(
        calls,
        const ToolCallEvent(kind: ToolCallEventKind.start, name: ''),
      );
      expect(calls, hasLength(1));
      expect(calls.single.name, isEmpty);

      applyToolCallEvent(
        calls,
        const ToolCallEvent(kind: ToolCallEventKind.name, name: 'fs_list'),
      );
      expect(calls, hasLength(1), reason: 'name must not add a second row');
      expect(calls.single.name, 'fs_list');
      expect(calls.single.isRunning, isTrue);

      applyToolCallEvent(
        calls,
        const ToolCallEvent(
          kind: ToolCallEventKind.arguments,
          name: 'fs_list',
          arguments: '{"path":"."}',
        ),
      );
      applyToolCallEvent(
        calls,
        const ToolCallEvent(
          kind: ToolCallEventKind.success,
          name: 'fs_list',
          output: '[{"type":"text","text":"a.txt"}]',
        ),
      );
      expect(calls, hasLength(1));
      expect(calls.single.status, ToolCallStatus.success);
      expect(calls.single.readableOutput, 'a.txt');
    });

    test('sequential named calls leave no unnamed leftovers', () {
      final calls = <ToolCallRecord>[];
      void call(String name) {
        applyToolCallEvent(
          calls,
          const ToolCallEvent(kind: ToolCallEventKind.start, name: ''),
        );
        applyToolCallEvent(
          calls,
          ToolCallEvent(kind: ToolCallEventKind.name, name: name),
        );
        applyToolCallEvent(
          calls,
          ToolCallEvent(
            kind: ToolCallEventKind.arguments,
            name: name,
            arguments: '{"path":"site1"}',
          ),
        );
        applyToolCallEvent(
          calls,
          ToolCallEvent(
            kind: ToolCallEventKind.success,
            name: name,
            output: 'ok',
          ),
        );
      }

      call('fs_mkdir');
      call('fs_write');

      expect(calls, hasLength(2));
      expect(calls.map((c) => c.name), ['fs_mkdir', 'fs_write']);
      expect(calls.every((c) => c.status == ToolCallStatus.success), isTrue);
      expect(calls.every((c) => !c.isRunning), isTrue);
    });

    test('parallel named calls are matched by name', () {
      final calls = <ToolCallRecord>[];
      applyToolCallEvent(
        calls,
        const ToolCallEvent(kind: ToolCallEventKind.start, name: 'read_file'),
      );
      applyToolCallEvent(
        calls,
        const ToolCallEvent(kind: ToolCallEventKind.start, name: 'write_file'),
      );
      applyToolCallEvent(
        calls,
        const ToolCallEvent(
          kind: ToolCallEventKind.success,
          name: 'read_file',
          output: 'ok',
        ),
      );
      expect(calls[0].status, ToolCallStatus.success);
      expect(calls[1].isRunning, isTrue);
    });
  });

  group('persistence', () {
    test('tool calls survive a JSON round trip', () {
      final message = ChatMessage(
        id: 'a1',
        role: 'assistant',
        content: 'готово',
        toolCalls: [
          ToolCallRecord(
            name: 'fs_mkdir',
            arguments: '{"path":"lmchat-test"}',
            output: '[{"type":"text","text":"created"}]',
            status: ToolCallStatus.success,
            finishedAt: DateTime.now(),
          ),
        ],
      );

      final restored = ChatMessage.fromJson(message.toJson());
      expect(restored.toolCalls, hasLength(1));
      expect(restored.toolCalls.single.name, 'fs_mkdir');
      expect(restored.toolCalls.single.status, ToolCallStatus.success);
      expect(restored.toolCalls.single.readableOutput, 'created');
    });

    test('archiving moves the calls and restoring brings them back', () {
      final message = ChatMessage(
        id: 'a1',
        role: 'assistant',
        content: 'ответ',
        toolCalls: [ToolCallRecord(name: 'fs_list')],
      );

      final version = message.archiveCurrent();
      expect(version?.toolCalls, hasLength(1));
      expect(message.toolCalls, isEmpty);

      message.toolCalls.add(ToolCallRecord(name: 'fs_read'));
      expect(message.restoreLatestArchived(), isTrue);
      expect(message.toolCalls, hasLength(1));
      expect(message.toolCalls.single.name, 'fs_list');
    });

    test('loading drops the ghost rows saved by 1.8.5', () {
      final message = ChatMessage(
        id: 'a1',
        role: 'assistant',
        content: 'готово',
        toolCalls: [
          ToolCallRecord(name: 'tool'),
          ToolCallRecord(name: ''),
          ToolCallRecord(
            name: 'fs_mkdir',
            output: 'ok',
            status: ToolCallStatus.success,
            finishedAt: DateTime.now(),
          ),
          ToolCallRecord(name: 'fs_list'),
        ],
      );

      final restored = ChatMessage.fromJson(message.toJson());
      expect(restored.toolCalls.map((call) => call.name), [
        'fs_mkdir',
        'fs_list',
      ]);
      expect(restored.toolCalls.last.status, ToolCallStatus.failure);
      expect(restored.toolCalls.last.error, 'Вызов прерван');
    });

    test('an answer with only a tool call is not considered empty', () {
      final message = ChatMessage(
        id: 'a1',
        role: 'assistant',
        toolCalls: [ToolCallRecord(name: 'fs_mkdir')],
      );
      expect(message.archiveCurrent(), isNotNull);
      expect(message.versions.single.content, isEmpty);
      expect(message.versions.single.toolCalls, hasLength(1));
    });
  });

  testWidgets('the bubble lists tools and expands their details', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 'a1',
      role: 'assistant',
      content: 'Папка создана.',
      toolCalls: [
        ToolCallRecord(
          name: 'fs_mkdir',
          arguments: '{"path":"lmchat-test"}',
          output: '[{"type":"text","text":"created"}]',
          status: ToolCallStatus.success,
          finishedAt: DateTime.now(),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MessageBubble(message: message)),
      ),
    );

    expect(find.text('Инструменты: 1'), findsOneWidget);
    expect(find.text('fs_mkdir'), findsOneWidget);
    expect(find.textContaining('path: lmchat-test'), findsOneWidget);
    expect(find.text('Аргументы'), findsNothing);

    await tester.tap(find.text('fs_mkdir'));
    await tester.pumpAndSettle();

    expect(find.text('Аргументы'), findsOneWidget);
    expect(find.text('Результат'), findsOneWidget);
    expect(find.textContaining('lmchat-test'), findsWidgets);
  });
}
