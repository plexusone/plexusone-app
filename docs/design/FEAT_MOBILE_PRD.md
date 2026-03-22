# PlexusOne Nexus Mobile Companion App

## Overview

A Flutter-based mobile companion app that connects to the macOS Nexus orchestrator, allowing users to monitor and interact with AI CLI agents (Claude Code, Kiro CLI) from iOS and Android devices.

## Goals

1. **Monitor** - View real-time output from multiple AI agent sessions
2. **Interact** - Respond to TUI prompts, approval requests, and wizards
3. **Control** - Start/stop sessions, switch between agents, send commands
4. **Mobility** - Work away from desk while agents run tasks

## Non-Goals (Phase 1)

- Full terminal emulation (no xterm.dart)
- Voice input (future feature via omnivoice)
- Cloud relay (LAN-first approach)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  macOS (Nexus Orchestrator)                                     │
│                                                                 │
│  ┌─────────────┐     ┌─────────────────────────────────────┐   │
│  │ tmux        │     │ TUI Parser Wrapper (Go)             │   │
│  │ sessions    │────▶│ - PTY intercept                     │   │
│  │             │◀────│ - ANSI parsing                      │   │
│  │ - coder-1   │     │ - Pattern detection                 │   │
│  │ - coder-2   │     │ - Structured event emission         │   │
│  │ - reviewer  │     │ - Keystroke injection               │   │
│  └─────────────┘     └──────────────┬──────────────────────┘   │
│                                     │                           │
│  ┌─────────────────────────────────┐│                           │
│  │ Nexus Swift App                 ││                           │
│  │ - Session management            │◀───── Local IPC            │
│  │ - SwiftTerm panes               ││                           │
│  │ - State persistence             ││                           │
│  └─────────────────────────────────┘│                           │
│                                     │                           │
│  ┌──────────────────────────────────▼──────────────────────┐   │
│  │ WebSocket Server (Go or embedded in wrapper)            │   │
│  │ - Port 9600 (default)                                   │   │
│  │ - JSON protocol                                         │   │
│  │ - Session multiplexing                                  │   │
│  └──────────────────────────────────┬──────────────────────┘   │
└─────────────────────────────────────┼───────────────────────────┘
                                      │ WebSocket (LAN)
                                      │
┌─────────────────────────────────────▼───────────────────────────┐
│  Mobile App (Flutter)                                           │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Session Tabs                                             │   │
│  │ [coder-1 ●] [coder-2 ○] [reviewer ●]                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Terminal-Style Output View                               │   │
│  │ - Monospace font, dark theme                            │   │
│  │ - Scrollable log                                        │   │
│  │ - Tap to copy                                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Interactive Prompt Area (context-aware)                  │   │
│  │ - Quick action buttons (Yes/No/Always)                  │   │
│  │ - Virtual D-pad for menu navigation                     │   │
│  │ - Native checkboxes for multi-select                    │   │
│  │ - Text input field                                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Status Bar                                               │   │
│  │ - Connection status                                     │   │
│  │ - Agent status (running/idle/stuck)                     │   │
│  │ - Token usage (if available)                            │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## WebSocket Protocol

### Connection

```
ws://<laptop-ip>:9600/ws
```

### Message Format

All messages are JSON with a `type` field:

```json
{
  "type": "<message_type>",
  "sessionId": "<tmux_session_name>",
  "timestamp": 1710945600,
  ...
}
```

### Server → Client Messages

#### `sessions` - Session list update
```json
{
  "type": "sessions",
  "sessions": [
    {
      "id": "coder-1",
      "name": "coder-1",
      "status": "running",
      "lastActivity": 1710945600
    }
  ]
}
```

#### `output` - Terminal output chunk
```json
{
  "type": "output",
  "sessionId": "coder-1",
  "text": "Building project...\n",
  "timestamp": 1710945600
}
```

#### `prompt` - Interactive prompt detected
```json
{
  "type": "prompt",
  "sessionId": "coder-1",
  "promptType": "yes_no",
  "title": "Tool Approval",
  "message": "Allow Read tool on config.json?",
  "options": ["yes", "no", "always", "never"],
  "defaultOption": "yes",
  "timestamp": 1710945600
}
```

