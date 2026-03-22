# Configuration

Configuration options for Nexus components.

## Desktop App

### State File

The desktop app stores session state in:

```
~/.plexusone/nexus_state.json
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

On startup, if a state file exists, Nexus prompts:

> "Restore previous session?"
>
> [Restore] [Start Fresh]

- **Restore** - Reattaches to saved sessions if they still exist
- **Start Fresh** - Ignores saved state, starts with empty panes

### Reset Configuration

To reset to defaults, delete the state file:

```bash
rm ~/.plexusone/nexus_state.json
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

While Nexus works with default tmux settings, these options enhance the experience:

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
```

### Session Naming

For better organization, name your sessions descriptively:

```bash
# Create named session
tmux new-session -s claude-main

# Or rename existing session
tmux rename-session -t 0 claude-main
```

Nexus displays session names in the pane headers.

## File Locations

| Component | Location | Purpose |
|-----------|----------|---------|
| Desktop state | `~/.plexusone/nexus_state.json` | Session state |
| tmux sessions | `/tmp/tmux-$UID/` | tmux sockets |
| Mobile config | Device storage | App settings |

## Ports

| Service | Default Port | Protocol |
|---------|--------------|----------|
| TUI Parser HTTP | 9600 | HTTP |
| TUI Parser WebSocket | 9600 | WebSocket |

## Security

### Sensitive Data

Nexus does not store:

- Passwords or credentials
- API keys
- Session content/history

Terminal content is streamed in real-time and not persisted by Nexus (tmux handles its own scrollback).

### Network Security

- TUI Parser binds to all interfaces by default
- No authentication is implemented
- Use only on trusted networks
- Consider SSH tunneling for remote access
