# Session Management

Sessions are tmux sessions that run your AI agents. PlexusOne Desktop helps you manage them visually.

## Creating Sessions

### From Terminal

```bash
# Create a session with Claude Code
tmux new-session -d -s coder-1 "claude"

# Create a session with a custom command
tmux new-session -d -s my-agent "kiro"

# Create an empty session
tmux new-session -d -s scratch
```

### From PlexusOne Desktop

1. Click the **+** button (toolbar or status bar)
2. Fill in the New Session form:
   - **Name**: Session identifier (e.g., `feature-login`)
   - **Command**: Optional command to run (e.g., `claude`)
3. Click **Create**

The session is created and attached to the first empty pane.

## Attaching Sessions

### Via Dropdown

1. Click the session dropdown in any pane header
2. Select a session from the list
3. Session output appears in the pane

### Via Empty Pane

Empty panes show available sessions. Click any session to attach it.

## Detaching Sessions

Click the **✕** button in the pane header to detach.

!!! warning "Detach vs Kill"
    - **Detach**: Session keeps running, just hidden from view
    - **Kill**: Session terminates, agent stops

## Session Status

### Status Detection

PlexusOne Desktop monitors sessions and infers status:

| Status | Indicators |
|--------|------------|
| **Running** | Recent output, active process |
| **Idle** | No recent output, waiting |
| **Stuck** | Long pause, potential issue |

### Status Bar

The status bar shows all pane assignments:

```
#1 🟢 coder-1 | #2 🔵 reviewer | #3 empty | 3 sessions
```

## Listing Sessions

### In PlexusOne Desktop

- Click any session dropdown to see available sessions
- Status bar shows session count

### From Terminal

```bash
# List all sessions
tmux list-sessions

# Detailed view
tmux list-sessions -F "#{session_name}: #{session_windows} windows"
```

## Killing Sessions

### From Terminal

```bash
# Kill a specific session
tmux kill-session -t coder-1

# Kill all sessions
tmux kill-server
```

### From PlexusOne Desktop

Currently, sessions must be killed from the terminal. Future versions will add in-app session management.

## Session Refresh

Click the **refresh** button (↻) in the toolbar to:

- Reload session list from tmux
- Update session statuses
- Detect new sessions created externally

Sessions auto-refresh periodically, but manual refresh is instant.

## Best Practices

### Naming Conventions

Use descriptive, consistent names:

```bash
# By feature
feature-auth
feature-payments
feature-dashboard

# By role
coder-1
coder-2
reviewer
tester

# By task type
bugfix-123
refactor-api
docs-update
```

### Session Lifecycle

1. **Create** session when starting a task
2. **Attach** to pane for visibility
3. **Detach** when not actively monitoring
4. **Kill** when task is complete

### Long-Running Sessions

For agents that run for hours:

- Keep sessions attached for visibility
- Use larger scrollback (PlexusOne Desktop has 10,000 lines)
- Monitor status colors for issues
- Detach temporarily if needed for other work

## Troubleshooting

### "Session Error" Alert

If PlexusOne Desktop can't complete a session operation (for example, tmux isn't installed or a command failed), a **Session Error** alert now appears describing the problem instead of failing silently. Click **OK** to dismiss it; the underlying error is cleared.

### Session Not Appearing

1. Refresh the session list (↻ button)
2. Verify session exists: `tmux list-sessions`
3. Check tmux socket: `tmux -L default list-sessions`

### Session Shows "Ended"

The process inside the session exited. Options:

1. Reattach and start a new command
2. Kill and recreate the session

### Pane Frozen / Warning Triangle Next to Session Name

If you see an amber warning triangle (⚠) next to a session name, or a dismissible banner at the top of the window, PlexusOne Desktop has detected that the session's shell is running behind an autocomplete PTY shim from one of:

- **Kiro CLI** (`kiro-cli-term`)
- **Fig** (`figterm`)
- **Amazon Q** (`qterm`)

These tools re-exec your shell inside a PTY wrapper so they can watch keystrokes for inline completions. It's a known cause of frozen panes — when the shim deadlocks, the agent running inside blocks on I/O and the pane hangs for every attached client, including PlexusOne Desktop.

**Fix:** remove the wrapper's shell integration, then open a new shell/session:

```bash
# Kiro CLI
kiro-cli integration uninstall dotfiles

# Fig
fig integrations uninstall dotfiles

# Amazon Q
q integrations uninstall dotfiles
```

Hover the warning triangle or the banner's "Copy" button to get the exact command for the detected tool. Use **Don't show again** on the banner once you've addressed it, or **✕** to dismiss it for the current session only.

### Multiple tmux Servers

PlexusOne Desktop connects to the default tmux server. If using named servers:

```bash
# This won't appear in PlexusOne Desktop
tmux -L myserver new-session -s test

# Use default server instead
tmux new-session -s test
```
