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

### Settings

Open **PlexusOne Desktop > Settings...** (`⌘,`).

| Tab | Setting | Default | Effect |
|-----|---------|---------|--------|
| General | Pane terminal height | 35% | Share of the pane the [pane terminal](../desktop/grid-layout.md#pane-terminal) takes. Panes you have not resized follow changes at once |
| Appearance | Font Size | 13 pt | Font size of every terminal, including open ones |
| Sessions | Idle after / Stuck after | 30 s / 120 s | Time without output before a session shows as idle, then stuck |
| Sessions | Record Claude sessions while PlexusOne is closed | Off | **Install Hook** adds the [Claude Code hook](../desktop/claude-sessions.md#recording-sessions-while-plexusone-is-closed); **Update Hook** and **Remove Hook** appear once installed |
| Sessions | Notify when a Claude session needs you | On | Posts a notification when a Claude session starts waiting. The Dock badge and `⌘J` work either way |
| Sessions | Trackpad scrolls conversation history | On | Turns on tmux mouse mode for each session the app attaches, so the trackpad scrolls tmux history. Off leaves your own tmux setting. Applies the next time a session is attached |

New tmux sessions use tmux's `default-shell`, normally your login shell.
The pane terminal uses your login shell (`$SHELL`).

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
| `--host` | `127.0.0.1` | Address to listen on. A non-loopback address (for example `0.0.0.0` or a Tailscale IP) requires a token |
| `--port` | `9600` | HTTP/WebSocket server port |
| `--token` | (empty) | Token clients must present on `/ws`. Falls back to `TUIPARSER_TOKEN` |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `TUIPARSER_TOKEN` | Token clients must present, used when `--token` is empty. Preferred over `--token`, which other local users can see in the process list |

If `--host` is not a loopback address and no token is set, TUI Parser refuses
to start and prints a randomly generated token you can use.

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
| Token | (empty) | Token the server was started with; sent as the `token` query parameter |
| Use TLS | off | Flutter only: connect with `wss://` (for a TLS-terminating proxy). The iOS app takes a full `ws://` or `wss://` URL instead of host and port |
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

Any client connected to TUI Parser can send keystrokes to your tmux sessions,
which amounts to running commands as you. TUI Parser therefore:

- Listens on `127.0.0.1` by default
- Refuses to listen on a non-loopback address without a token
- Requires the token on `/ws`, as `Authorization: Bearer <token>` or a
  `token` query parameter, compared in constant time, and answers
  `401 Unauthorized` before the WebSocket upgrade otherwise
- Accepts WebSocket requests with no `Origin` header (native apps) or an
  `Origin` matching the request host, so other web pages cannot connect from
  your browser
- Leaves `/health` and the static debug console page open; neither shows
  session data. Open the console as `http://<host>:9600/?token=<token>` when a
  token is set

Traffic is not encrypted. For remote access, prefer Tailscale (listen on the
Tailscale address with a token) or an SSH tunnel to the default loopback
listener, and never expose the port to the internet.
