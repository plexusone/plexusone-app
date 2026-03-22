# Phase 1 Tasks - Single Window + Basic Attach

## Overview

Phase 1 delivers a minimal viable product: a single-window app with one terminal pane that can attach to tmux sessions.

## Task List

### 1. Project Setup

- [x] **1.1** Create Xcode project (macOS App, Swift, SwiftUI)
- [x] **1.2** Add SwiftTerm package dependency
- [x] **1.3** Configure build settings (macOS 14+, signing)
- [x] **1.4** Set up project structure (Models, Views, Services)

### 2. Core Models

- [x] **2.1** Define `NexusSession` model (id, name, tmuxSession, status, lastActivity)
- [x] **2.2** Define `SessionStatus` enum (running, idle, stuck, detached)
- [x] **2.3** Define `AgentType` enum (claude, codex, gemini, kiro, custom)

### 3. SessionManager Service

- [x] **3.1** Implement `listSessions()` - parse `tmux list-sessions`
- [x] **3.2** Implement `createSession(name:command:)` - run `tmux new-session`
- [x] **3.3** Implement `killSession(_:)` - run `tmux kill-session`
- [x] **3.4** Implement session status detection (activity timestamps)
- [x] **3.5** Add periodic refresh (poll every 5 seconds)

### 4. Terminal Integration

- [x] **4.1** Create `TerminalViewController` wrapping SwiftTerm
- [x] **4.2** Implement `attachToSession(_:)` - spawn `tmux attach -t <session>`
- [x] **4.3** Implement `detach()` - terminate attach process
- [x] **4.4** Handle terminal resize events
- [x] **4.5** Create SwiftUI wrapper (`TerminalViewRepresentable`)

### 5. Main Window UI

- [x] **5.1** Create `ContentView` with toolbar and terminal area
- [x] **5.2** Create `SessionPickerView` (dropdown/popover of sessions)
- [x] **5.3** Create `StatusIndicatorView` (colored dot for session status)
- [x] **5.4** Add "Detached" placeholder view when no session attached
- [x] **5.5** Wire up toolbar session picker to attach action

### 6. Keyboard Shortcuts

- [x] **6.1** ⌘N - Create new session (with name prompt)
- [x] **6.2** ⌘W - Detach from current session (or close window if detached)
- [x] **6.3** ⌘A - Show attach picker
- [x] **6.4** ⌘⇧A - Detach from session

### 7. Status Bar

- [x] **7.1** Create `StatusBarView` showing all sessions
- [x] **7.2** Add click-to-attach behavior
- [x] **7.3** Add [+] button to create new session

### 8. Error Handling

- [x] **8.1** Detect if tmux is not installed, show instructions
- [ ] **8.2** Handle session attach failures gracefully
- [ ] **8.3** Handle unexpected session termination

### 9. Testing & Polish

- [ ] **9.1** Manual test: create session, attach, type, detach
- [ ] **9.2** Manual test: list existing sessions, attach to external
- [ ] **9.3** Manual test: session status indicators update
- [ ] **9.4** Fix any layout/resize issues

## Acceptance Criteria

Phase 1 is complete when:

1. App launches with empty "detached" state
2. Can see list of existing tmux sessions
3. Can create a new tmux session from UI
4. Can attach pane to a session and interact (type commands, see output)
5. Can detach from session (session keeps running)
6. Status bar shows all sessions with status indicators
7. Basic keyboard shortcuts work

## Dependencies

- SwiftTerm: https://github.com/migueldeicaza/SwiftTerm
- tmux 3.0+ installed on system

## Out of Scope (Phase 1)

- Multiple panes
- Multiple windows
- Pane splitting
- Logging/token tracking
- Layout persistence
- Theming

## Build & Run

```bash
cd Nexus
swift build
swift run Nexus
```

Or open in Xcode:

```bash
cd Nexus
open Package.swift
```
