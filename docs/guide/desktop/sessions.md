# Session Management

Sessions are tmux sessions that run your AI agents. Nexus helps you manage them visually.

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

### From Nexus

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

Nexus monitors sessions and infers status:

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

### In Nexus

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

### From Nexus

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
- Use larger scrollback (Nexus has 10,000 lines)
- Monitor status colors for issues
- Detach temporarily if needed for other work

## Troubleshooting

### Session Not Appearing

1. Refresh the session list (↻ button)
2. Verify session exists: `tmux list-sessions`
3. Check tmux socket: `tmux -L default list-sessions`

### Session Shows "Ended"

The process inside the session exited. Options:

1. Reattach and start a new command
2. Kill and recreate the session

### Multiple tmux Servers

Nexus connects to the default tmux server. If using named servers:

```bash
# This won't appear in Nexus
tmux -L myserver new-session -s test

# Use default server instead
tmux new-session -s test
```
