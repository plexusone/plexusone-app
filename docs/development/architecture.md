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
├── AppDelegate              # App lifecycle, menu bar, new window handling
├── AppState (Singleton)     # Shared state across windows
│   ├── SessionManager       # tmux session management (shared)
│   └── WindowStateManager   # Multi-window persistence
├── ContentView              # Per-window layout
│   ├── PaneManager          # Per-window pane-to-session mappings
│   └── GridConfig           # Per-window grid layout
├── GridLayoutView           # Pane grid rendering
├── TerminalPaneView         # Individual terminal pane
│   └── SwiftTermView        # SwiftTerm wrapper
└── Models
    ├── WindowState          # Window configuration models
    └── NexusState           # Legacy v1 state (migration)
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

Saved to `~/.plexusone/nexus_state.json` (v2 multi-window format):

```json
{
  "windows": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "gridColumns": 3,
      "gridRows": 2,
      "paneAttachments": {"1": "claude-main", "2": "reviewer"},
      "frame": {"x": 100, "y": 100, "width": 1200, "height": 800}
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "gridColumns": 2,
      "gridRows": 1,
      "paneAttachments": {"1": "tests"}
    }
  ],
  "savedAt": "2024-03-28T12:00:00Z",
  "version": 2
}
```

**Lifecycle:**

1. On launch, check for state file
2. If exists (v1 or v2), migrate to v2 if needed
3. Prompt user to restore windows
4. On window change, save state immediately
5. On window close, unregister and save

**Multi-Window State:**

- Each window has a unique UUID
- Windows track their own grid config and pane attachments
- SessionManager is shared across all windows (singleton)
- Closing one window doesn't affect others

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