#### `menu` - Scrollable menu detected
```json
{
  "type": "menu",
  "sessionId": "coder-1",
  "title": "Select tools to approve",
  "items": [
    {"label": "Read: config.json", "selected": false, "index": 0},
    {"label": "Write: output.txt", "selected": true, "index": 1},
    {"label": "Bash: npm install", "selected": false, "index": 2}
  ],
  "currentIndex": 1,
  "multiSelect": true,
  "timestamp": 1710945600
}
```

#### `wizard` - Multi-step wizard detected
```json
{
  "type": "wizard",
  "sessionId": "coder-1",
  "title": "Configure task",
  "currentStep": 2,
  "totalSteps": 4,
  "fields": [
    {"name": "approach", "type": "select", "options": ["Option A", "Option B"]},
    {"name": "confirm", "type": "checkbox", "label": "I understand the changes"}
  ],
  "actions": ["back", "next", "submit"],
  "timestamp": 1710945600
}
```

#### `status` - Session status change
```json
{
  "type": "status",
  "sessionId": "coder-1",
  "status": "idle",
  "tokenUsage": {
    "input": 15000,
    "output": 3200
  },
  "timestamp": 1710945600
}
```

#### `clear` - Clear terminal buffer
```json
{
  "type": "clear",
  "sessionId": "coder-1"
}
```

### Client → Server Messages

#### `subscribe` - Subscribe to session(s)
```json
{
  "type": "subscribe",
  "sessionIds": ["coder-1", "coder-2"]
}
```

#### `unsubscribe` - Unsubscribe from session(s)
```json
{
  "type": "unsubscribe",
  "sessionIds": ["coder-1"]
}
```

#### `input` - Send text input
```json
{
  "type": "input",
  "sessionId": "coder-1",
  "text": "hello world"
}
```

#### `key` - Send special key
```json
{
  "type": "key",
  "sessionId": "coder-1",
  "key": "enter"
}
```

Valid keys: `enter`, `tab`, `escape`, `up`, `down`, `left`, `right`, `space`, `backspace`, `y`, `n`, `a`

#### `action` - Respond to prompt/menu/wizard
```json
{
  "type": "action",
  "sessionId": "coder-1",
  "action": "select",
  "value": "yes"
}
```

---

## TUI Parser Wrapper

### Overview

A Go binary that wraps tmux sessions, intercepts PTY output, detects TUI patterns, and emits structured events while also forwarding raw output.

### Location

```
github.com/plexusone/nexus/tuiparser/
├── cmd/
│   └── tuiparser/
│       └── main.go
├── internal/
│   ├── parser/
│   │   ├── parser.go       # Main parsing logic
│   │   ├── patterns.go     # Pattern definitions
│   │   └── ansi.go         # ANSI sequence handling
│   ├── pty/
│   │   └── pty.go          # PTY management
│   ├── server/
│   │   └── websocket.go    # WebSocket server
│   └── session/
│       └── manager.go      # Session management
├── pkg/
│   └── protocol/
│       └── messages.go     # Message types
└── go.mod
```

### Pattern Detection

#### Yes/No Prompts
```
Patterns:
- "(y/n)" or "[Y/n]" or "[y/N]"
- "? (yes/no)"
- "Allow ... ?"
- "Approve ... ?"

Action: Emit `prompt` message with type `yes_no`
```

#### Multi-Select Menus (Claude Code style)
```
Patterns:
- Lines with "[ ]" or "[x]" or "◯" or "●"
- Highlighted/inverse video line (current selection)
- "Press space to toggle, enter to confirm"

Action: Emit `menu` message with items and selection state
```

#### Kiro CLI Tool Approval
```
Patterns:
- "Tool requests:" header
- Numbered list of tools
- "Enter numbers to approve" or similar

Action: Emit `menu` message with multiSelect: true
```

