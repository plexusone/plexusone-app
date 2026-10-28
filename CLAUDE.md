# CLAUDE.md

Project context for Claude Code sessions.

## Project Overview

**PlexusOne Apps** is a multi-agent orchestration platform for AI CLI tools (Claude Code, Kiro CLI, etc.). It provides a unified interface to monitor and control multiple AI agents running in tmux sessions.

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Xcode | 15+ | Provides Swift 5.9+ toolchain |
| macOS | 14+ (Sonoma) | Required by desktop app |
| Flutter | 3.x | Dart SDK >=2.18.6 included |
| Go | 1.22+ | For tuiparser service |
| tmux | 3.x | Session management backend |

Install via Homebrew:

```bash
brew install go tmux
# Flutter: https://docs.flutter.dev/get-started/install/macos
# Xcode: App Store or https://developer.apple.com/xcode/
```

## Repository Structure

```
plexusone-app/
├── apps/
│   ├── desktop/              # PlexusOne Desktop (macOS) - Swift/SwiftUI
│   │   ├── Sources/PlexusOneDesktop/
│   │   │   ├── App/          # App entry point, AppDelegate
│   │   │   ├── Models/       # Data models (Session, WindowState)
│   │   │   ├── Services/     # Business logic (SessionManager, AppState)
│   │   │   └── Views/        # SwiftUI views
│   │   └── Tests/PlexusOneDesktopTests/
│   ├── flutter/              # PlexusOne Mobile (Flutter) - Cross-platform
│   │   ├── lib/              # Dart source code
│   │   ├── ios/              # iOS-specific config
│   │   ├── android/          # Android-specific config
│   │   └── test/             # Unit tests
│   └── ios/                  # PlexusOne Mobile (Native iOS) - Swift/SwiftTerm
│       ├── Sources/PlexusOneiOS/
│       │   ├── App/          # App entry point
│       │   ├── Models/       # Data models
│       │   ├── Services/     # WebSocket client
│       │   └── Views/        # SwiftUI views
│       └── PlexusOneiOS.xcodeproj/
├── services/
│   └── tuiparser/            # WebSocket bridge for mobile (Go)
│       ├── cmd/tuiparser/    # Entry point
│       ├── internal/         # Server, session management
│       └── pkg/              # Protocol definitions
├── docs/                     # MkDocs documentation site
│   ├── guides/               # User and developer guides
│   │   ├── getting-started/  # Installation and quick start
│   │   ├── desktop/          # Desktop app user guide
│   │   ├── mobile/           # Mobile app user guide
│   │   ├── reference/        # Configuration and protocol reference
│   │   └── development/      # Building each app, contributing
│   ├── design/               # How it is built
│   │   ├── architecture/     # Architecture overview
│   │   └── adrs/             # Architecture decision records
│   ├── specs/                # PRD, TRD, feature specs, initiative roadmaps
│   ├── images/               # Screenshots and images
│   └── releases/             # Release notes and changelog
└── CHANGELOG.json            # Structured changelog (use schangelog to generate CHANGELOG.md)
```

## Components

### PlexusOne Desktop (macOS)

Native terminal multiplexer built with Swift and SwiftTerm.

**Key Features:**
- Multi-window support with independent grid layouts
- Pop-out sessions to dedicated windows
- Attach/detach tmux sessions
- 10,000 line scrollback buffer
- State persistence across restarts

**Build & Run:**
```bash
cd apps/desktop
swift build
.build/debug/PlexusOneDesktop
```

**Run Tests:**
```bash
cd apps/desktop
swift test
```

### PlexusOne Mobile - Flutter

Cross-platform companion app for remote monitoring via WebSocket.

**Build & Run:**
```bash
cd apps/flutter
flutter pub get
flutter run -d "iPhone 16 Pro"  # iOS Simulator
flutter run -d chrome           # Web
flutter run -d macos            # macOS
```

### PlexusOne Mobile - Native iOS

Native iOS/iPadOS app using SwiftTerm (same terminal library as Desktop).

**Build & Run:**
```bash
cd apps/ios
xcodebuild -project PlexusOneiOS.xcodeproj \
  -scheme PlexusOneiOS \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build

# Install and launch
xcrun simctl install "iPhone 16 Pro" \
  ~/Library/Developer/Xcode/DerivedData/PlexusOneiOS-*/Build/Products/Debug-iphonesimulator/PlexusOneiOS.app
xcrun simctl launch "iPhone 16 Pro" com.plexusone.ios
```

### TUI Parser (Go)

WebSocket bridge that streams tmux output to mobile clients.

**Build & Run:**
```bash
cd services/tuiparser
go build -o bin/tuiparser ./cmd/tuiparser
./bin/tuiparser --port 9600
```

## Key Technologies

