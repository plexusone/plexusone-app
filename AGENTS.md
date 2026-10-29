# AGENTS.md

Project context for coding agents (Claude Code, Codex, and others). `CLAUDE.md` imports this file.

## Project Overview

**PlexusOne Apps** is a multi-agent orchestration platform for AI CLI tools (Claude Code, Kiro CLI, etc.). It provides a unified interface to monitor and control multiple AI agents running in tmux sessions.

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Xcode | 16+ | Provides the Swift 6.0 toolchain SwiftTerm needs; CI builds with 16.2 |
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
- Claude Sessions window: lists Claude Code sessions with tmux name, Claude name, subject, repository, cost, and how each ended; restores and renames them
- Claude names and waiting badges in pane headers; notifications, Dock badge, and `⌘J` for sessions waiting on the user
- Optional Claude Code hook (`PlexusOneDesktop claude-hook`) that records sessions while the app is closed
- Only one instance runs at a time (a bare `.build/debug` executable is exempt)

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
| Desktop | Swift 6 toolchain (Swift 5 language mode), SwiftUI, SwiftTerm, AppKit |
| Mobile (Flutter) | Flutter 3.x, Dart, xterm package |
| Mobile (iOS) | Swift 6 toolchain, SwiftUI, SwiftTerm |
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

Desktop app files:

| File | Contents |
|------|----------|
| `~/.plexusone/state.json` | Window layouts and pane attachments |
| `~/.plexusone/claude-sessions.json` | Observed Claude sessions: tmux name, Claude name, end state |
| `~/.plexusone/claude-session-events.jsonl` | Events appended by the Claude Code hook |

The app also reads Claude Code's own files (`~/.claude/sessions/*.json` live
records and `~/.claude/projects/*/*.jsonl` transcripts) and, when the hook is
installed, writes its entries into `~/.claude/settings.json`.

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

CI: **Desktop CI** (`.github/workflows/desktop.yaml`) builds and tests the desktop app on pushes and pull requests that touch `apps/desktop/`, using the shared org Swift workflow (Xcode 16.2). **Desktop Release** (`desktop-release.yaml`) builds the DMGs on `v*` tags or a manual run. The other components have no CI yet; run their checks locally.

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
├── SessionManager        # Shared across all windows
├── WindowStateManager    # Tracks all window configs
└── ClaudeSessionCatalog  # Claude sessions, names, waiting state (polled every 5s)

Window A                 Window B
├── PaneManager (local)  ├── PaneManager (local)
└── GridConfig (local)   └── GridConfig (local)
```

- **SessionManager** is shared - sessions sync across windows
- **PaneManager** and **GridConfig** are per-window
- Menu commands reach the front window through a focused scene value (`WindowActions`); new windows open with SwiftUI's `openWindow`
- `ClaudeSessionCatalog` keeps the tmux `@claude_name` option on each tmux session in sync
- `EntryPoint.swift` is `@main`: it runs the app, or the `claude-hook` command when given that argument

### Key Files

| Purpose | Location |
|---------|----------|
| App entry | `apps/desktop/Sources/PlexusOneDesktop/App/EntryPoint.swift` |
| Scenes and menus | `apps/desktop/Sources/PlexusOneDesktop/App/PlexusOneDesktopApp.swift`, `App/AppCommands.swift` |
| Shared state | `apps/desktop/Sources/PlexusOneDesktop/Services/AppState.swift` |
| Session logic | `apps/desktop/Sources/PlexusOneDesktop/Services/SessionManager.swift` |
| Window persistence | `apps/desktop/Sources/PlexusOneDesktop/Services/WindowStateManager.swift` |
| Terminal view | `apps/desktop/Sources/PlexusOneDesktop/Views/AppTerminalView.swift` |
| Main content | `apps/desktop/Sources/PlexusOneDesktop/Views/ContentView.swift` |
| Claude sessions | `apps/desktop/Sources/PlexusOneDesktop/Services/ClaudeSession*.swift`, `Views/ClaudeSessionsView.swift` |
| Claude Code hook | `apps/desktop/Sources/PlexusOneDesktop/Services/ClaudeHookRecorder.swift`, `ClaudeHookInstaller.swift` |

## Common Tasks

### Add a new feature to Desktop

1. Create/modify models in `Models/`
2. Add business logic in `Services/`
3. Create UI in `Views/`
4. Add tests in `Tests/PlexusOneDesktopTests/`
5. Update docs in `docs/guides/desktop/`

### Prepare a release

Follow the full process in `docs/guides/development/maintaining.md`. In short:

1. Pull and rebase first; write the changelog after the last rebase so its commit hashes are final
2. Update `CHANGELOG.json`, then `schangelog generate CHANGELOG.json -o CHANGELOG.md` and `cp CHANGELOG.md docs/releases/changelog.md`
3. Create `docs/releases/vX.Y.Z.md` (it becomes the GitHub release page; use full GitHub URLs for links)
4. Add it to the `mkdocs.yml` Releases nav
5. Update the two version strings in `Info.plist` by hand (PlistBuddy reformats the file)
6. Push `main` and wait for Desktop CI
7. Trial run: `gh workflow run desktop-release.yaml -f version=X.Y.Z` (builds DMGs, publishes nothing)
8. Tag and push `vX.Y.Z`; the release workflow builds the DMGs and publishes the release
9. If a release fails, fix it and release the next patch version; never reuse a pushed tag

### Debug the Desktop app

```bash
cd apps/desktop
swift build
# Run directly to see console output:
.build/debug/PlexusOneDesktop
```

To test the bundled app (single-instance check, notifications, Dock badge),
build a release bundle as in `.github/workflows/desktop-release.yaml` and quit
any installed copy first, since a second instance hands off to the running one.

## Links

- [MkDocs Site](https://plexusone.github.io/plexusone-app/)
- [GitHub Repo](https://github.com/plexusone/plexusone-app)
