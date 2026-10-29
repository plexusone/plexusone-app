# macOS Desktop App Development

The desktop app (`apps/desktop`) is a native macOS terminal multiplexer built with Swift and SwiftTerm for managing tmux sessions.

## Prerequisites

| Tool | Version | Installation |
|------|---------|--------------|
| Xcode | 16+ | App Store |
| macOS | 14+ (Sonoma) | Required for SwiftUI features |
| tmux | 3.x+ | `brew install tmux` |

Verify tmux installation:

```bash
tmux -V
```

## Project Setup

The project uses Swift Package Manager. No additional setup required:

```bash
cd apps/desktop
swift build
```

Or open in Xcode:

```bash
cd apps/desktop
open Package.swift
```

## Running the App

### Command Line (Recommended for Development)

Build and run:

```bash
cd apps/desktop
swift build && .build/debug/PlexusOneDesktop
```

### Restarting the App

To stop a running instance and restart:

```bash
pkill -f PlexusOneDesktop 2>/dev/null; swift build && .build/debug/PlexusOneDesktop
```

### Xcode

1. Open `Package.swift` in Xcode
2. Select the `PlexusOneDesktop` scheme
3. Press ⌘R to build and run

### Release Build

```bash
swift build -c release
.build/release/PlexusOneDesktop
```

## Development Commands

| Command | Description |
|---------|-------------|
| `swift build` | Build debug version |
| `swift build -c release` | Build release version |
| `swift test` | Run unit tests |
| `swift package clean` | Clean build artifacts |
| `swift package resolve` | Resolve dependencies |
| `swift package update` | Update dependencies |

## Project Structure

```
apps/desktop/
├── Package.swift                           # Swift package manifest
├── Sources/PlexusOneDesktop/
│   ├── App/
│   │   ├── EntryPoint.swift                # @main: runs the app, or the claude-hook command
│   │   ├── PlexusOneDesktopApp.swift       # Scenes and windows
│   │   ├── AppCommands.swift               # Menu commands and shortcuts
│   │   └── AppDelegate.swift               # Lifecycle, single instance, notifications
│   ├── Models/
│   │   ├── Session.swift                   # Session, SessionStatus, AgentType
│   │   ├── ClaudeSession.swift             # Claude session info, end states, live records
│   │   ├── TerminalWrapper.swift           # PTY wrapper types
│   │   ├── WindowState.swift               # WindowConfig, MultiWindowState
│   │   └── LegacyState.swift               # v1 → v2 state migration
│   ├── Services/
│   │   ├── AppState.swift                  # Shared state, waiting alerts, Dock badge
│   │   ├── SessionManager.swift            # tmux session orchestration
│   │   ├── WindowStateManager.swift        # Multi-window persistence
│   │   ├── InputMonitor.swift              # AI prompt detection
│   │   ├── ClaudeSessionCatalog.swift      # Lists Claude sessions, polls live state
│   │   ├── ClaudeSessionRegistry.swift     # Observation log (~/.plexusone/claude-sessions.json)
│   │   ├── ClaudeSessionRestorer.swift     # Resume and rename sessions in tmux
│   │   ├── ClaudeTranscriptReader.swift    # Subject, prompts, files, and cost from transcripts
│   │   ├── ClaudeHookRecorder.swift        # The claude-hook command
│   │   ├── ClaudeHookInstaller.swift       # Adds and removes the hook in Claude settings
│   │   ├── GitRepoResolver.swift           # Maps files to github.com/org/repo
│   │   ├── SessionNavigator.swift          # Focuses the pane showing a session
│   │   ├── SystemProbe.swift               # Process start times, parents, boot time
│   │   ├── TerminalWrapperDetector.swift   # PTY wrapper detection
│   │   ├── TmuxEnvironment.swift           # Finding tmux, mouse mode options
│   │   ├── CommandExecuting.swift          # Protocol for testing
│   │   └── FileSystemAccessing.swift       # Protocol for testing
│   ├── Views/
│   │   ├── ContentView.swift               # Main window content
│   │   ├── GridLayoutView.swift            # Multi-pane grid
│   │   ├── PaneView.swift                  # Pane header and terminal
│   │   ├── AppTerminalView.swift           # SwiftTerm subclass
│   │   ├── TerminalViewRepresentable.swift # NSViewRepresentable wrapper
│   │   ├── ClaudeSessionsView.swift        # Claude Sessions window
│   │   ├── AttachSessionSheet.swift        # Attach dialog
│   │   ├── NewSessionSheet.swift           # Create session dialog
│   │   ├── SessionPickerView.swift         # Session picker for a pane
│   │   ├── DetachedView.swift              # Pop-out window
│   │   ├── StatusBarView.swift             # Status bar
│   │   ├── InputIndicatorView.swift        # AI prompt overlay
│   │   ├── WrapperWarningView.swift        # PTY wrapper warning
│   │   └── SettingsView.swift              # App preferences
│   ├── Resources/
│   │   └── AppIcon.icns                    # App icon
│   └── Info.plist                          # Bundle version
└── Tests/PlexusOneDesktopTests/
    ├── AppStateTests.swift
    ├── ClaudeSessionTests.swift
    ├── CommandExecutingTests.swift
    ├── SessionManagerTests.swift
    ├── TerminalWrapperDetectorTests.swift
    ├── WindowStateManagerTests.swift
    ├── WindowStateTests.swift
    └── Mocks/
        ├── MockCommandExecutor.swift
        └── MockFileSystem.swift
```