#### Wizard/Questionnaire (Claude Code AskUserQuestion)
```
Patterns:
- Step indicators "Step 1 of 3" or "[1/3]"
- Multiple choice options with radio buttons
- "Submit" or "Continue" at bottom

Action: Emit `wizard` message with fields and actions
```

#### Input Waiting
```
Patterns:
- Cursor at end of line with no recent output
- ">" or "$" or ":" prompt character
- Blinking cursor (timing-based detection)

Action: Emit `prompt` message with type `input`
```

### ANSI Handling

The parser should:
1. Strip ANSI codes for clean text extraction
2. Detect cursor position for menu navigation
3. Identify inverse/highlight for current selection
4. Track screen state for multi-line TUI elements

### Integration with Nexus

The TUI Parser runs as a daemon alongside Nexus:

```bash
# Started by Nexus app or launchd
tuiparser --port 9600 --tmux-socket /tmp/tmux-501/default
```

Nexus Swift app can:
1. Launch tuiparser on startup
2. Query session list via WebSocket
3. Let mobile app connect directly to tuiparser

---

## Flutter Mobile App

### Project Structure

```
nexus_mobile/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── models/
│   │   ├── session.dart
│   │   ├── message.dart
│   │   └── prompt.dart
│   ├── services/
│   │   ├── websocket_service.dart
│   │   ├── connection_service.dart
│   │   └── notification_service.dart
│   ├── screens/
│   │   ├── home_screen.dart
│   │   ├── session_screen.dart
│   │   └── settings_screen.dart
│   ├── widgets/
│   │   ├── terminal_view.dart
│   │   ├── session_tabs.dart
│   │   ├── prompt_bar.dart
│   │   ├── quick_actions.dart
│   │   ├── menu_selector.dart
│   │   ├── virtual_dpad.dart
│   │   └── status_indicator.dart
│   └── theme/
│       └── terminal_theme.dart
├── pubspec.yaml
└── README.md
```

### Key Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  web_socket_channel: ^2.4.0
  provider: ^6.1.0
  shared_preferences: ^2.2.0
  flutter_riverpod: ^2.4.0  # Alternative to provider
```

### Terminal-Style View

A custom widget that renders output in a terminal aesthetic:

```dart
class TerminalView extends StatelessWidget {
  final List<OutputLine> lines;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: TerminalTheme.background,
      child: ListView.builder(
        controller: scrollController,
        itemCount: lines.length,
        itemBuilder: (context, index) {
          return TerminalLine(line: lines[index]);
        },
      ),
    );
  }
}

class TerminalLine extends StatelessWidget {
  final OutputLine line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: SelectableText(
        line.text,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',  // or 'Menlo', 'Courier'
          fontSize: 12,
          color: _colorForStyle(line.style),
        ),
      ),
    );
  }

  Color _colorForStyle(LineStyle style) {
    switch (style) {
      case LineStyle.error: return TerminalTheme.red;
      case LineStyle.success: return TerminalTheme.green;
      case LineStyle.info: return TerminalTheme.blue;
      default: return TerminalTheme.foreground;
    }
  }
}
```

### Interactive Prompt Bar

Context-aware input area that changes based on detected prompts:

```dart
class PromptBar extends StatelessWidget {
  final Prompt? activePrompt;
  final Function(String) onAction;
  final Function(String) onInput;

