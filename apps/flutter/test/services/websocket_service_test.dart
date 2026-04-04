import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plexusone_mobile/models/session.dart';
import 'package:plexusone_mobile/services/websocket_service.dart';

void main() {
  group('WebSocketService', () {
    late WebSocketService service;

    setUp(() {
      service = WebSocketService();
    });

    tearDown(() {
      service.dispose();
    });

    test('initial state is disconnected', () {
      expect(service.connectionState, WsConnectionState.disconnected);
      expect(service.errorMessage, isNull);
      expect(service.sessions, isEmpty);
      expect(service.currentSessionId, isNull);
      expect(service.currentOutput, isEmpty);
      expect(service.activePrompt, isNull);
      expect(service.activeMenu, isNull);
    });

    test('serverAddress has default value', () {
      expect(service.serverAddress, 'localhost:9600');
    });

    test('sessions list is unmodifiable', () {
      final sessions = service.sessions;
      expect(
        () => sessions.add(Session(
          id: '1',
          name: 'test',
          status: 'idle',
          lastActivity: DateTime.now(),
        )),
        throwsUnsupportedError,
      );
    });
  });

  group('WebSocketService message handling', () {
    late WebSocketService service;

    setUp(() {
      service = WebSocketService();
    });

    tearDown(() {
      service.dispose();
    });

    void simulateMessage(Map<String, dynamic> message) {
      service.handleMessage(jsonEncode(message));
    }

    test('handles sessions message', () {
      simulateMessage({
        'type': 'sessions',
        'sessions': [
          {'id': 'session-1', 'name': 'claude-code', 'status': 'running'},
          {'id': 'session-2', 'name': 'kiro', 'status': 'idle'},
        ],
      });

      expect(service.sessions.length, 2);
      expect(service.sessions[0].id, 'session-1');
      expect(service.sessions[0].name, 'claude-code');
      expect(service.sessions[1].id, 'session-2');
    });

    test('handles output message', () {
      // Subscribe to a session first
      service.setCurrentSessionIdForTest('session-1');

      simulateMessage({
        'type': 'output',
        'sessionId': 'session-1',
        'text': 'Hello\nWorld',
      });

      expect(service.currentOutput.length, 2);
      expect(service.currentOutput[0].text, 'Hello');
      expect(service.currentOutput[1].text, 'World');
    });

    test('handles output message with buffer limit', () {
      service.setCurrentSessionIdForTest('session-1');

      // Simulate output that exceeds buffer limit
      final longText = List.generate(10001, (i) => 'Line $i').join('\n');
      simulateMessage({
        'type': 'output',
        'sessionId': 'session-1',
        'text': longText,
      });

      expect(service.currentOutput.length, 10000);
    });

    test('handles prompt message', () {
      simulateMessage({
        'type': 'prompt',
        'promptType': 'yes_no',
        'message': 'Continue?',
        'options': ['yes', 'no'],
      });

      expect(service.activePrompt, isNotNull);
      expect(service.activePrompt!.type, PromptType.yesNo);
      expect(service.activePrompt!.message, 'Continue?');
      expect(service.activeMenu, isNull);
    });

    test('handles menu message', () {
      simulateMessage({
        'type': 'menu',
        'title': 'Select option',
        'items': [
          {'label': 'Option 1', 'selected': false, 'index': 0},
          {'label': 'Option 2', 'selected': true, 'index': 1},
        ],
        'currentIndex': 1,
      });

      expect(service.activeMenu, isNotNull);
      expect(service.activeMenu!.title, 'Select option');
      expect(service.activeMenu!.items.length, 2);
      expect(service.activePrompt, isNull);
    });

    test('handles status message', () {
      // First add a session
      simulateMessage({
        'type': 'sessions',
        'sessions': [
          {'id': 'session-1', 'name': 'test', 'status': 'idle'},
        ],
      });

      expect(service.sessions[0].status, 'idle');

      // Now update its status
      simulateMessage({
        'type': 'status',
        'sessionId': 'session-1',
        'status': 'running',
      });

      expect(service.sessions[0].status, 'running');
    });

    test('handles clear message', () {
      service.setCurrentSessionIdForTest('session-1');

      simulateMessage({
        'type': 'output',
        'sessionId': 'session-1',
        'text': 'Some output',
      });

      expect(service.currentOutput.length, 1);

      simulateMessage({
        'type': 'clear',
        'sessionId': 'session-1',
      });

      expect(service.currentOutput, isEmpty);
    });

    test('handles error message', () {
      simulateMessage({
        'type': 'error',
        'error': 'Connection failed',
      });

      expect(service.errorMessage, 'Connection failed');
    });

    test('menu clears prompt when received', () {
      // Set a prompt first
      simulateMessage({
        'type': 'prompt',
        'promptType': 'input',
        'message': 'Enter text:',
      });

      expect(service.activePrompt, isNotNull);

      // Receive menu - should clear prompt
      simulateMessage({
        'type': 'menu',
        'items': [
          {'label': 'A', 'selected': false, 'index': 0}
        ],
        'currentIndex': 0,
      });

      expect(service.activePrompt, isNull);
      expect(service.activeMenu, isNotNull);
    });

    test('prompt clears menu when received', () {
      // Set a menu first
      simulateMessage({
        'type': 'menu',
        'items': [
          {'label': 'A', 'selected': false, 'index': 0}
        ],
        'currentIndex': 0,
      });

      expect(service.activeMenu, isNotNull);

      // Receive prompt - should clear menu
      simulateMessage({
        'type': 'prompt',
        'promptType': 'input',
        'message': 'Enter text:',
      });

      expect(service.activeMenu, isNull);
      expect(service.activePrompt, isNotNull);
    });

    test('ignores malformed messages', () {
      // Should not throw
      service.handleMessage('not valid json');
      service.handleMessage('{"type": null}');
      service.handleMessage('{"type": "unknown"}');

      expect(service.sessions, isEmpty);
    });
  });

  group('WebSocketService subscription', () {
    late WebSocketService service;

    setUp(() {
      service = WebSocketService();
    });

    tearDown(() {
      service.dispose();
    });

    test('setCurrentSessionIdForTest sets currentSessionId', () {
      service.setCurrentSessionIdForTest('session-1');

      expect(service.currentSessionId, 'session-1');
    });

    test('setCurrentSessionIdForTest creates output buffer for session', () {
      service.setCurrentSessionIdForTest('session-1');

      // Output buffer should exist (empty)
      service.handleMessage(jsonEncode({
        'type': 'output',
        'sessionId': 'session-1',
        'text': 'test',
      }));

      expect(service.currentOutput.length, 1);
    });

    test('clearOutput removes lines for session', () {
      service.setCurrentSessionIdForTest('session-1');

      service.handleMessage(jsonEncode({
        'type': 'output',
        'sessionId': 'session-1',
        'text': 'Line 1\nLine 2',
      }));

      expect(service.currentOutput.length, 2);

      service.clearOutput('session-1');

      expect(service.currentOutput, isEmpty);
    });

    test('getOutputForSession returns output for specific session', () {
      service.setCurrentSessionIdForTest('session-1');
      service.handleMessage(jsonEncode({
        'type': 'output',
        'sessionId': 'session-1',
        'text': 'Output 1',
      }));

      // Add output to another session
      service.handleMessage(jsonEncode({
        'type': 'output',
        'sessionId': 'session-2',
        'text': 'Output 2',
      }));

      final session1Output = service.getOutputForSession('session-1');
      final session2Output = service.getOutputForSession('session-2');

      expect(session1Output.length, 1);
      expect(session1Output[0].text, 'Output 1');
      expect(session2Output.length, 1);
      expect(session2Output[0].text, 'Output 2');
    });

    test('getOutputForSession returns empty for unknown session', () {
      expect(service.getOutputForSession('unknown'), isEmpty);
    });
  });

  group('WebSocketService notifies listeners', () {
    late WebSocketService service;
    late int notificationCount;

    setUp(() {
      service = WebSocketService();
      notificationCount = 0;
      service.addListener(() {
        notificationCount++;
      });
    });

    tearDown(() {
      service.dispose();
    });

    test('notifies on session update', () {
      service.handleMessage(jsonEncode({
        'type': 'sessions',
        'sessions': [
          {'id': '1', 'name': 'test'},
        ],
      }));

      expect(notificationCount, 1);
    });

    test('notifies on output', () {
      service.setCurrentSessionIdForTest('session-1');
      notificationCount = 0;

      service.handleMessage(jsonEncode({
        'type': 'output',
        'sessionId': 'session-1',
        'text': 'test',
      }));

      expect(notificationCount, 1);
    });

    test('notifies on prompt', () {
      service.handleMessage(jsonEncode({
        'type': 'prompt',
        'promptType': 'input',
        'message': 'test',
      }));

      expect(notificationCount, 1);
    });

    test('notifies on clearOutput', () {
      service.setCurrentSessionIdForTest('session-1');
      notificationCount = 0;

      service.clearOutput('session-1');

      expect(notificationCount, 1);
    });
  });
}
