import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexusone_mobile/theme/terminal_theme.dart';
import 'package:plexusone_mobile/utils/ansi_parser.dart';

void main() {
  group('AnsiParser.parse', () {
    test('returns single span for plain text', () {
      final spans = AnsiParser.parse('Hello World');

      expect(spans.length, 1);
      expect(spans[0].text, 'Hello World');
      expect(spans[0].foreground, isNull);
      expect(spans[0].bold, false);
    });

    test('handles empty string', () {
      final spans = AnsiParser.parse('');

      expect(spans, isEmpty);
    });

    test('parses reset code', () {
      final spans = AnsiParser.parse('\x1B[0mReset');

      expect(spans.length, 1);
      expect(spans[0].text, 'Reset');
      expect(spans[0].foreground, isNull);
      expect(spans[0].bold, false);
    });

    test('parses bold text', () {
      final spans = AnsiParser.parse('\x1B[1mBold Text');

      expect(spans.length, 1);
      expect(spans[0].text, 'Bold Text');
      expect(spans[0].bold, true);
    });

    test('parses dim text', () {
      final spans = AnsiParser.parse('\x1B[2mDim Text');

      expect(spans.length, 1);
      expect(spans[0].text, 'Dim Text');
      expect(spans[0].dim, true);
    });

    test('parses italic text', () {
      final spans = AnsiParser.parse('\x1B[3mItalic');

      expect(spans.length, 1);
      expect(spans[0].italic, true);
    });

    test('parses underline text', () {
      final spans = AnsiParser.parse('\x1B[4mUnderlined');

      expect(spans.length, 1);
      expect(spans[0].underline, true);
    });

    test('parses standard foreground colors', () {
      // Red (31)
      var spans = AnsiParser.parse('\x1B[31mRed');
      expect(spans[0].foreground, TerminalTheme.ansiRed);

      // Green (32)
      spans = AnsiParser.parse('\x1B[32mGreen');
      expect(spans[0].foreground, TerminalTheme.ansiGreen);

      // Yellow (33)
      spans = AnsiParser.parse('\x1B[33mYellow');
      expect(spans[0].foreground, TerminalTheme.ansiYellow);

      // Blue (34)
      spans = AnsiParser.parse('\x1B[34mBlue');
      expect(spans[0].foreground, TerminalTheme.ansiBlue);

      // Magenta (35)
      spans = AnsiParser.parse('\x1B[35mMagenta');
      expect(spans[0].foreground, TerminalTheme.ansiMagenta);

      // Cyan (36)
      spans = AnsiParser.parse('\x1B[36mCyan');
      expect(spans[0].foreground, TerminalTheme.ansiCyan);
    });

    test('parses bright foreground colors', () {
      // Bright red (91)
      const brightRed = Color(0xFFFF5555);
      final spans = AnsiParser.parse('\x1B[91mBright Red');
      expect(spans[0].foreground, brightRed);
    });

    test('parses standard background colors', () {
      // Red background (41)
      final spans = AnsiParser.parse('\x1B[41mRed BG');
      expect(spans[0].background, TerminalTheme.ansiRed);
    });

    test('parses combined codes', () {
      // Bold + Red
      final spans = AnsiParser.parse('\x1B[1;31mBold Red');

      expect(spans.length, 1);
      expect(spans[0].bold, true);
      expect(spans[0].foreground, TerminalTheme.ansiRed);
    });

    test('parses multiple spans with different styles', () {
      final spans = AnsiParser.parse('\x1B[31mRed\x1B[32mGreen\x1B[0mNormal');

      expect(spans.length, 3);
      expect(spans[0].text, 'Red');
      expect(spans[0].foreground, TerminalTheme.ansiRed);
      expect(spans[1].text, 'Green');
      expect(spans[1].foreground, TerminalTheme.ansiGreen);
      expect(spans[2].text, 'Normal');
      expect(spans[2].foreground, isNull);
    });

    test('handles text before first escape sequence', () {
      final spans = AnsiParser.parse('Prefix \x1B[31mRed');

      expect(spans.length, 2);
      expect(spans[0].text, 'Prefix ');
      expect(spans[0].foreground, isNull);
      expect(spans[1].text, 'Red');
      expect(spans[1].foreground, TerminalTheme.ansiRed);
    });

    test('parses 256-color foreground', () {
      // Color 196 is bright red in 256-color palette
      final spans = AnsiParser.parse('\x1B[38;5;196mColor 196');

      expect(spans.length, 1);
      expect(spans[0].foreground, isNotNull);
    });

    test('parses RGB foreground color', () {
      const expectedColor = Color.fromARGB(255, 255, 128, 64);
      final spans = AnsiParser.parse('\x1B[38;2;255;128;64mRGB Color');

      expect(spans.length, 1);
      expect(spans[0].foreground, expectedColor);
    });

    test('parses 256-color background', () {
      final spans = AnsiParser.parse('\x1B[48;5;21mBlue BG');

      expect(spans.length, 1);
      expect(spans[0].background, isNotNull);
    });

    test('parses RGB background color', () {
      const expectedColor = Color.fromARGB(255, 100, 150, 200);
      final spans = AnsiParser.parse('\x1B[48;2;100;150;200mRGB BG');

      expect(spans.length, 1);
      expect(spans[0].background, expectedColor);
    });

    test('handles default color codes', () {
      // Set color then reset to default
      final spans = AnsiParser.parse('\x1B[31mRed\x1B[39mDefault');

      expect(spans.length, 2);
      expect(spans[0].foreground, TerminalTheme.ansiRed);
      expect(spans[1].foreground, isNull);
    });

    test('handles intensity reset', () {
      final spans = AnsiParser.parse('\x1B[1mBold\x1B[22mNormal');

      expect(spans.length, 2);
      expect(spans[0].bold, true);
      expect(spans[1].bold, false);
    });

    test('style carries across spans', () {
      // Bold, then red (bold should persist)
      final spans = AnsiParser.parse('\x1B[1mBold \x1B[31mBold Red');

      expect(spans.length, 2);
      expect(spans[0].bold, true);
      expect(spans[0].foreground, isNull);
      expect(spans[1].bold, true);
      expect(spans[1].foreground, TerminalTheme.ansiRed);
    });
  });

  group('AnsiParser.stripAnsi', () {
    test('removes ANSI codes from text', () {
      final result = AnsiParser.stripAnsi('\x1B[31mRed\x1B[0m Normal');

      expect(result, 'Red Normal');
    });

    test('returns plain text unchanged', () {
      final result = AnsiParser.stripAnsi('Plain text');

      expect(result, 'Plain text');
    });

    test('handles empty string', () {
      final result = AnsiParser.stripAnsi('');

      expect(result, '');
    });

    test('removes multiple escape sequences', () {
      final result = AnsiParser.stripAnsi(
        '\x1B[1m\x1B[31mBold Red\x1B[0m \x1B[32mGreen\x1B[0m',
      );

      expect(result, 'Bold Red Green');
    });
  });

  group('AnsiParser.hasAnsiCodes', () {
    test('returns true for text with ANSI codes', () {
      expect(AnsiParser.hasAnsiCodes('\x1B[31mRed'), true);
    });

    test('returns false for plain text', () {
      expect(AnsiParser.hasAnsiCodes('Plain text'), false);
    });

    test('returns false for empty string', () {
      expect(AnsiParser.hasAnsiCodes(''), false);
    });
  });

  group('AnsiSpan.toTextSpan', () {
    test('creates TextSpan with correct style', () {
      final span = AnsiSpan(
        text: 'Test',
        foreground: Colors.red,
        bold: true,
        italic: true,
        underline: true,
      );

      final textSpan = span.toTextSpan();

      expect(textSpan.text, 'Test');
      expect(textSpan.style?.color, Colors.red);
      expect(textSpan.style?.fontWeight, FontWeight.bold);
      expect(textSpan.style?.fontStyle, FontStyle.italic);
      expect(textSpan.style?.decoration, TextDecoration.underline);
    });

    test('uses default color when foreground is null', () {
      final span = AnsiSpan(text: 'Test');

      final textSpan = span.toTextSpan(defaultColor: Colors.white);

      expect(textSpan.style?.color, Colors.white);
    });

    test('applies dim effect', () {
      final span = AnsiSpan(
        text: 'Dim',
        foreground: Colors.white,
        dim: true,
      );

      final textSpan = span.toTextSpan();

      // Dim should reduce opacity
      expect(textSpan.style?.color?.opacity, lessThan(1.0));
    });
  });

  group('256 color palette', () {
    test('parses standard colors (0-7)', () {
      for (var i = 0; i < 8; i++) {
        final spans = AnsiParser.parse('\x1B[38;5;${i}mColor $i');
        expect(spans[0].foreground, isNotNull);
      }
    });

    test('parses bright colors (8-15)', () {
      for (var i = 8; i < 16; i++) {
        final spans = AnsiParser.parse('\x1B[38;5;${i}mColor $i');
        expect(spans[0].foreground, isNotNull);
      }
    });

    test('parses color cube (16-231)', () {
      // Test a few samples from the color cube
      final spans = AnsiParser.parse('\x1B[38;5;196mRed-ish');
      expect(spans[0].foreground, isNotNull);
    });

    test('parses grayscale (232-255)', () {
      final spans = AnsiParser.parse('\x1B[38;5;244mGray');
      expect(spans[0].foreground, isNotNull);
    });
  });
}
