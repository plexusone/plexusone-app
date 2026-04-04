import 'package:flutter_test/flutter_test.dart';
import 'package:plexusone_mobile/models/session.dart';

void main() {
  group('Session', () {
    test('fromJson parses valid JSON', () {
      final json = {
        'id': 'session-1',
        'name': 'claude-code',
        'status': 'running',
        'lastActivity': 1711929600,
      };

      final session = Session.fromJson(json);

      expect(session.id, 'session-1');
      expect(session.name, 'claude-code');
      expect(session.status, 'running');
      expect(session.lastActivity, DateTime.fromMillisecondsSinceEpoch(1711929600 * 1000));
    });

    test('fromJson uses defaults for missing fields', () {
      final json = {
        'id': 'session-1',
        'name': 'test',
      };

      final session = Session.fromJson(json);

      expect(session.status, 'idle');
      expect(session.lastActivity, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('isRunning returns true for running status', () {
      final session = Session(
        id: '1',
        name: 'test',
        status: 'running',
        lastActivity: DateTime.now(),
      );

      expect(session.isRunning, true);
      expect(session.isIdle, false);
      expect(session.isStuck, false);
    });

    test('isIdle returns true for idle status', () {
      final session = Session(
        id: '1',
        name: 'test',
        status: 'idle',
        lastActivity: DateTime.now(),
      );

      expect(session.isRunning, false);
      expect(session.isIdle, true);
      expect(session.isStuck, false);
    });

    test('isStuck returns true for stuck status', () {
      final session = Session(
        id: '1',
        name: 'test',
        status: 'stuck',
        lastActivity: DateTime.now(),
      );

      expect(session.isRunning, false);
      expect(session.isIdle, false);
      expect(session.isStuck, true);
    });
  });

  group('OutputLine', () {
    test('creates with default style and timestamp', () {
      final line = OutputLine(text: 'Hello world');

      expect(line.text, 'Hello world');
      expect(line.style, LineStyle.normal);
      expect(line.timestamp, isA<DateTime>());
    });

    test('creates with custom style', () {
      final line = OutputLine(text: 'Error!', style: LineStyle.error);

      expect(line.style, LineStyle.error);
    });
  });

  group('Prompt', () {
    test('fromJson parses yes/no prompt', () {
      final json = {
        'promptType': 'yes_no',
        'title': 'Confirm',
        'message': 'Continue?',
        'options': ['yes', 'no'],
        'defaultOption': 'yes',
      };

      final prompt = Prompt.fromJson(json);

      expect(prompt.type, PromptType.yesNo);
      expect(prompt.title, 'Confirm');
      expect(prompt.message, 'Continue?');
      expect(prompt.options, ['yes', 'no']);
      expect(prompt.defaultOption, 'yes');
    });

    test('fromJson parses input prompt', () {
      final json = {
        'promptType': 'input',
        'message': 'Enter your name:',
      };

      final prompt = Prompt.fromJson(json);

      expect(prompt.type, PromptType.input);
      expect(prompt.message, 'Enter your name:');
      expect(prompt.options, isEmpty);
    });

    test('fromJson parses choice prompt', () {
      final json = {
        'promptType': 'choice',
        'message': 'Select option:',
        'options': ['Option A', 'Option B', 'Option C'],
      };

      final prompt = Prompt.fromJson(json);

      expect(prompt.type, PromptType.choice);
      expect(prompt.options, ['Option A', 'Option B', 'Option C']);
    });

    test('fromJson uses defaults for missing fields', () {
      final json = <String, dynamic>{};

      final prompt = Prompt.fromJson(json);

      expect(prompt.type, PromptType.input);
      expect(prompt.message, '');
      expect(prompt.options, isEmpty);
      expect(prompt.title, isNull);
      expect(prompt.defaultOption, isNull);
    });
  });

  group('PromptType', () {
    test('fromString parses known types', () {
      expect(PromptType.fromString('yes_no'), PromptType.yesNo);
      expect(PromptType.fromString('input'), PromptType.input);
      expect(PromptType.fromString('choice'), PromptType.choice);
      expect(PromptType.fromString('menu'), PromptType.menu);
    });

    test('fromString defaults to input for unknown types', () {
      expect(PromptType.fromString('unknown'), PromptType.input);
      expect(PromptType.fromString(''), PromptType.input);
    });
  });

  group('MenuItem', () {
    test('fromJson parses valid JSON', () {
      final json = {
        'label': 'Option 1',
        'selected': true,
        'index': 0,
      };

      final item = MenuItem.fromJson(json);

      expect(item.label, 'Option 1');
      expect(item.selected, true);
      expect(item.index, 0);
    });

    test('fromJson uses defaults for missing fields', () {
      final json = {
        'label': 'Option',
      };

      final item = MenuItem.fromJson(json);

      expect(item.selected, false);
      expect(item.index, 0);
    });
  });

  group('Menu', () {
    test('fromJson parses valid JSON', () {
      final json = {
        'title': 'Select an option',
        'items': [
          {'label': 'Option 1', 'selected': true, 'index': 0},
          {'label': 'Option 2', 'selected': false, 'index': 1},
        ],
        'currentIndex': 0,
        'multiSelect': false,
      };

      final menu = Menu.fromJson(json);

      expect(menu.title, 'Select an option');
      expect(menu.items.length, 2);
      expect(menu.items[0].label, 'Option 1');
      expect(menu.items[0].selected, true);
      expect(menu.currentIndex, 0);
      expect(menu.multiSelect, false);
    });

    test('fromJson handles multiSelect menu', () {
      final json = {
        'items': [
          {'label': 'A', 'selected': true, 'index': 0},
          {'label': 'B', 'selected': true, 'index': 1},
        ],
        'currentIndex': 1,
        'multiSelect': true,
      };

      final menu = Menu.fromJson(json);

      expect(menu.multiSelect, true);
      expect(menu.title, isNull);
    });
  });
}