| Component | Stack |
|-----------|-------|
| Desktop | Swift 5.9+, SwiftUI, SwiftTerm, AppKit |
| Mobile (Flutter) | Flutter 3.x, Dart, xterm package |
| Mobile (iOS) | Swift 5.9+, SwiftUI, SwiftTerm |
| TUI Parser | Go 1.22+, gorilla/websocket |
| Sessions | tmux |
| Docs | MkDocs Material |

## Development Conventions

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/).

**Valid scopes:**

| Scope | Description |
|-------|-------------|
| `desktop` | PlexusOne Desktop (Swift/macOS) |
| `flutter` | PlexusOne Mobile - Flutter app |
| `ios` | PlexusOne Mobile - Native iOS app |
| `tuiparser` | TUI Parser service (Go) |
| `docs` | Documentation site |
| (none) | Cross-cutting changes |

**Examples:**

```
feat(desktop): add multi-window support
fix(flutter): handle WebSocket reconnection
feat(ios): add SwiftTerm terminal view
docs: update architecture diagram
refactor(tuiparser): extract session manager
```

### Changelog

Use structured changelog workflow:
```bash
# Update CHANGELOG.json with new entries
# Then regenerate:
schangelog generate CHANGELOG.json -o CHANGELOG.md
cp CHANGELOG.md docs/releases/changelog.md
```

### State Files

Desktop app state is stored in:
```
~/.plexusone/state.json
```

### Local Checks (Pre-Push)

Run these checks before pushing:

```bash
# Desktop (Swift)
cd apps/desktop && swift build && swift test

# Mobile - Flutter
cd apps/flutter && flutter analyze && flutter test

# Mobile - Native iOS
cd apps/ios && xcodebuild -scheme PlexusOneiOS -sdk iphonesimulator build

# TUI Parser (Go)
cd services/tuiparser && go build ./... && go test ./...
```

**Note:** CI workflows are not yet configured. Run checks locally before pushing.

### Environment Variables

| Variable | Component | Description |
|----------|-----------|-------------|
| `SHELL` | Desktop | Shell for new tmux sessions (default: `/bin/zsh`) |
| `TERM` | Desktop | Set to `xterm-256color` for terminal compatibility |
| `LANG` | Desktop | Locale; set to `en_US.UTF-8` if unset |

The tuiparser service has no required environment variables.

### Linting

| Component | Tool | Command |
|-----------|------|---------|
| Desktop | (none configured) | `swift build` catches errors |
| Flutter | flutter_lints | `flutter analyze` |
| iOS | (none configured) | `xcodebuild` catches errors |
| TUI Parser | golangci-lint | `golangci-lint run` |

## Architecture Notes

### Desktop App Architecture

```
AppState (Singleton)
├── SessionManager       # Shared across all windows
└── WindowStateManager   # Tracks all window configs

Window A                 Window B
├── PaneManager (local)  ├── PaneManager (local)
└── GridConfig (local)   └── GridConfig (local)
```

- **SessionManager** is shared - sessions sync across windows
- **PaneManager** and **GridConfig** are per-window
- Windows communicate via NotificationCenter

### Key Files

| Purpose | Location |
|---------|----------|
| App entry | `apps/desktop/Sources/PlexusOneDesktop/App/PlexusOneDesktopApp.swift` |
| Shared state | `apps/desktop/Sources/PlexusOneDesktop/Services/AppState.swift` |
| Session logic | `apps/desktop/Sources/PlexusOneDesktop/Services/SessionManager.swift` |
| Window persistence | `apps/desktop/Sources/PlexusOneDesktop/Services/WindowStateManager.swift` |
| Terminal view | `apps/desktop/Sources/PlexusOneDesktop/Views/AppTerminalView.swift` |
| Main content | `apps/desktop/Sources/PlexusOneDesktop/Views/ContentView.swift` |

## Common Tasks

### Add a new feature to Desktop

1. Create/modify models in `Models/`
2. Add business logic in `Services/`
3. Create UI in `Views/`
4. Add tests in `Tests/PlexusOneDesktopTests/`
5. Update docs in `docs/guides/desktop/`

### Prepare a release

1. Update `CHANGELOG.json` with new version
2. Run `schangelog generate CHANGELOG.json -o CHANGELOG.md`
3. Copy to docs: `cp CHANGELOG.md docs/releases/changelog.md`
4. Create `docs/releases/vX.Y.Z.md`
5. Update `Info.plist` version
6. Update `mkdocs.yml` navigation
7. Commit, push, wait for CI, then tag

### Debug the Desktop app

```bash
cd apps/desktop
swift build
# Run directly to see console output:
.build/debug/PlexusOneDesktop
```

## Links

- [MkDocs Site](https://plexusone.github.io/plexusone-app/)
- [GitHub Repo](https://github.com/plexusone/plexusone-app)