## Key Dependencies

| Package | Purpose |
|---------|---------|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | Terminal emulation and rendering |
| [AssistantKit](https://github.com/plexusone/assistantkit-swift) | AI prompt pattern detection |

## Architecture

The app follows a multi-window architecture with shared state:

```
AppState (Singleton)
├── SessionManager       # Shared - all tmux sessions
├── WindowStateManager   # Shared - window persistence
├── InputMonitor         # Shared - AI prompt detection
└── ClaudeSessionCatalog # Shared - Claude sessions, names, and waiting state

Window A                 Window B
├── PaneManager (local)  ├── PaneManager (local)
├── GridConfig (local)   └── GridConfig (local)
└── ContentView          └── ContentView
```

**Key principle**: `SessionManager` and `ClaudeSessionCatalog` are shared across windows (single sources of truth for tmux and Claude sessions), while `PaneManager` and `GridConfig` are per-window.

## Configuration

### State Persistence

Window layouts and session attachments are saved to:

```
~/.plexusone/state.json
```

Format (v2):

```json
{
  "windows": [
    {
      "id": "uuid",
      "gridColumns": 2,
      "gridRows": 1,
      "paneAttachments": {
        "1": "coder-1",
        "2": "reviewer"
      }
    }
  ],
  "savedAt": "2024-01-01T00:00:00Z",
  "version": 2
}
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SHELL` | `/bin/zsh` | Shell for new tmux sessions |
| `TERM` | `xterm-256color` | Terminal type (set automatically) |
| `LANG` | `en_US.UTF-8` | Locale (set if unset) |

## Testing

Run all tests:

```bash
swift test
```

Run specific test class:

```bash
swift test --filter SessionManagerTests
```

Run with verbose output:

```bash
swift test -v
```

### Test Coverage

The test suite includes 78 tests covering:

- Session parsing and status detection
- Window state persistence and migration
- Multi-window state management
- App initialization

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘N | New Session |
| ⌘⇧N | New Window |
| ⌘] | Next Pane |
| ⌘[ | Previous Pane |
| ⌘A | Select All (terminal) |

## Troubleshooting

### tmux Not Found

If the app shows "tmux Not Found" alert:

```bash
brew install tmux
```

Verify installation path:

```bash
which tmux
# Should be /opt/homebrew/bin/tmux (Apple Silicon)
# or /usr/local/bin/tmux (Intel)
```

### Build Errors

Clean and rebuild:

```bash
swift package clean
swift build
```

### Package Resolution Failed

Reset package cache:

```bash
rm -rf .build
rm Package.resolved
swift build
```

### Console Logging

View app logs in Console.app:

1. Open Console.app
2. Filter by process: `PlexusOneDesktop`
3. Look for `PlexusOne:` prefixed messages

Or use Terminal:

```bash
log stream --predicate 'process == "PlexusOneDesktop"'
```

### Session Not Attaching

If sessions appear in the list but won't attach:

1. Verify tmux server is running:

    ```bash
    tmux list-sessions
    ```

2. Check for zombie processes:

    ```bash
    ps aux | grep tmux
    ```

3. Restart tmux server:

    ```bash
    tmux kill-server
    tmux new-session -d -s test
    ```

## Comparison with Mobile Apps

| Feature | Desktop | Flutter Mobile | Native iOS |
|---------|---------|----------------|------------|
| Platform | macOS | iOS, Android, Web | iOS, iPadOS |
| Terminal | SwiftTerm (local) | xterm (remote) | SwiftTerm (remote) |
| tmux | Direct attachment | Via tuiparser | Via tuiparser |
| Multi-window | Yes | No | No |
| Grid layouts | Yes (up to 4×4) | No | No |

The desktop app is the primary interface for direct tmux management, while mobile apps connect remotely via the tuiparser WebSocket bridge.
