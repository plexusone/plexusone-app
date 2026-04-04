import 'package:flutter/material.dart';

import '../theme/terminal_theme.dart';

/// Represents a styled span of text parsed from ANSI escape sequences
class AnsiSpan {
  final String text;
  final Color? foreground;
  final Color? background;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool dim;

  const AnsiSpan({
    required this.text,
    this.foreground,
    this.background,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.dim = false,
  });

  /// Build a TextSpan from this AnsiSpan
  TextSpan toTextSpan({Color? defaultColor}) {
    return TextSpan(
      text: text,
      style: TextStyle(
        color: dim
            ? (foreground ?? defaultColor)?.withValues(alpha: 0.6)
            : (foreground ?? defaultColor),
        backgroundColor: background,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        decoration: underline ? TextDecoration.underline : TextDecoration.none,
      ),
    );
  }
}

/// Parser for ANSI escape sequences in terminal output
class AnsiParser {
  // ANSI CSI sequence pattern: ESC[ followed by params and a command letter
  static final _ansiPattern = RegExp(r'\x1B\[([0-9;]*)([A-Za-z])');

  // Pattern to match all escape sequences we want to strip (non-SGR)
  // Includes: CSI sequences, OSC sequences, other escape sequences
  static final _allEscapePattern = RegExp(
    r'\x1B'
    r'(?:'
    r'\[[0-9;]*[A-Za-z]|' // CSI sequences
    r'\][^\x07\x1B]*(?:\x07|\x1B\\)|' // OSC sequences (ended by BEL or ST)
    r'\([AB0-9]|' // Character set selection
    r'[=>NMOPHIJK78]|' // Single character escapes
    r'#[0-9]' // Line height
    r')',
  );

