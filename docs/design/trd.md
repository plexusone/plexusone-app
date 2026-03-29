# PlexusOne Desktop - Technical Requirements Document

## Overview

**Product Name:** PlexusOne Desktop
**Version:** 1.0
**Status:** Draft
**Last Updated:** 2026-03-20

## Architecture Overview

PlexusOne Desktop is a **native terminal multiplexer with embedded terminal emulation**, replacing iTerm2 entirely. It uses SwiftTerm for terminal rendering and tmux for session persistence.

### Core Concepts

| Concept | Description |
|---------|-------------|
| **Window** | Top-level application window (like a Chrome window) |
| **Pane** | Terminal view within a window (SwiftTerm instance) |
| **Session** | tmux session (persistent, survives app restart) |
| **Attachment** | Connection between a Pane and a Session |

### Relationships

```
┌─────────────────────────────────────────────────────────────────┐
│                      PlexusOne Desktop Application                          │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Window 1                              │   │
│  │  ┌─────────────────┬─────────────────┐                  │   │
│  │  │     Pane A      │     Pane B      │                  │   │
│  │  │  ↔ session:     │  ↔ session:     │                  │   │
│  │  │    coder-1      │    reviewer     │                  │   │
│  │  └─────────────────┴─────────────────┘                  │   │
│  │  ┌───────────────────────────────────┐                  │   │
│  │  │            Pane C                 │                  │   │
│  │  │         ↔ session: planner        │                  │   │
│  │  └───────────────────────────────────┘                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Window 2                              │   │
│  │  ┌───────────────────────────────────┐                  │   │
│  │  │            Pane D                 │                  │   │
│  │  │         ↔ session: coder-2        │                  │   │
│  │  └───────────────────────────────────┘                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Services: SessionManager │ LogStore │ WindowManager      │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ PTY via tmux attach
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       tmux server                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│  │ coder-1  │  │ coder-2  │  │ reviewer │  │ planner  │  ...   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘        │
└─────────────────────────────────────────────────────────────────┘
```

### Key Properties

- **Panes are ephemeral**: UI layout, destroyed when window closes
- **Sessions are persistent**: Survive app restart, managed by tmux
- **Attachment is dynamic**: Panes can detach and reattach to different sessions
- **Multiple views**: Two panes can attach to the same session (like `tmux attach`)

## Technology Stack

