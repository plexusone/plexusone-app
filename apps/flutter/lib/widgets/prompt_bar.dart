import 'package:flutter/material.dart';

import '../models/session.dart';
import '../theme/terminal_theme.dart';

/// Context-aware input bar for prompts and menus
class PromptBar extends StatefulWidget {
  final Prompt? activePrompt;
  final Menu? activeMenu;
  final Function(String) onAction;
  final Function(String) onInput;
  final Function(String) onKey;

  const PromptBar({
    super.key,
    this.activePrompt,
    this.activeMenu,
    required this.onAction,
    required this.onInput,
    required this.onKey,
  });

  @override
  State<PromptBar> createState() => _PromptBarState();
}

class _PromptBarState extends State<PromptBar> {
  final TextEditingController _controller = TextEditingController();
  bool _showDpad = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: TerminalTheme.surface,
        border: Border(
          top: BorderSide(color: TerminalTheme.surfaceLight),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.activePrompt != null) _buildPromptUI(),
          if (widget.activeMenu != null) _buildMenuUI(),
          if (widget.activePrompt == null && widget.activeMenu == null)
            _buildDefaultUI(),
        ],
      ),
    );
  }

  Widget _buildPromptUI() {
    final prompt = widget.activePrompt!;

    switch (prompt.type) {
      case PromptType.yesNo:
        return QuickActionBar(
          options: prompt.options.isNotEmpty
              ? prompt.options
              : ['yes', 'no', 'always'],
          onSelect: widget.onAction,
        );
      case PromptType.choice:
        return QuickActionBar(
          options: prompt.options,
          onSelect: widget.onAction,
        );
      default:
        return _buildTextInput();
    }
  }

  Widget _buildMenuUI() {
    return Column(
      children: [
        if (widget.activeMenu!.title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              widget.activeMenu!.title!,
              style: const TextStyle(
                color: TerminalTheme.foreground,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        VirtualDpad(onKey: widget.onKey),
      ],
    );
  }

  Widget _buildDefaultUI() {
    return Column(
      children: [
        if (_showDpad) ...[
          VirtualDpad(onKey: widget.onKey),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            IconButton(
              icon: Icon(
                _showDpad ? Icons.keyboard : Icons.gamepad,
                color: TerminalTheme.foreground,
              ),
              onPressed: () {
                setState(() {
                  _showDpad = !_showDpad;
                });
              },
              tooltip: _showDpad ? 'Show keyboard' : 'Show D-pad',
            ),
            Expanded(child: _buildTextInput()),
          ],
        ),
      ],
    );
  }

  Widget _buildTextInput() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            style: const TextStyle(
              color: TerminalTheme.foreground,
              fontFamily: 'monospace',
            ),
            decoration: const InputDecoration(
              hintText: 'Enter command...',
              hintStyle: TextStyle(color: TerminalTheme.foregroundDim),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onSubmitted: (text) {
              if (text.isNotEmpty) {
                widget.onInput(text);
                _controller.clear();
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.send, color: TerminalTheme.primary),
          onPressed: () {
            if (_controller.text.isNotEmpty) {
              widget.onInput(_controller.text);
              _controller.clear();
            }
          },
        ),
      ],
    );
  }
}

/// Quick action buttons for Yes/No/etc prompts
class QuickActionBar extends StatelessWidget {
  final List<String> options;
  final Function(String) onSelect;

  const QuickActionBar({
    super.key,
    required this.options,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: options.map((option) {
        return ElevatedButton(
          onPressed: () => onSelect(option),
          style: ElevatedButton.styleFrom(
            backgroundColor: _colorForOption(option),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: Text(_labelForOption(option)),
        );
      }).toList(),
    );
  }

  String _labelForOption(String option) {
    switch (option.toLowerCase()) {
      case 'yes':
      case 'y':
        return 'Yes';
      case 'no':
      case 'n':
        return 'No';
      case 'always':
      case 'a':
        return 'Always';
      case 'never':
        return 'Never';
      case 'submit':
        return 'Submit';
      case 'cancel':
        return 'Cancel';
      default:
        return option;
    }
  }

  Color _colorForOption(String option) {
    switch (option.toLowerCase()) {
      case 'yes':
      case 'y':
      case 'always':
      case 'a':
      case 'submit':
        return TerminalTheme.green;
      case 'no':
      case 'n':
      case 'never':
      case 'cancel':
        return TerminalTheme.red;
      default:
        return TerminalTheme.primary;
    }
  }
}

/// Virtual D-pad for menu navigation
class VirtualDpad extends StatelessWidget {
  final Function(String) onKey;

  const VirtualDpad({super.key, required this.onKey});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Arrow keys
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildKey(Icons.arrow_upward, 'up'),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildKey(Icons.arrow_back, 'left'),
                const SizedBox(width: 48),
                _buildKey(Icons.arrow_forward, 'right'),
              ],
            ),
            _buildKey(Icons.arrow_downward, 'down'),
          ],
        ),
        const SizedBox(width: 32),
        // Action keys
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () => onKey('space'),
              style: ElevatedButton.styleFrom(
                backgroundColor: TerminalTheme.surfaceLight,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Space'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => onKey('enter'),
              style: ElevatedButton.styleFrom(
                backgroundColor: TerminalTheme.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Enter'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKey(IconData icon, String key) {
    return IconButton(
      icon: Icon(icon, color: TerminalTheme.foreground),
      onPressed: () => onKey(key),
      style: IconButton.styleFrom(
        backgroundColor: TerminalTheme.surfaceLight,
      ),
    );
  }
}
