# PlexusOne Nexus

A multi-agent orchestration platform for AI CLI tools like Claude Code and Kiro CLI.

## Repository Structure

```
nexus/
├── apps/
│   ├── desktop/          # macOS app (Swift + SwiftTerm)
│   └── mobile/           # iOS/Android companion (Flutter)
├── services/
│   └── tuiparser/        # WebSocket bridge for mobile streaming (Go)
└── docs/
    └── design/           # PRDs and design documents
```

## Components

### Desktop App (macOS)

Native macOS terminal multiplexer built with Swift and SwiftTerm.

- Multi-window, multi-pane grid layout (like Chrome tabs)
- Attach/detach to tmux sessions
- Session state persistence
- 10,000 line scrollback buffer

**Build & Run:**
```bash
cd apps/desktop
swift build
./Nexus.app/Contents/MacOS/Nexus
```

### Mobile App (iOS/Android)

Flutter companion app for monitoring and interacting with agents remotely.

- Terminal-styled output view
- Session tabs
- Quick action buttons (Yes/No/Always)
- Virtual D-pad for menu navigation
- WebSocket connection to TUI Parser

**Build & Run:**
```bash
cd apps/mobile
flutter pub get
flutter run
```

### TUI Parser (WebSocket Bridge)

Go service that bridges tmux sessions to mobile clients over WebSocket.

- Attaches to tmux sessions via PTY
- Streams terminal output
- Accepts input/keystrokes from mobile
- Pattern detection for TUI prompts (planned)

**Build & Run:**
```bash
cd services/tuiparser
go build -o bin/tuiparser ./cmd/tuiparser
./bin/tuiparser --port 9600
```

Debug console: http://localhost:9600

## Architecture

```
┌───────────────────────────────────────────────────┐
│  macOS                                            │
│                                                   │
│  ┌─────────────┐     ┌─────────────────────────┐  │
│  │ tmux        │     │ TUI Parser (Go)         │  │
│  │ sessions    │◄───►│ WebSocket server :9600  │  │
│  └─────────────┘     └───────────┬─────────────┘  │
│         ▲                        │                │
│         │                        │                │
│  ┌──────┴──────┐                 │                │
│  │ Nexus       │                 │                │
│  │ Desktop App │                 │                │
│  └─────────────┘                 │                │
└──────────────────────────────────┼────────────────┘
                                   │ WebSocket (LAN)
                          ┌────────▼────────┐
                          │  Nexus Mobile   │
                          │  (Flutter)      │
                          └─────────────────┘
```

## Documentation

- [Changelog](CHANGELOG.md)
- [Product Requirements](docs/design/prd.md)
- [Technical Requirements](docs/design/trd.md)
- [Mobile App PRD](docs/design/FEAT_MOBILE_PRD.md)
- [AgentPair Integration](docs/design/FEAT_AGENTPAIR_DESIGN.md)
- [AgentSentinel Integration](docs/design/FEAT_SENTINEL_PRD.md)
- [Voice Note Feature](docs/design/FEAT_VOICENOTE_PRD.md)

## Development

### Prerequisites

- macOS 13+
- Xcode 15+ (for Swift development)
- Go 1.22+
- Flutter 3.x
- tmux

### Quick Start

1. Start tmux sessions:
   ```bash
   tmux new-session -d -s agent1
   tmux new-session -d -s agent2
   ```

2. Run TUI Parser:
   ```bash
   cd services/tuiparser && ./bin/tuiparser
   ```

3. Run Desktop App:
   ```bash
   cd apps/desktop && open Nexus.app
   ```

4. Run Mobile App (same WiFi network):
   ```bash
   cd apps/mobile && flutter run
   ```

## License

Proprietary - PlexusOne
