# Mobile App Overview

The PlexusOne Mobile app provides remote access to your AI agent sessions from iOS and Android devices.

## Status

!!! warning "Early Development"
    The mobile app is in early development. Features described here represent the planned functionality.

## Features

### Remote Session Monitoring

- View terminal output from any active session
- Real-time streaming via WebSocket
- Scrollable history with terminal styling

### Session Interaction

- Send keystrokes to active sessions
- Navigate TUI menus with virtual D-pad
- Quick action buttons for common operations

### Multi-Session Support

- View all active sessions
- Switch between sessions with tabs
- Session status indicators (running, idle, error)

## Architecture

The mobile app connects to the TUI Parser service running on your desktop:

```
┌─────────────┐     WebSocket      ┌─────────────┐
│  Mobile App │ ◄─────────────────► │ TUI Parser  │
│  (Flutter)  │    :9600/ws        │    (Go)     │
└─────────────┘                    └──────┬──────┘
                                          │ PTY
                                   ┌──────▼──────┐
                                   │    tmux     │
                                   │  sessions   │
                                   └─────────────┘
```

## Platforms

| Platform | Status |
|----------|--------|
| iOS | Planned |
| Android | Planned |
| Web | Not planned |

## Limitations

Current limitations of the mobile app:

- **Local network only** - Must be on the same network as the desktop
- **No offline mode** - Requires active connection to TUI Parser
- **Read-heavy** - Optimized for monitoring, not heavy typing
- **Single server** - Connects to one TUI Parser instance at a time

## Use Cases

### Monitoring Long-Running Tasks

Start a task on your desktop and monitor progress from your phone while away from your desk.

### Quick Interventions

Respond to agent prompts that require simple input (yes/no, menu selection) without returning to your computer.

### Status Checks

Quickly check if your agents are still running or have completed their tasks.

## Requirements

To use the mobile app, you need:

1. **TUI Parser running** - Start with `tuiparser` command on desktop
2. **Network access** - Mobile device must reach desktop on port 9600
3. **Active sessions** - At least one tmux session to monitor

## Next Steps

- [Connecting to Desktop](connecting.md) - Set up the connection