  @override
  Widget build(BuildContext context) {
    if (activePrompt == null) {
      return TextInputBar(onSubmit: onInput);
    }

    switch (activePrompt!.type) {
      case PromptType.yesNo:
        return QuickActionBar(
          options: activePrompt!.options,
          onSelect: onAction,
        );
      case PromptType.menu:
        return MenuSelector(
          items: activePrompt!.items,
          multiSelect: activePrompt!.multiSelect,
          onConfirm: onAction,
        );
      case PromptType.navigation:
        return VirtualDpad(onKey: onAction);
      default:
        return TextInputBar(onSubmit: onInput);
    }
  }
}
```

### Quick Action Buttons

```dart
class QuickActionBar extends StatelessWidget {
  final List<String> options;
  final Function(String) onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: options.map((option) {
        return ElevatedButton(
          onPressed: () => onSelect(option),
          style: _styleForOption(option),
          child: Text(_labelForOption(option)),
        );
      }).toList(),
    );
  }

  String _labelForOption(String option) {
    switch (option) {
      case 'yes': return 'Yes';
      case 'no': return 'No';
      case 'always': return 'Always';
      case 'never': return 'Never';
      default: return option;
    }
  }
}
```

### Virtual D-Pad

For navigating menus when native UI detection fails:

```dart
class VirtualDpad extends StatelessWidget {
  final Function(String) onKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Arrow keys
        Column(
          children: [
            IconButton(icon: Icon(Icons.arrow_upward), onPressed: () => onKey('up')),
            Row(
              children: [
                IconButton(icon: Icon(Icons.arrow_back), onPressed: () => onKey('left')),
                SizedBox(width: 40),
                IconButton(icon: Icon(Icons.arrow_forward), onPressed: () => onKey('right')),
              ],
            ),
            IconButton(icon: Icon(Icons.arrow_downward), onPressed: () => onKey('down')),
          ],
        ),
        SizedBox(width: 32),
        // Action keys
        Column(
          children: [
            ElevatedButton(onPressed: () => onKey('space'), child: Text('Space')),
            SizedBox(height: 8),
            ElevatedButton(onPressed: () => onKey('enter'), child: Text('Enter')),
          ],
        ),
      ],
    );
  }
}
```

---

## Implementation Phases

### Phase 1: Foundation (Week 1)

**TUI Parser (Go):**
- [ ] Basic PTY wrapper for tmux sessions
- [ ] WebSocket server with session multiplexing
- [ ] Raw output streaming (no pattern detection yet)
- [ ] Basic input/keystroke injection

**Flutter App:**
- [ ] Project setup with dependencies
- [ ] WebSocket connection service
- [ ] Terminal-style output view
- [ ] Session tabs
- [ ] Basic text input

### Phase 2: Pattern Detection (Week 2)

**TUI Parser:**
- [ ] ANSI sequence stripping/parsing
- [ ] Yes/No prompt detection
- [ ] Simple menu detection (checkbox patterns)
- [ ] Input waiting detection

**Flutter App:**
- [ ] Quick action buttons (Yes/No/Always)
- [ ] Virtual D-pad widget
- [ ] Context-aware prompt bar

### Phase 3: Advanced Patterns (Week 3)

**TUI Parser:**
- [ ] Claude Code wizard detection
- [ ] Kiro CLI multi-tool approval
- [ ] Screen state tracking for complex TUIs
- [ ] Status detection (running/idle/stuck)

**Flutter App:**
- [ ] Multi-select menu UI
- [ ] Wizard/stepper UI
- [ ] Status indicators
- [ ] Connection status and reconnection

### Phase 4: Polish (Week 4)

**Both:**
- [ ] Error handling and edge cases
- [ ] Performance optimization
- [ ] Settings (server address, theme)
- [ ] Notifications for prompt waiting
- [ ] Testing with Claude Code and Kiro CLI

---

## Future Enhancements

1. **Cloud Relay** - For remote access outside LAN
2. **Voice Input** - Integration with omnivoice daemon
3. **Multi-Device** - Multiple mobile devices connected
4. **Notifications** - Push notifications when agent needs input
5. **History** - Persistent log storage and search
6. **Themes** - Customizable terminal themes

---

## Security Considerations

1. **LAN-Only (Phase 1)** - No internet exposure
2. **Optional Auth** - Add token-based auth for shared networks
3. **TLS** - Use wss:// for encrypted WebSocket (optional)
4. **Input Sanitization** - Validate all client input before injection

---

## Open Questions

1. Should the TUI Parser be a standalone binary or embedded in Nexus Swift app via Go→Swift bridge?
2. How to handle multiple mobile devices connecting simultaneously?
3. Should we persist terminal output history on the server for mobile reconnection?
4. What's the fallback when pattern detection fails? (Default to virtual D-pad?)
