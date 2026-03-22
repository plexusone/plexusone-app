# PlexusOne Nexus - Product Requirements Document

## Overview

**Product Name:** PlexusOne Nexus
**Version:** 1.0
**Status:** Draft
**Last Updated:** 2026-03-20

## Problem Statement

Developers using multiple AI CLI agents (Claude Code, Codex CLI, Gemini CLI, etc.) face significant challenges:

1. **Visual overload** - Managing multiple tmux panes/terminal windows is cognitively expensive
2. **No persistent history** - Interactions are ephemeral and hard to search
3. **No async workflows** - Must actively watch terminals; no notification system
4. **No structured logging** - Cannot analyze token usage, task efficiency, or failure patterns
5. **No coordination** - Each agent operates in isolation with no task routing

Current solutions like get-shit-done (GSD) and Gas Town attempt automation but suffer from excessive token consumption due to poor task boundaries and over-communication between agents.

## Vision

Nexus is a **native terminal multiplexer and control plane for AI agents** - a macOS application that fully replaces iTerm2/Terminal.app for managing AI CLI agents. It embeds terminal emulation directly (via SwiftTerm) while using tmux for session persistence.

**Key differentiators:**

- **Embedded terminals**: No external terminal app needed; Nexus IS the terminal
- **Multi-window/multi-pane**: Browser-like window model with flexible pane layouts
- **Session persistence**: tmux sessions survive app crashes and restarts
- **Detach/attach**: Panes can dynamically connect to any tmux session
- **Agent-aware**: Built-in logging, token tracking, and status monitoring

The key insight: **manual orchestration first, automation later**. By building a better human interface, we learn the coordination patterns that matter before encoding them in software.

## Target Users

**Primary:** Developers who regularly use 3+ AI CLI agents simultaneously for software development tasks.

**Persona:**

- Uses Claude Code, Codex CLI, Gemini CLI, or similar tools
- Currently manages agents via tmux + iTerm2
- Frustrated by context-switching between panes
- Wants to track which agent is doing what
- Wants to step away and return to progress updates

## Core Principles

1. **tmux is infrastructure, not orchestrator** - Nexus controls tmux; tmux runs agents
2. **Human-in-the-loop** - User makes routing decisions; Nexus provides visibility
3. **Log everything** - Every interaction is recorded for analysis
4. **Structured communication** - Enforce task/response formats even in manual mode
5. **Token awareness** - Make token costs visible to build intuition

## Features (v1)

### P0 - Must Have

#### Multi-Window Support

- Create multiple application windows (like Chrome)
- Each window operates independently
- Windows can be arranged across desktops/monitors

#### Multi-Pane Layout

- Split panes horizontally or vertically within a window
- Flexible layouts: single, 2-up, 3-up, grid
- Resize panes by dragging dividers
- Navigate between panes with keyboard (⌘1-9, ⌘], ⌘[)

#### Embedded Terminal (SwiftTerm)

- Full terminal emulation in each pane
- ANSI color support, cursor control, scrollback
- Native macOS text rendering and font support
- Standard terminal input (typing goes directly to session)

#### Session Management

- List all tmux sessions with status indicator
- Create new tmux session from UI
- Attach pane to existing session
- Detach pane from session (session keeps running)
- Kill session from UI

#### Attach/Detach Model

- Each pane can attach to one tmux session
- Panes start detached (empty state with session picker)
- Detaching leaves session running in background
- Multiple panes can attach to same session (mirrored view)

#### Status Bar

- Show all sessions across bottom of window
- Status indicators: 🟢 running, 🟡 idle, 🔴 stuck
- Click session to attach in focused pane
- Quick-create new session button

### P1 - Should Have

#### Structured Logging

Every interaction optionally logged as JSON:

```json
{
  "session": "coder-1",
  "input": "Write a Node.js middleware...",
  "output": "...",
  "input_tokens": 120,
  "output_tokens": 450,
  "timestamp": "2026-03-20T10:00:00Z",
  "duration_ms": 12500
}
```