| Component | Technology | Rationale |
|-----------|------------|-----------|
| Platform | macOS 14+ | Target platform; native performance |
| Language | Swift 5.9+ | Native macOS development |
| UI Framework | SwiftUI + AppKit | Multi-window requires AppKit integration |
| Terminal Emulation | [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | Native Swift, production-ready |
| Session Management | tmux | Industry-standard, session persistence |
| Data Storage | JSONL files | Simple, append-only, human-readable |

### Why SwiftTerm + tmux

| Concern | Solution |
|---------|----------|
| Terminal rendering | SwiftTerm handles ANSI, colors, scrollback |
| Session persistence | tmux sessions survive app crashes |
| Reconnection | `tmux attach` restores full session state |
| Background execution | Agents keep running when pane closes |

## Component Design

### 1. Domain Models

```swift
// MARK: - Core Types

struct Session: Identifiable, Codable {
    let id: UUID
    let name: String                    // e.g., "coder-1"
    let tmuxSession: String             // tmux session name
    var agentType: AgentType?           // Optional: claude, codex, gemini
    var status: SessionStatus
    var lastActivity: Date
    var metadata: [String: String]
}

enum SessionStatus: String, Codable {
    case running    // Active output within threshold
    case idle       // No recent output
    case stuck      // No output for extended period
    case detached   // No pane attached (still running in tmux)
}

enum AgentType: String, Codable {
    case claude
    case codex
    case gemini
    case kiro
    case custom
}

struct PlexusOne DesktopPane: Identifiable {
    let id: UUID
    weak var terminalView: TerminalView?
    var attachedSession: Session?
    var isAttached: Bool { attachedSession != nil }
}

struct PlexusOne DesktopWindow: Identifiable {
    let id: UUID
    var panes: [PlexusOne DesktopPane]
    var layout: PaneLayout
    var title: String
}

enum PaneLayout {
    case single
    case horizontalSplit(ratio: CGFloat)
    case verticalSplit(ratio: CGFloat)
    case grid(rows: Int, cols: Int)
    case custom(frames: [CGRect])
}
```

### 2. SessionManager

Central service for tmux session lifecycle.

```swift
protocol SessionManagerProtocol {
    // Session discovery
    func listSessions() async throws -> [Session]
    func refreshStatus() async throws

    // Session lifecycle
    func createSession(name: String, command: String?) async throws -> Session
    func killSession(_ session: Session) async throws
    func renameSession(_ session: Session, to newName: String) async throws

    // Attachment
    func attach(pane: PlexusOne DesktopPane, to session: Session) throws -> Process
    func detach(pane: PlexusOne DesktopPane) throws
}

@Observable
class SessionManager: SessionManagerProtocol {
    private(set) var sessions: [Session] = []
    private var attachments: [UUID: Process] = [:]  // pane.id -> tmux process

    func attach(pane: PlexusOne DesktopPane, to session: Session) throws -> Process {
        // Launch: tmux attach -t <session>
        // Connect SwiftTerm to the PTY
    }
}
```

**tmux commands used:**

```bash
# List sessions with metadata
tmux list-sessions -F "#{session_name}|#{session_activity}|#{session_attached}"

# Create new session
tmux new-session -d -s <name> [command]

# Attach (returns PTY for SwiftTerm)
tmux attach -t <session>

# Kill session
tmux kill-session -t <session>

# Rename session
tmux rename-session -t <old> <new>
```

### 3. WindowManager

Manages application windows and their pane layouts.

```swift
@Observable
class WindowManager {
    private(set) var windows: [PlexusOne DesktopWindow] = []

    // Window lifecycle
    func createWindow() -> PlexusOne DesktopWindow
    func closeWindow(_ window: PlexusOne DesktopWindow)

    // Pane management within window
    func addPane(to window: PlexusOne DesktopWindow, at position: PanePosition) -> PlexusOne DesktopPane
    func removePane(_ pane: PlexusOne DesktopPane, from window: PlexusOne DesktopWindow)
    func splitPane(_ pane: PlexusOne DesktopPane, direction: SplitDirection) -> PlexusOne DesktopPane

    // Layout
    func setLayout(_ layout: PaneLayout, for window: PlexusOne DesktopWindow)
}

enum SplitDirection {
    case horizontal  // Side by side
    case vertical    // Stacked
}

enum PanePosition {
    case left, right, top, bottom, center
}
```

### 4. TerminalViewController

Wraps SwiftTerm for each pane.

```swift
import SwiftTerm

class TerminalViewController: NSViewController {
    private var terminalView: LocalProcessTerminalView!
    private var currentProcess: Process?

    var onOutput: ((String) -> Void)?
    var onProcessExit: (() -> Void)?

    func attachToSession(_ session: Session) {
        // Detach from current if any
        detach()

        // Create PTY and connect to tmux
        terminalView.startProcess(
            executable: "/usr/bin/tmux",
            args: ["attach", "-t", session.tmuxSession],
            environment: ProcessInfo.processInfo.environment
        )
    }

    func detach() {
        // Send detach command to tmux (Ctrl-B d or custom prefix)
        // Or kill the attach process
        currentProcess?.terminate()
        currentProcess = nil
    }

    func createNewSession(name: String, command: String? = nil) {
        let cmd = command ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        // Create session and attach
        Task {
            let session = try await sessionManager.createSession(name: name, command: cmd)
            attachToSession(session)
        }
    }
}
```

### 5. LogStore

Persistent logging with session context.

```swift
struct InteractionLog: Codable {
    let id: UUID
    let sessionId: UUID
    let sessionName: String
    let windowId: UUID?
    let paneId: UUID?
    let input: String
    let output: String
    let inputTokens: Int
    let outputTokens: Int
    let timestamp: Date
    let durationMs: Int?
}

class LogStore {
    private let logDir: URL  // ~/Library/Application Support/PlexusOne Desktop/logs/

    func log(_ interaction: InteractionLog) async throws
    func query(sessionId: UUID?, since: Date?, limit: Int?) async throws -> [InteractionLog]
    func export(format: ExportFormat) async throws -> Data
}

enum ExportFormat {
    case jsonl
    case csv
}
```

### 6. TokenEstimator

```swift
struct TokenEstimator {
    static func estimate(_ text: String, model: AgentType? = nil) -> Int {
        // v1: Simple heuristic
        return max(1, text.count / 4)

        // v2: Model-specific tokenizers
        // switch model {
        // case .claude: return ClaudeTokenizer.count(text)
        // case .codex: return TiktokenTokenizer.count(text)
        // ...
        // }
    }
}
```

## UI Architecture

### Window Structure

Each window follows this layout:

```
┌─────────────────────────────────────────────────────────────────┐
│  [+] New Pane   │   Session: coder-1 ▼   │   [⚙] Settings      │  <- Toolbar
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────┬───────────────────────────────┐   │
│  │                         │                               │   │
│  │      Terminal Pane      │       Terminal Pane           │   │
│  │      (SwiftTerm)        │       (SwiftTerm)             │   │
│  │                         │                               │   │
│  │  Session: coder-1       │  Session: reviewer            │   │
│  │  Status: 🟢 running     │  Status: 🟡 idle              │   │
│  │                         │                               │   │
│  └─────────────────────────┴───────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Terminal Pane                         │   │
│  │                    (SwiftTerm)                           │   │
│  │                                                          │   │
│  │  Session: planner │ Status: 🟢 running                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│  Sessions: coder-1 🟢 │ coder-2 🟡 │ reviewer 🟢 │ [+]         │  <- Status Bar
└─────────────────────────────────────────────────────────────────┘
```

### Pane Context Menu

Right-click on pane divider or title bar:

```
┌──────────────────────────┐
│ Split Horizontal      ⌘D │
│ Split Vertical        ⌘⇧D│
├──────────────────────────┤
│ Attach to Session...  ⌘A │
│ Detach               ⌘⇧A │
│ New Session...        ⌘N │
├──────────────────────────┤
│ Close Pane            ⌘W │
└──────────────────────────┘
```

### Session Picker (Attach Dialog)

```
┌────────────────────────────────────────┐
│ Attach to Session                      │
├────────────────────────────────────────┤
│ 🟢 coder-1      (claude)    2m ago     │
│ 🟡 coder-2      (codex)     15m ago    │
│ 🟢 reviewer     (gemini)    30s ago    │
│ 🔴 planner      (claude)    1h ago     │
├────────────────────────────────────────┤
│ [+ Create New Session]                 │
└────────────────────────────────────────┘
```

### Status Bar

Global view of all sessions:

```
┌─────────────────────────────────────────────────────────────────┐
│ 🟢 coder-1 │ 🟡 coder-2 │ 🟢 reviewer │ 🔴 planner │ [+] [📊]   │
└─────────────────────────────────────────────────────────────────┘
           ↑                                              ↑
     Click to attach                              Token dashboard
     in focused pane
```

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| New Window | ⌘N |
| Close Window | ⌘⇧W |
| New Pane (new session) | ⌘T |
| Split Horizontal | ⌘D |
| Split Vertical | ⌘⇧D |
| Close Pane | ⌘W |
| Attach to Session | ⌘A |
| Detach Pane | ⌘⇧A |
| Next Pane | ⌘] |
| Previous Pane | ⌘[ |
| Next Window | ⌘` |
| Focus Pane 1-9 | ⌘1-9 |
| Toggle Status Bar | ⌘/ |
| Token Dashboard | ⌘⇧T |

## Data Flow

### Attaching to a Session

```
User clicks "Attach to Session"
         │
         ▼
    Session Picker shown
         │
         ▼
    User selects session
         │
         ▼
    SessionManager.attach(pane, session)
         │
         ├──► Spawns: tmux attach -t <session>
         │
         ├──► Returns PTY file descriptor
         │
         └──► SwiftTerm connects to PTY
                  │
                  ▼
         Terminal output streams to pane
                  │
                  ▼
         LogStore captures I/O (optional)
```

### Creating a New Session

```
User: ⌘T or "New Session..."
         │
         ▼
    Name prompt (or auto-generate)
         │
         ▼
    SessionManager.createSession(name, shell)
         │
         ├──► tmux new-session -d -s <name> <shell>
         │
         └──► Returns Session
                  │
                  ▼
    WindowManager.addPane() OR splitPane()
         │
         ▼
    Auto-attach new pane to new session
```

### Detaching a Pane

```
User: ⌘⇧A or "Detach"
         │
         ▼
    SessionManager.detach(pane)
         │
         ├──► Sends Ctrl-B d (or kills attach process)
         │
         └──► Pane shows "Detached" state
                  │
                  ▼
    Session continues running in tmux
         │
         ▼
    Pane can be reattached or closed
```

## Configuration

```json
{
  "appearance": {
    "theme": "auto",
    "font": "SF Mono",
    "fontSize": 13,
    "cursorStyle": "block",
    "cursorBlink": true
  },
  "sessions": {
    "defaultShell": "/bin/zsh",
    "tmuxPrefix": "C-b",
    "autoAttachOnLaunch": true,
    "showDetachedSessions": true
  },
  "statusThresholds": {
    "idleAfterSeconds": 30,
    "stuckAfterSeconds": 120
  },
  "logging": {
    "enabled": true,
    "captureOutput": true,
    "path": "~/Library/Application Support/PlexusOne Desktop/logs"
  },
  "windows": {
    "restoreOnLaunch": true,
    "defaultLayout": "single"
  }
}
```

## File Organization

```
~/Library/Application Support/PlexusOne Desktop/
├── config.json               # User preferences
├── sessions.json             # Session metadata (name, type, etc.)
├── windows.json              # Window/pane layout state (for restore)
├── logs/
│   ├── interactions.jsonl    # All logged interactions
│   └── sessions/
│       ├── coder-1.log       # Per-session raw output (optional)
│       └── reviewer.log
└── themes/
    └── custom.json           # Custom color schemes
```

## Error Handling

| Scenario | Handling |
|----------|----------|
| tmux not installed | Show install instructions, offer Homebrew command |
| tmux server not running | Auto-start with `tmux start-server` |
| Session died unexpectedly | Show notification, offer to recreate |
| Attach fails | Show error, offer retry or create new |
| SwiftTerm crash | Isolate to pane, offer reattach |

## Security Considerations

- **No secrets in logs**: Logging is opt-in per session
- **No network access**: v1 is fully local
- **Sandboxing**: May need `com.apple.security.temporary-exception.files.absolute-path.read-write` for tmux socket access
- **PTY permissions**: Standard terminal emulator permissions

## Testing Strategy

| Layer | Approach |
|-------|----------|
| SessionManager | Integration tests with real tmux |
| WindowManager | Unit tests for layout logic |
| TerminalViewController | Manual testing with SwiftTerm |
| LogStore | Unit tests with temp directory |
| UI | SwiftUI previews + manual testing |

## Implementation Phases

### Phase 1: Single Window + Basic Attach

- [ ] SwiftTerm integration in single-pane window
- [ ] SessionManager: list, create, attach, detach
- [ ] Basic toolbar: session picker, status indicator
- [ ] Keyboard shortcuts: ⌘N, ⌘W, ⌘A

### Phase 2: Multi-Pane

- [ ] Horizontal and vertical splits
- [ ] Pane navigation (⌘], ⌘[, ⌘1-9)
- [ ] Pane resize with drag
- [ ] Context menu for pane operations

### Phase 3: Multi-Window + Persistence

- [ ] Multiple windows (⌘N for window)
- [ ] Window/pane state persistence
- [ ] Restore layout on launch
- [ ] Status bar with all sessions

### Phase 4: Logging & Analytics

- [ ] LogStore implementation
- [ ] Token estimation
- [ ] Token dashboard (⌘⇧T)
- [ ] Per-session activity tracking

### Phase 5: Polish

- [ ] Theming support
- [ ] Custom fonts
- [ ] Preferences UI
- [ ] Performance optimization

## Future Architecture (v2+)

### Agent Wrappers

For structured communication beyond raw terminal:

```
tmux session
  └── agent-wrapper (Go/Rust binary)
        ├── launches CLI tool (claude, codex, etc.)
        ├── parses structured output
        ├── exposes JSON API (Unix socket)
        └── reports: status, tokens, errors
```

### Discord Integration

```
PlexusOne Desktop (macOS)
     │
     ├──► Local API server (localhost:9999)
     │
     ▼
Discord Bot ──► PlexusOne Desktop API ──► SessionManager
     ▲                              │
     └──────────────────────────────┘
         (session output relay)
```

### Mobile Companion

- View session status
- Send simple commands
- Receive notifications
- Read recent output

## Open Technical Questions

1. **tmux prefix key**: Should we intercept it or pass through?
2. **Scrollback sync**: How to handle SwiftTerm scrollback vs tmux scrollback?
3. **Copy mode**: Use SwiftTerm selection or tmux copy-mode?
4. **Multiple attach**: Allow same session in multiple panes?

## Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | latest | Terminal emulation |
| tmux | 3.0+ | Session management |

## References

- [SwiftTerm GitHub](https://github.com/migueldeicaza/SwiftTerm)
- [tmux man page](https://man.openbsd.org/tmux)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [AppKit Multi-Window](https://developer.apple.com/documentation/appkit/nswindow)
- [PRD](./prd.md) - Product requirements
