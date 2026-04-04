import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart' as xterm;

import '../models/session.dart';
import '../theme/terminal_theme.dart' as app_theme;

/// Terminal-style output view using xterm package
class TerminalView extends StatefulWidget {
  final List<OutputLine> lines;
  final bool autoScroll;

  const TerminalView({
    super.key,
    required this.lines,
    this.autoScroll = true,
  });

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<TerminalView> {
  late xterm.Terminal _terminal;
  late xterm.TerminalController _terminalController;
  int _lastLineCount = 0;

  @override
  void initState() {
    super.initState();
    _terminal = xterm.Terminal(maxLines: 10000);
    _terminalController = xterm.TerminalController();
    _writeLines(widget.lines);
  }

  @override
  void didUpdateWidget(TerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Only write new lines
    if (widget.lines.length > _lastLineCount) {
      final newLines = widget.lines.sublist(_lastLineCount);
      _writeLines(newLines);
    } else if (widget.lines.length < _lastLineCount) {
      // Lines were cleared, reset terminal
      _terminal = xterm.Terminal(maxLines: 10000);
      _lastLineCount = 0;
      _writeLines(widget.lines);
      setState(() {});
    }
  }

  void _writeLines(List<OutputLine> lines) {
    for (final line in lines) {
      _terminal.write('${line.text}\r\n');
    }
    _lastLineCount = widget.lines.length;
  }

  @override
  void dispose() {
    _terminalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use double.infinity to force the container to fill all available space
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: app_theme.TerminalTheme.background,
      child: widget.lines.isEmpty
          ? const Center(
              child: Text(
                'No output yet',
                style: TextStyle(
                  color: app_theme.TerminalTheme.foregroundDim,
                  fontFamily: 'Menlo',
                  fontSize: 14,
                ),
              ),
            )
          : xterm.TerminalView(
              _terminal,
              controller: _terminalController,
              theme: xterm.TerminalTheme(
                cursor: app_theme.TerminalTheme.primary,
                selection: app_theme.TerminalTheme.primary.withValues(alpha: 0.3),
                foreground: app_theme.TerminalTheme.foreground,
                background: app_theme.TerminalTheme.background,
                black: app_theme.TerminalTheme.ansiBlack,
                red: app_theme.TerminalTheme.ansiRed,
                green: app_theme.TerminalTheme.ansiGreen,
                yellow: app_theme.TerminalTheme.ansiYellow,
                blue: app_theme.TerminalTheme.ansiBlue,
                magenta: app_theme.TerminalTheme.ansiMagenta,
                cyan: app_theme.TerminalTheme.ansiCyan,
                white: app_theme.TerminalTheme.ansiWhite,
                brightBlack: const Color(0xFF555555),
                brightRed: const Color(0xFFFF5555),
                brightGreen: const Color(0xFF55FF55),
                brightYellow: const Color(0xFFFFFF55),
                brightBlue: const Color(0xFF5555FF),
                brightMagenta: const Color(0xFFFF55FF),
                brightCyan: const Color(0xFF55FFFF),
                brightWhite: const Color(0xFFFFFFFF),
                searchHitBackground: app_theme.TerminalTheme.yellow,
                searchHitBackgroundCurrent: app_theme.TerminalTheme.orange,
                searchHitForeground: app_theme.TerminalTheme.background,
              ),
              textStyle: const xterm.TerminalStyle(
                fontSize: 14,
                fontFamily: 'Menlo',
              ),
              readOnly: true,
              autofocus: false,
            ),
    );
  }
}
