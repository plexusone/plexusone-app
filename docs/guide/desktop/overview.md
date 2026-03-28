# Desktop App Overview

Nexus Desktop is a macOS application for managing multiple AI CLI agent sessions in a unified interface.

## Main Interface

### Components

1. **Toolbar** - Layout picker, new session button, refresh
2. **Grid Layout** - Configurable panes (1×1 to 4×4)
3. **Pane Header** - Session dropdown, pane number, detach button
4. **Terminal View** - Embedded terminal showing session output
5. **Status Bar** - Pane indicators, session count

## Key Concepts

### Sessions vs Panes

| Concept | Description |
|---------|-------------|
| **Session** | A tmux session running an AI agent (e.g., Claude Code) |
| **Pane** | A visual slot in the grid that can display a session |

Sessions exist independently of panes. You can:

- **Attach** a session to a pane (view its output)
- **Detach** a session from a pane (keep it running invisibly)
- **Move** a session between panes

### Session States

Sessions are color-coded by status:

| Status | Color | Meaning |
|--------|-------|---------|
| 🟢 Running | Green | Agent is actively working |
| 🔵 Idle | Blue | Agent is waiting for input or finished |
| 🟠 Stuck | Orange | Agent may need attention |
| 🔴 Error | Red | Session has an error |

## Workflows

### Multi-Agent Development

Run multiple coding agents in parallel:

1. Create sessions for different tasks:
   ```bash
   tmux new-session -d -s feature-auth "claude"
   tmux new-session -d -s feature-api "claude"
   tmux new-session -d -s tests "claude"
   ```

2. Use a 3×1 layout to view all three side-by-side

3. Monitor progress and respond to prompts as needed

### Code Review Pipeline

Set up a review workflow:

1. **Pane 1**: Coder agent working on implementation
2. **Pane 2**: Reviewer agent checking code
3. **Pane 3**: Test runner agent

### Focus Mode

Need to concentrate on one agent?

1. Switch to 1×1 layout
2. Attach the session you're working with
3. Other sessions continue running in the background

## Features

### Scrollback Buffer

Each pane has 10,000 lines of scrollback. Scroll up to review:

- Previous commands
- Agent reasoning
- Error messages
- Full conversation history

**Scrolling with tmux:**

When attached to a tmux session, enable mouse mode for trackpad scrolling:

```bash
tmux set -g mouse on
```

Add to `~/.tmux.conf` to make it permanent. With mouse mode enabled, two-finger trackpad scrolling works to navigate through tmux's scrollback buffer.

### State Persistence

Your workspace is automatically saved:

- Grid layout (columns × rows)
- Pane-to-session assignments
- Saved to `~/.plexusone/nexus_state.json`

On restart, you're prompted to restore or start fresh.

### Session Creation

Create new tmux sessions directly from Nexus:

1. Click the **+** button in the toolbar or status bar
2. Enter a session name
3. Optionally specify a command to run
4. Session is created and attached to an empty pane

## Tips

!!! tip "Use Descriptive Session Names"
    Name sessions by task: `feature-login`, `bugfix-123`, `refactor-api`
    This makes it easy to identify them in dropdowns.

!!! tip "Detach, Don't Kill"
    When done with a pane, click ✕ to detach (session keeps running).
    Only kill sessions when you want to stop the agent completely.

!!! tip "Match Layout to Task"
    - **1×1**: Focused work with one agent
    - **2×1**: Side-by-side comparison
    - **3×2**: Full team of agents