  // Control characters to strip (except newline, tab)
  static final _controlCharsPattern = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1A\x1C-\x1F\x7F]');

  // Standard ANSI colors (0-7)
  static const _standardColors = [
    TerminalTheme.ansiBlack, // 0 - Black
    TerminalTheme.ansiRed, // 1 - Red
    TerminalTheme.ansiGreen, // 2 - Green
    TerminalTheme.ansiYellow, // 3 - Yellow
    TerminalTheme.ansiBlue, // 4 - Blue
    TerminalTheme.ansiMagenta, // 5 - Magenta
    TerminalTheme.ansiCyan, // 6 - Cyan
    TerminalTheme.ansiWhite, // 7 - White
  ];

  // Bright ANSI colors (8-15)
  static const _brightColors = [
    Color(0xFF555555), // 8 - Bright Black (Gray)
    Color(0xFFFF5555), // 9 - Bright Red
    Color(0xFF55FF55), // 10 - Bright Green
    Color(0xFFFFFF55), // 11 - Bright Yellow
    Color(0xFF5555FF), // 12 - Bright Blue
    Color(0xFFFF55FF), // 13 - Bright Magenta
    Color(0xFF55FFFF), // 14 - Bright Cyan
    Color(0xFFFFFFFF), // 15 - Bright White
  ];

  /// Parse a string containing ANSI escape sequences into styled spans
  static List<AnsiSpan> parse(String text) {
    final spans = <AnsiSpan>[];
    var currentIndex = 0;

    // Current style state
    Color? foreground;
    Color? background;
    var bold = false;
    var italic = false;
    var underline = false;
    var dim = false;

    for (final match in _ansiPattern.allMatches(text)) {
      // Add any text before this escape sequence
      if (match.start > currentIndex) {
        final beforeText = text.substring(currentIndex, match.start);
        if (beforeText.isNotEmpty) {
          spans.add(AnsiSpan(
            text: beforeText,
            foreground: foreground,
            background: background,
            bold: bold,
            italic: italic,
            underline: underline,
            dim: dim,
          ));
        }
      }

      // Parse the escape sequence
      final params = match.group(1) ?? '';
      final command = match.group(2) ?? '';

      // Only handle SGR (Select Graphic Rendition) commands - 'm'
      if (command == 'm') {
        final codes = params.isEmpty
            ? [0]
            : params.split(';').map((s) => int.tryParse(s) ?? 0).toList();

        var i = 0;
        while (i < codes.length) {
          final code = codes[i];

          switch (code) {
            case 0: // Reset
              foreground = null;
              background = null;
              bold = false;
              italic = false;
              underline = false;
              dim = false;
              break;
            case 1: // Bold
              bold = true;
              break;
            case 2: // Dim
              dim = true;
              break;
            case 3: // Italic
              italic = true;
              break;
            case 4: // Underline
              underline = true;
              break;
            case 22: // Normal intensity (not bold, not dim)
              bold = false;
              dim = false;
              break;
            case 23: // Not italic
              italic = false;
              break;
            case 24: // Not underlined
              underline = false;
              break;
            case 30:
            case 31:
            case 32:
            case 33:
            case 34:
            case 35:
            case 36:
            case 37: // Standard foreground colors
              foreground = _standardColors[code - 30];
              break;
            case 38: // Extended foreground color
              if (i + 1 < codes.length) {
                if (codes[i + 1] == 5 && i + 2 < codes.length) {
                  // 256 color mode: 38;5;n
                  foreground = _get256Color(codes[i + 2]);
                  i += 2;
                } else if (codes[i + 1] == 2 && i + 4 < codes.length) {
                  // RGB mode: 38;2;r;g;b
                  foreground = Color.fromARGB(
                    255,
                    codes[i + 2].clamp(0, 255),
                    codes[i + 3].clamp(0, 255),
                    codes[i + 4].clamp(0, 255),
                  );
                  i += 4;
                }
              }
              break;
            case 39: // Default foreground
              foreground = null;
              break;
            case 40:
            case 41:
            case 42:
            case 43:
            case 44:
            case 45:
            case 46:
            case 47: // Standard background colors
              background = _standardColors[code - 40];
              break;
            case 48: // Extended background color
              if (i + 1 < codes.length) {
                if (codes[i + 1] == 5 && i + 2 < codes.length) {
                  // 256 color mode: 48;5;n
                  background = _get256Color(codes[i + 2]);
                  i += 2;
                } else if (codes[i + 1] == 2 && i + 4 < codes.length) {
                  // RGB mode: 48;2;r;g;b
                  background = Color.fromARGB(
                    255,
                    codes[i + 2].clamp(0, 255),
                    codes[i + 3].clamp(0, 255),
                    codes[i + 4].clamp(0, 255),
                  );
                  i += 4;
                }
              }
              break;
            case 49: // Default background
              background = null;
              break;
            case 90:
            case 91:
            case 92:
            case 93:
            case 94:
            case 95:
            case 96:
            case 97: // Bright foreground colors
              foreground = _brightColors[code - 90];
              break;
            case 100:
            case 101:
            case 102:
            case 103:
            case 104:
            case 105:
            case 106:
            case 107: // Bright background colors
              background = _brightColors[code - 100];
              break;
          }
          i++;
        }
      }

      currentIndex = match.end;
    }

    // Add any remaining text after the last escape sequence
    if (currentIndex < text.length) {
      final remainingText = text.substring(currentIndex);
      if (remainingText.isNotEmpty) {
        spans.add(AnsiSpan(
          text: remainingText,
          foreground: foreground,
          background: background,
          bold: bold,
          italic: italic,
          underline: underline,
          dim: dim,
        ));
      }
    }

    // If no spans were created (no escape sequences), return the whole text
    if (spans.isEmpty && text.isNotEmpty) {
      spans.add(AnsiSpan(text: text));
    }

    return spans;
  }

  /// Get color from 256-color palette
  static Color _get256Color(int index) {
    if (index < 0 || index > 255) {
      return TerminalTheme.foreground;
    }

    // Standard colors (0-7)
    if (index < 8) {
      return _standardColors[index];
    }

    // Bright colors (8-15)
    if (index < 16) {
      return _brightColors[index - 8];
    }

    // 216 color cube (16-231)
    if (index < 232) {
      final i = index - 16;
      final r = (i ~/ 36) * 51;
      final g = ((i ~/ 6) % 6) * 51;
      final b = (i % 6) * 51;
      return Color.fromARGB(255, r, g, b);
    }

    // Grayscale (232-255)
    final gray = (index - 232) * 10 + 8;
    return Color.fromARGB(255, gray, gray, gray);
  }

  /// Strip all ANSI escape sequences from text
  static String stripAnsi(String text) {
    return text
        .replaceAll(_allEscapePattern, '')
        .replaceAll(_controlCharsPattern, '');
  }

  /// Check if text contains any ANSI escape sequences
  static bool hasAnsiCodes(String text) {
    return _ansiPattern.hasMatch(text);
  }

  /// Clean text by removing non-SGR escape sequences and control characters
  /// while preserving SGR sequences for color parsing
  static String cleanForParsing(String text) {
    // First, handle carriage return (move cursor to start of line)
    // This is commonly used for progress bars - keep only the last segment
    if (text.contains('\r')) {
      final lines = text.split('\n');
      final cleanedLines = lines.map((line) {
        if (line.contains('\r')) {
          final segments = line.split('\r');
          return segments.last;
        }
        return line;
      }).toList();
      text = cleanedLines.join('\n');
    }

    // Remove non-SGR CSI sequences (cursor movement, erase, etc.)
    text = text.replaceAllMapped(
      RegExp(r'\x1B\[([0-9;]*)([A-LN-Za-z])'),
      (match) {
        final cmd = match.group(2);
        // Only keep SGR sequences (m command)
        if (cmd == 'm') {
          return match.group(0)!;
        }
        return '';
      },
    );

    // Remove OSC sequences
    text = text.replaceAll(RegExp(r'\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)'), '');

    // Remove other escape sequences
    text = text.replaceAll(RegExp(r'\x1B[\(\)][AB0-9]'), '');
    text = text.replaceAll(RegExp(r'\x1B[=>NMOPHIJK78#]'), '');

    // Remove control characters (except \n, \t)
    text = text.replaceAll(_controlCharsPattern, '');

    return text;
  }
}
