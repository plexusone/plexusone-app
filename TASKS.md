# PlexusOne Tasks

## Open

### Desktop App - Current

- [ ] **Session restore debugging**: Session restore from `~/.plexusone/state.json` may not be attaching saved sessions. Added NSLog debugging but console output not visible in iTerm2. Need to verify restore flow and session matching.

- [ ] **Copy/paste verification**: SwiftTerm should support Cmd+C (copy selected text) and Cmd+V (paste). User reported copy/paste not working - needs investigation of terminal text selection and clipboard integration.

- [ ] **Focus indicator testing**: Blue border/shadow focus indicator implemented but user didn't see visual changes. May need to verify KVO observation is firing and UI updates are applied.

- [ ] **Scroll position indicator**: Display line position (e.g., "123/615") while scrolling through terminal scrollback. Shows current position relative to total lines.

- [ ] **Scrollbar visibility**: Verify scrollbar thumb appears and is draggable when there's scrollback content (native scrollback, not tmux).

---

## Feature Roadmap

Features to make PlexusOne Desktop the best tool for developers using AI assistants.

### High Impact

#### Input Detection (Foundation)

Detect when any AI agent is waiting for user input. This is the foundational feature that enables alerts and agent-specific UI.

**Universal patterns to detect:**

| Pattern | Example | Agent |
|---------|---------|-------|
| Yes/No prompts | `[Y/n]`, `[y/N]`, `(yes/no)` | All |
| Permission prompts | `? Allow clipboard access` | Claude Code |
| Question prompts | `? Which option...` | Claude Code, Kiro |
| Raised hand | `🙋`, `✋`, `🤚` | Gemini |
| Continue prompts | `Press Enter to continue` | Various |
| Input cursor | `> `, `? `, `>>> ` | REPLs, shells |
| Approval requests | `Do you want to proceed?` | All |
| Selection prompts | `Select an option (1-4):` | Various |

**Detection approach:**

- [ ] Monitor terminal output stream in real-time
- [ ] Pattern matching with configurable regex rules
- [ ] Track cursor position (waiting at prompt vs mid-output)
- [ ] Detect output pause + cursor at line start
- [ ] Emoji detection for visual indicators (🙋, ✋, ⏸️)
- [ ] Track time since last output (distinguish thinking vs waiting)
- [ ] Learn from user responses (ML enhancement later)

**State machine:**

```
┌─────────┐    output    ┌─────────┐
│  Idle   │ ──────────▶  │ Running │
└─────────┘              └────┬────┘
     ▲                        │
     │                   pause + pattern
     │                        │
     │    user input     ┌────▼────┐
     └─────────────────  │ Waiting │  ◀── ALERT!
                         └─────────┘
```

#### Input Alerts

Desktop notifications when AI is waiting for user input. Builds on Input Detection.

- [ ] macOS notification with session name and prompt preview
- [ ] Sound alert option (configurable per agent)
- [ ] Badge app icon with pending input count
- [ ] Bring window to front option
- [ ] Menu bar indicator (colored dot)
- [ ] Configurable alert delay (avoid spam during rapid prompts)
- [ ] "Do not disturb" mode
- [ ] Per-session alert preferences

#### Agent Detection

Auto-detect which AI assistant is running. Enhances Input Detection with agent-specific context.

**Detection methods:**

- [ ] Parse process name (`claude`, `kiro`, `gemini`, `codex`)
- [ ] Analyze output patterns (prompts, formatting, colors)
- [ ] Check for known environment variables
- [ ] Monitor for agent-specific escape sequences
- [ ] Detect startup banners/signatures

**Agent-specific UI (after detection):**

| Agent | Icon/Color | Status Indicators | Quick Actions |
|-------|------------|-------------------|---------------|
| Claude Code | Purple | Thinking spinner, tool use, permission requests | Approve (y), Reject (n), Interrupt |
| Kiro CLI | Blue | Spec mode, steering, agent flow | Accept spec, Edit spec, Stop |
| GitHub Copilot | Gray | Suggestion pending, explanation mode | Accept, Reject, Explain |
| Gemini | Coral | Model indicator, function calling, 🙋 alerts | Continue, Stop, Switch model |
| Codex | Green | Generation status, edit mode | Apply, Discard, Refine |
| Custom/Unknown | Default | Basic running/idle/stuck | Interrupt only |

**Agent-specific enhancements:**

- **Claude Code**
  - Show current tool being used (Read, Edit, Bash, etc.)
  - Highlight permission requests with approve/reject buttons
  - Display task list progress if available
  - Show "Thinking..." indicator prominently
  - Parse and display file paths being accessed

