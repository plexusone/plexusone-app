# Configuration

Configuration options for PlexusOne Desktop components.

## Desktop App

### State File

The desktop app stores session state in:

```
~/.plexusone/state.json
```

This file contains:

- Window positions and sizes
- Grid layout configuration
- Session-to-pane assignments
- Last used settings

**Format:**

```json
{
  "gridLayout": "2x2",
  "sessions": [
    {
      "paneIndex": 0,
      "sessionName": "claude-main",
      "attached": true
    }
  ],
  "windowFrame": {
    "x": 100,
    "y": 100,
    "width": 1200,
    "height": 800
  }
}
```

### Restore Behavior

On startup, if a state file exists, PlexusOne Desktop prompts:

> "Restore previous session?"
>
> [Restore] [Start Fresh]

- **Restore** - Reattaches to saved sessions if they still exist
- **Start Fresh** - Ignores saved state, starts with empty panes

### Reset Configuration

To reset to defaults, delete the state file:

```bash
rm ~/.plexusone/state.json
```

## TUI Parser

### Command Line Options

```bash
tuiparser [options]
```

| Option | Default | Description |
|--------|---------|-------------|
| `-port` | `9600` | HTTP/WebSocket server port |
| `-debug` | `false` | Enable verbose logging |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `TUIPARSER_PORT` | Override default port |
| `TUIPARSER_LOG_LEVEL` | Log level (debug, info, warn, error) |

### tmux Integration

TUI Parser automatically discovers tmux sessions via:

```bash
tmux list-sessions -F "#{session_name}"
```

No additional configuration is required if tmux is in your PATH.

## Mobile App

### Server Configuration

Server settings are stored locally on the device:

| Setting | Default | Description |
|---------|---------|-------------|
| Host | `localhost` | TUI Parser server address |
| Port | `9600` | TUI Parser server port |
| Auto-connect | `true` | Connect on app launch |
| Reconnect delay | `3s` | Time between reconnection attempts |

### Display Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Font size | `14` | Terminal output font size |
| Theme | `dark` | Color scheme (dark only for now) |
| Scroll buffer | `10000` | Lines of history to keep |

## tmux Configuration

While PlexusOne Desktop works with default tmux settings, these options enhance the experience:

### Recommended ~/.tmux.conf

```bash
# Increase scrollback buffer
set -g history-limit 10000

# Enable mouse support (optional)
set -g mouse on

# Don't rename windows automatically
set -g allow-rename off

# Start window numbering at 1
set -g base-index 1
setw -g pane-base-index 1

# Show the Claude session name next to the tmux session name
set -g status-left '[#S]#{?@claude_name,[#{@claude_name}],} '
set -g status-left-length 40
```

PlexusOne Desktop turns on mouse mode for each session it attaches, so the
trackpad scrolls tmux history, unless **Settings > Sessions > Trackpad scrolls
conversation history** is off. The `@claude_name` option is kept up to date
while the app runs; see [Claude Sessions](../desktop/claude-sessions.md#claude-names-in-the-tmux-status-line).

### Session Naming

For better organization, name your sessions descriptively:

```bash
# Create named session
tmux new-session -s claude-main

# Or rename existing session
tmux rename-session -t 0 claude-main
```

PlexusOne Desktop displays session names in the pane headers, followed by the Claude session name when Claude Code runs in the session.

## File Locations

| Component | Location | Purpose |
|-----------|----------|---------|
| Desktop state | `~/.plexusone/state.json` | Window layouts and pane attachments |
| Claude session log | `~/.plexusone/claude-sessions.json` | What the app observed about each Claude session: tmux name, Claude name, how it ended |
| Claude hook events | `~/.plexusone/claude-session-events.jsonl` | Lines written by the optional Claude Code hook while the app is closed |
| Claude Code settings | `~/.claude/settings.json` | Holds the hook entries when the hook is installed; backed up to `settings.json.plexusone-backup` before each change |
| tmux sessions | `/tmp/tmux-$UID/` | tmux sockets |
| Mobile config | Device storage | App settings |

## Ports

| Service | Default Port | Protocol |
|---------|--------------|----------|
| TUI Parser HTTP | 9600 | HTTP |
| TUI Parser WebSocket | 9600 | WebSocket |

## Security

### Sensitive Data

PlexusOne Desktop does not store:

- Passwords or credentials
- API keys
- Session content/history

Terminal content is streamed in real-time and not persisted by PlexusOne Desktop (tmux handles its own scrollback).

### Network Security

- TUI Parser binds to all interfaces by default
- No authentication is implemented
- Use only on trusted networks
- Consider SSH tunneling for remote access
