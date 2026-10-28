# PlexusOne App

[![Swift CI][swift-ci-svg]][swift-ci-url]
[![License][license-svg]][license-url]

 [swift-ci-svg]: https://github.com/plexusone/plexusone-app/actions/workflows/desktop.yaml/badge.svg?branch=main
 [swift-ci-url]: https://github.com/plexusone/plexusone-app/actions/workflows/desktop.yaml
 [license-svg]: https://img.shields.io/badge/license-MIT-blue.svg
 [license-url]: https://github.com/plexusone/plexusone-app/blob/main/LICENSE

A multi-agent orchestration platform for AI CLI tools like Claude Code and Kiro CLI.

[![PlexusOne App Hero](docs/images/ss_plexusone-app_hero_v2.jpeg)](https://plexusone.dev/plexusone-app/)

[![PlexusOne App Screenshot](docs/images/ss_plexusone-desktop_claude-code-12x.png)](https://plexusone.dev/plexusone-app/)

## Repository Structure

```
plexusone-app/
├── apps/
│   ├── desktop/          # macOS app (Swift + SwiftTerm)
│   ├── flutter/          # iOS/Android/web/macOS companion (Flutter)
│   └── ios/              # Native iOS/iPadOS companion (Swift + SwiftTerm)
├── services/
│   └── tuiparser/        # WebSocket bridge for mobile streaming (Go)
└── docs/
    ├── guides/           # User and developer guides
    ├── design/           # Architecture and decision records
    ├── specs/            # PRD, TRD, feature specs, roadmaps
    └── releases/         # Release notes and changelog
```

## Components

### PlexusOne Desktop (macOS)

Native macOS terminal multiplexer built with Swift and SwiftTerm.

- Multi-window, multi-pane grid layout
- Attach/detach to tmux sessions
- Pop-out sessions to dedicated windows
- **Input detection** for AI assistant prompts (Claude, Kiro, etc.)
- **PTY wrapper detection** - warns if a session is running behind a shell-autocomplete PTY shim (Kiro CLI, Fig, Amazon Q) known to freeze terminal panes
- **Claude Sessions window** (`⇧⌘S`) - lists Claude Code sessions with their tmux session, subject, repositories, last activity, and whether each ended normally or in a crash, restart, or closed terminal; resumes the ones you pick into tmux sessions you name
- Trackpad scrolls tmux history (tmux mouse mode per attached session; hold Shift to drag-select)
- Keyboard pane navigation (`⌘]` / `⌘[`), attach (`⌥⌘A`), and detach (`⇧⌘A`)
- Visual focus indicator for active pane
- Session state persistence

**Download:** [Releases](https://github.com/plexusone/plexusone-app/releases)

**Install:** Open the `.dmg` and drag PlexusOne Desktop to Applications. Release builds are ad-hoc signed but not notarized, so on first launch macOS shows "Apple could not verify ... free of malware". Open **System Settings → Privacy & Security**, scroll to the message about PlexusOne Desktop, and click **Open Anyway**; the prompt does not recur. (Alternatively, from Terminal: `xattr -dr com.apple.quarantine "/Applications/PlexusOne Desktop.app"`.)

**Build & Run:**
```bash
cd apps/desktop
swift build
open "PlexusOne Desktop.app"
```

### PlexusOne Mobile - Flutter (iOS/Android/Web/macOS)

Cross-platform companion app for monitoring and interacting with agents remotely.

- Terminal-styled output view
- Session tabs
- Quick action buttons (Yes/No/Always)
- Virtual D-pad for menu navigation
- WebSocket connection to TUI Parser

**Build & Run:**
```bash
cd apps/flutter
flutter pub get
flutter run
```

### PlexusOne Mobile - Native iOS

Native iOS/iPadOS companion app using SwiftTerm (same terminal library as Desktop).

**Build & Run:**
```bash
cd apps/ios
xcodebuild -project PlexusOneiOS.xcodeproj \
  -scheme PlexusOneiOS \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build
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
│  │ PlexusOne   │                 │                │
│  │ Desktop     │                 │                │
│  └─────────────┘                 │                │
└──────────────────────────────────┼────────────────┘
                                   │ WebSocket (LAN)
                         ┌─────────▼────────┐
                         │ PlexusOne Mobile │
                         │ (Flutter or iOS) │
                         └──────────────────┘
```

## Related Projects

Other tools for running several coding agents side by side:

| Project | Built with | Focus |
|---------|------------|-------|
| [cmux](https://github.com/manaflow-ai/cmux) | Swift, Ghostty-based macOS terminal | Vertical tabs and notifications for AI coding agents |
| [Agent Deck](https://github.com/asheshgoplani/agent-deck) | Go, terminal UI | One session manager for Claude, Gemini, OpenCode, Codex, and others |
| [workmux](https://github.com/raine/workmux) | Rust, tmux | Git worktrees paired with tmux windows for parallel development |
| [herdr](https://github.com/herdrdev/herdr) | Rust | A background server keeps agent terminals running; after a restart it restores the layout and resumes supported agent sessions |
| [Agent of Empires](https://github.com/agent-of-empires/agent-of-empires) | Rust, terminal and web UI | Managing several agents from a terminal UI or a browser, including on mobile |
| [dmux](https://github.com/standardagents/dmux) | tmux | Git worktrees and parallel agent tasks |

PlexusOne keeps your existing tmux sessions as the backend: a native macOS
grid of SwiftTerm panes, a mobile companion over WebSocket, and a Claude
Sessions window that finds and restores sessions lost to a crash or restart.

## Documentation

- [Changelog](CHANGELOG.md)
- [Product Requirements](docs/specs/PRD.md)
- [Technical Requirements](docs/specs/TRD.md)
- [Mobile App PRD](docs/specs/features/FEAT_MOBILE_PRD.md)
- [AgentPair Integration](docs/specs/features/FEAT_AGENTPAIR_DESIGN.md)
- [AgentSentinel Integration](docs/specs/features/FEAT_SENTINEL_PRD.md)
- [Voice Note Feature](docs/specs/features/FEAT_VOICENOTE_PRD.md)

## Development

### Prerequisites

- macOS 14+
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
   cd apps/desktop && open "PlexusOne Desktop.app"
   ```

4. Run Mobile App (same WiFi network):
   ```bash
   cd apps/flutter && flutter run
   ```

## License

MIT - See [LICENSE](LICENSE)