- **Kiro CLI**
  - Show spec file status
  - Display steering prompt panel
  - Show agent-to-agent handoff
  - Highlight implementation vs planning mode

- **Gemini**
  - Detect 🙋 raised hand indicator
  - Show model being used
  - Parse function calling status

- **GitHub Copilot**
  - Show suggestion preview
  - Display explanation panel
  - Quick accept/reject buttons

- **General**
  - Agent logo in session title bar
  - Agent-themed color accent
  - Contextual keyboard shortcuts

#### Session Search

Full-text search across all session output history.

- [ ] Index scrollback buffer content
- [ ] Search across all sessions or single session
- [ ] Regex support
- [ ] Highlight matches in terminal
- [ ] Jump to match location
- [ ] Search history
- [ ] Filter by time range
- [ ] Export search results

#### Quick Commands

Hotkeys for common AI assistant interactions.

- [ ] Global hotkey to focus PlexusOne
- [ ] Per-session hotkeys:
  - `Cmd+Y` - Send "y" (approve)
  - `Cmd+N` - Send "n" (reject)
  - `Cmd+.` - Send Ctrl+C (interrupt)
  - `Cmd+Enter` - Send Enter (continue)
- [ ] Customizable key bindings
- [ ] Command palette (Cmd+Shift+P)
- [ ] Quick switch between sessions (Cmd+1-9)

#### Git Context

Show repository context per session.

- [ ] Detect git repository in session cwd
- [ ] Display current branch in status bar
- [ ] Show dirty/clean status indicator
- [ ] Uncommitted changes count
- [ ] Recent commits preview
- [ ] Quick git actions (status, diff, log)
- [ ] Branch switcher
- [ ] Sync with IDE git status

### Medium Impact

#### Session Recording

Record and export session transcripts.

- [ ] Record all terminal output
- [ ] Timestamp each line
- [ ] Export as plain text
- [ ] Export as Markdown (with code blocks)
- [ ] Export as HTML (with ANSI colors)
- [ ] Replay recording in terminal
- [ ] Share recording via link
- [ ] Annotate recordings

#### Error Highlighting

Parse output and highlight important events.

- [ ] Detect error patterns (stack traces, exit codes)
- [ ] Highlight warnings (yellow) and errors (red)
- [ ] Parse test output (pass/fail counts)
- [ ] Build failure detection
- [ ] Clickable file paths (open in editor)
- [ ] Error summary panel
- [ ] Filter view to show only errors
- [ ] Copy error to clipboard

#### Project Templates

Quick-start layouts for common workflows.

- [ ] Save current layout as template
- [ ] Built-in templates:
  - "Solo" - Single large pane
  - "Pair" - 2 columns (you + AI)
  - "Review" - 3 columns (code, AI, tests)
  - "Multi-agent" - 2x2 grid
- [ ] Project-specific templates
- [ ] Template sharing
- [ ] Auto-start commands per pane

#### Working Directory

Show and manage current working directory.

- [ ] Display cwd in session header
- [ ] Sync cwd across related sessions
- [ ] Quick cd to project root
- [ ] Recent directories list
- [ ] Bookmark directories
- [ ] Open in Finder
- [ ] Open in IDE
- [ ] Directory watcher for changes

#### Stuck Detection

Smarter idle detection to distinguish states.

- [ ] "Thinking" - AI is processing (show spinner)
- [ ] "Waiting" - AI needs input (show alert)
- [ ] "Idle" - No activity, may need attention
- [ ] "Stuck" - Likely hung, needs intervention
- [ ] Configurable thresholds per agent
- [ ] Visual indicators (color, animation)
- [ ] Auto-notification for stuck sessions
- [ ] One-click recovery actions

### Nice to Have

#### Cost Tracking

Estimate token usage and costs.

- [ ] Parse token counts from AI output
- [ ] Calculate cost per session
- [ ] Daily/weekly/monthly summaries
- [ ] Cost alerts/budgets
- [ ] Compare cost across agents
- [ ] Export cost reports
- [ ] Team cost allocation

#### Multi-Agent Dashboard

Bird's-eye view of all agents.

- [ ] Overview panel showing all sessions
- [ ] Status summary (running, idle, stuck, waiting)
- [ ] Task progress per session
- [ ] Drag-and-drop task reassignment
- [ ] Agent utilization metrics
- [ ] Timeline view of activity
- [ ] Filter by project/agent type

#### IDE Integration

Connect with development environments.

