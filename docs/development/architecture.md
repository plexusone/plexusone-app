# Architecture

Technical architecture of the Nexus multi-agent orchestration platform.

## System Overview

```
┌────────────────────────────────────────────────────────────┐
│                      User Devices                          │
│  ┌──────────────┐              ┌──────────────┐           │
│  │   Desktop    │              │    Mobile    │           │
│  │   (macOS)    │              │  (iOS/Andr)  │           │
│  └──────┬───────┘              └──────┬───────┘           │
└─────────┼──────────────────────────────┼──────────────────┘
          │                              │
          │ SwiftTerm                    │ WebSocket
          │                              │
┌─────────┼──────────────────────────────┼──────────────────┐
│         │           Services           │                   │
│         │                              │                   │
│         ▼                              ▼                   │
│  ┌──────────────┐              ┌──────────────┐           │
│  │     tmux     │◄────PTY─────►│  TUI Parser  │           │
│  │   Sessions   │              │     (Go)     │           │
│  └──────┬───────┘              └──────────────┘           │
│         │                                                  │
│         ▼                                                  │
│  ┌──────────────┐                                         │
│  │   AI CLIs    │                                         │
│  │ Claude Code  │                                         │
│  │  Kiro CLI    │                                         │
│  └──────────────┘                                         │
└────────────────────────────────────────────────────────────┘
```

## Components

### Desktop App (Swift/SwiftUI)

**Location:** `apps/desktop/`

The macOS desktop application provides a native multi-pane terminal interface.

**Key Technologies:**

- SwiftUI for UI framework
- AppKit for window management
- SwiftTerm for terminal emulation
- SwiftUI-Introspect for AppKit bridging

**Architecture:**

```
NexusApp
├── AppDelegate           # App lifecycle, menu bar
├── ContentView           # Main window layout
├── GridLayoutManager     # Pane grid calculations
├── SessionManager        # tmux session management
├── TerminalPaneView      # Individual terminal pane
│   └── SwiftTermView     # SwiftTerm wrapper
└── StateManager          # Persistence
```

**Responsibilities:**

- Render multiple terminal panes in configurable grid
- Attach to tmux sessions via PTY
- Persist window state across restarts
- Provide keyboard shortcuts for navigation

### TUI Parser (Go)

**Location:** `services/tuiparser/`

A WebSocket bridge that connects mobile clients to tmux sessions.

**Key Technologies:**

- Go standard library
- gorilla/websocket for WebSocket handling
- PTY for tmux attachment

**Architecture:**

```
tuiparser/
├── cmd/tuiparser/main.go      # Entry point
├── internal/
│   ├── server/                # HTTP/WebSocket server
│   │   └── websocket.go
│   └── session/               # tmux session management
│       └── manager.go
└── pkg/protocol/              # Message types
    └── messages.go
```

**Responsibilities:**

- Discover and list tmux sessions
- Attach to sessions via PTY
- Stream terminal output to WebSocket clients
- Forward keystrokes from clients to sessions
- Detect TUI patterns (prompts, menus)

### Mobile App (Flutter)

**Location:** `apps/mobile/`

Cross-platform mobile application for remote session monitoring.

**Key Technologies:**

- Flutter/Dart
- web_socket_channel for WebSocket
- provider for state management

**Architecture:**

```
lib/
├── main.dart                  # Entry point
├── models/
│   └── session.dart           # Data models
├── services/
│   └── websocket_service.dart # WebSocket client
├── screens/
│   ├── home_screen.dart       # Main screen
│   └── settings_screen.dart   # Configuration
├── widgets/
│   ├── terminal_view.dart     # Terminal output
│   ├── prompt_bar.dart        # Input controls
│   └── session_tabs.dart      # Session switcher
└── theme/
    └── terminal_theme.dart    # Dark theme
```

**Responsibilities:**

- Connect to TUI Parser via WebSocket
- Display streaming terminal output
- Provide touch-friendly input controls
- Handle TUI menu navigation

## Data Flow

### Terminal Output Flow

```
1. AI CLI writes to stdout
2. tmux captures in session buffer
3. Desktop: SwiftTerm reads via PTY, renders directly
4. Mobile: TUI Parser reads via PTY, streams over WebSocket
5. Mobile app receives, parses ANSI, renders
```

### Input Flow (Mobile)

```
1. User taps key/button in mobile app
2. App sends keystroke message via WebSocket
3. TUI Parser receives, validates
4. TUI Parser writes to PTY
5. tmux delivers to attached session
6. AI CLI receives input
```

## Session Management

### tmux as Source of Truth

tmux is the central session manager:

- Sessions persist across app restarts
- Multiple clients can attach to same session
- Built-in scrollback buffer
- Established patterns for detach/reattach

### Session Discovery

Both desktop and TUI Parser discover sessions via:

```bash
tmux list-sessions -F "#{session_name}"
```

### Session Attachment

**Desktop (SwiftTerm):**

```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/tmux")
process.arguments = ["attach-session", "-t", sessionName]
```

**TUI Parser (Go):**

```go
cmd := exec.Command("tmux", "attach-session", "-t", sessionName)
pty, _ := pty.Start(cmd)
```

## State Persistence

### Desktop State

Saved to `~/.plexusone/nexus_state.json`:

```json
{
  "gridLayout": "2x2",
  "sessions": [
    {"paneIndex": 0, "sessionName": "claude-main"}
  ]
}
```

**Lifecycle:**

1. On launch, check for state file
2. If exists, prompt user to restore
3. On change, save state (debounced)
4. On quit, save final state

### Mobile State

Stored via Flutter's SharedPreferences:

- Server host/port
- Last connected sessions
- Display preferences

## Error Handling

### Desktop

- Failed tmux attach: Show error in pane, allow retry
- Lost session: Mark pane as disconnected, offer reconnect

### TUI Parser

- Client disconnect: Clean up subscriptions
- Session ended: Notify subscribed clients, remove from list

### Mobile

- Connection lost: Show status, auto-reconnect with backoff
- Session gone: Remove from list, notify user

## Security Model

### Current State

- No authentication
- Local network only
- Trust-based model

### Future Considerations

- Token-based authentication
- TLS encryption
- SSH tunnel support

## Performance

### Desktop

- SwiftTerm handles rendering efficiently
- Scrollback limited to 10,000 lines (configurable)
- Minimal CPU when idle

### TUI Parser

- One goroutine per PTY reader
- WebSocket broadcast to all subscribers
- Memory scales with active sessions

### Mobile

- Virtualized scrolling for large buffers
- ANSI parsing on receive
- Battery-conscious reconnection