Token counts use heuristic estimation (1 token ≈ 4 characters) in v1.

#### Window/Layout Persistence

- Save window positions and pane layouts
- Restore on app launch
- Remember which session was attached to each pane

#### Session Metadata

- Name/rename sessions
- Assign agent type (Claude, Codex, Gemini, etc.)
- Custom color/icon per session

### P2 - Nice to Have

#### Token Dashboard

- Aggregate token usage per session
- Daily/weekly trends
- Cost estimates (based on model pricing)

#### Task Templates

- Quick-insert common task formats
- Enforce structure: Goal, Input, Constraints, Expected Output

#### Activity Timeline

- Per-session history of interactions
- Searchable by content

## User Stories

### US-1: Multi-Pane Workflow

> As a developer, I want to work with multiple agents side-by-side in a single window so I can compare outputs and coordinate work.

**Acceptance Criteria:**

- Split window into 2+ panes (horizontal or vertical)
- Each pane shows its own terminal session
- Can resize panes by dragging
- Keyboard shortcuts to navigate between panes

### US-2: Attach to Existing Session

> As a developer, I want to attach a pane to an already-running tmux session so I can resume work or monitor background tasks.

**Acceptance Criteria:**

- Session picker shows all available tmux sessions
- Shows session name, status, last activity time
- Click to attach; terminal output appears immediately
- Session history (scrollback) is available

### US-3: Detach Without Stopping

> As a developer, I want to detach from a session without killing it so the agent keeps working while I close the pane.

**Acceptance Criteria:**

- Detach command (⌘⇧A) disconnects pane from session
- Session continues running in tmux
- Pane shows "detached" state with reattach option
- Can close pane; session unaffected

### US-4: View All Session Status

> As a developer, I want to see the status of all my sessions at a glance so I know which agents need attention.

**Acceptance Criteria:**

- Status bar shows all sessions
- Color indicators: running (green), idle (yellow), stuck (red)
- Updates within 5 seconds
- Click session to attach in focused pane

### US-5: Create New Session

> As a developer, I want to quickly create a new tmux session and start an agent so I can spin up new workers.

**Acceptance Criteria:**

- ⌘N creates new session with name prompt
- Auto-attaches to new pane
- Can specify command to run (default: shell)
- Session appears in status bar immediately

### US-6: Multiple Windows

> As a developer, I want to have multiple Nexus windows so I can organize agents by project or task.

**Acceptance Criteria:**

- ⌘⇧N opens new window
- Each window has independent pane layout
- Windows can be on different desktops/monitors
- Window state persists across app restart

## Out of Scope (v1)

- Automated orchestration / task routing
- Agent-to-agent communication
- Discord integration
- Mobile companion app
- Windows/Linux support (macOS only)
- Real tokenizer integration (using heuristic only)
- tmux control mode integration (using standard attach)
- Tabs within panes (panes only, no tab bar per pane)
- SSH remote sessions (local tmux only)

## Success Metrics

| Metric | Target |
|--------|--------|
| Replace iTerm entirely | 100% of agent work done in Nexus |
| Multi-agent visibility | Can monitor 5+ sessions simultaneously |
| Session resilience | Sessions survive app crash/restart |
| Pane flexibility | Split, attach, detach workflows feel natural |
| Startup time | App launches and restores layout in < 2s |

## Future Considerations (v2+)

1. **Discord integration** - Each agent as a channel; async notifications
2. **Mobile companion app** - Monitor and send simple commands
3. **Automated task routing** - Rules-based agent selection
4. **Agent wrappers** - JSON API over CLI tools for structured communication
5. **Real token counting** - Integrate model-specific tokenizers
6. **Replay/debug** - Re-run past interactions

## Open Questions

1. Should we support custom agent launch commands from UI, or require pre-existing tmux sessions?
2. What's the right threshold for "stuck" detection? Should it be per-agent configurable?
3. Should logs be per-agent files or single JSONL?

## References

- [get-shit-done (GSD)](https://github.com/gsd-build/get-shit-done) - Reference orchestrator