- [ ] VSCode extension
  - Launch session from editor
  - Open file from session in editor
  - Sync terminal to editor workspace
- [ ] JetBrains plugin
- [ ] Sublime Text integration
- [ ] Open session at cursor location
- [ ] Push selected code to session

#### Session Sharing

Collaborate on sessions with teammates.

- [ ] Generate shareable session link
- [ ] Read-only spectator mode
- [ ] Collaborative control mode
- [ ] Voice/video overlay
- [ ] Chat sidebar
- [ ] Permission controls
- [ ] Session handoff
- [ ] Recording auto-share

#### Resource Monitoring

Track system resources per session.

- [ ] CPU usage per session
- [ ] Memory usage
- [ ] Network activity
- [ ] Disk I/O
- [ ] Process tree view
- [ ] Resource alerts
- [ ] Historical graphs
- [ ] Aggregate across sessions

#### Voice Notes

Audio notes attached to sessions.

- [ ] Record voice memo per session
- [ ] Transcribe to text
- [ ] Timestamp alignment with terminal
- [ ] Playback during replay
- [ ] Share with team
- [ ] AI summary of voice notes

#### Sentinel Mode

Autonomous monitoring and intervention.

- [ ] Define rules for auto-intervention
- [ ] Auto-approve safe operations
- [ ] Auto-reject dangerous commands
- [ ] Escalate to human for edge cases
- [ ] Learning from human decisions
- [ ] Audit log of all decisions
- [ ] Configurable risk levels

### Technical Debt

- [ ] Improve test coverage for Services layer
- [ ] Add UI tests with XCTest
- [ ] Performance profiling for large scrollback
- [ ] Memory optimization for many sessions
- [ ] Accessibility improvements (VoiceOver)
- [ ] Localization support

### Documentation

- [ ] User guide for each feature
- [ ] Video tutorials
- [ ] Keyboard shortcut reference
- [ ] Troubleshooting guide
- [ ] API documentation (if applicable)
- [ ] Contributing guide updates

---

## Completed

### Documentation (CLAUDE.md)

- [x] **Add prerequisites section**: Documented required tool versions (Xcode 15+, Flutter 3.x, Go 1.22+, tmux, macOS 14+). (2026-03-29)

- [x] **Fix build command accuracy**: Updated desktop build instructions to show `.build/debug/PlexusOneDesktop` instead of .app bundle. (2026-03-29)

- [x] **Add CI/CD context**: Added Local Checks section with pre-push commands for all components. Noted CI workflows not yet configured. (2026-03-29)

- [x] **Document environment variables**: Added table of SHELL, TERM, LANG variables used by desktop app. (2026-03-29)

- [x] **Add Swift/Dart linting tools**: Added Linting section with tools and commands per component. (2026-03-29)

- [x] **List valid commit scopes**: Added valid scopes table (desktop, mobile, tuiparser, docs) to Commit Messages section. (2026-03-29)

### Desktop App

- [x] **Terminal trackpad scrolling**: Fixed two-finger trackpad scrolling by sending mouse wheel escape sequences (button 64/65) to terminal applications like tmux. Updated SwiftTerm to main branch for NSScroller Auto Layout fix. (2026-03-28)

- [x] **Unit test infrastructure**: Added protocol-based dependency injection (CommandExecuting, FileSystemAccessing), mocks, and 78 unit tests for SessionManager, WindowStateManager, and AppState. (2026-03-29)

- [x] **CI/CD pipeline**: Added GitHub Actions workflow for Swift tests using reusable workflow from plexusone/.github. (2026-03-29)

- [x] **AssistantKit integration**: Created AssistantKit Swift package with input detection patterns for Claude, Kiro, and universal patterns. Integrated InputMonitor service for real-time terminal monitoring. (2026-03-29)

- [x] **Input detection UI**: Added InputIndicatorView overlay for showing detected input prompts with suggested actions. (2026-03-29)

- [x] **Edit menu**: Added Edit menu with Select All command (Cmd+A) for terminal text selection. (2026-03-29)

- [x] **App icon**: Generated macOS .icns from mobile icon source. Added to app bundle with CFBundleIconFile configuration. (2026-03-30)

- [x] **Pane focus indicator**: Implemented visual focus indicator with blue border (3px), shadow (8px), header tint, and focus dot. Added KVO observation for real-time focus tracking. (2026-03-30)

- [x] **Release workflow**: Added GitHub Actions workflow for building macOS DMG artifacts (arm64, x86_64, universal) on version tags. (2026-03-30)
