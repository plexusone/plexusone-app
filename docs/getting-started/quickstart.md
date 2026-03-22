# Quick Start

Get up and running with Nexus in 5 minutes.

## Prerequisites

- macOS 14.0 or later
- tmux installed (`brew install tmux`)

## Step 1: Start Some Agent Sessions

Create a few tmux sessions for your AI agents:

```bash
# Create sessions for different agents
tmux new-session -d -s coder-1 "claude"
tmux new-session -d -s coder-2 "claude"
tmux new-session -d -s reviewer "claude"
```

Verify sessions are running:

```bash
tmux list-sessions
# coder-1: 1 windows (created ...)
# coder-2: 1 windows (created ...)
# reviewer: 1 windows (created ...)
```

## Step 2: Launch Nexus

Open the Nexus app:

```bash
open /Applications/Nexus.app
# Or from source: open apps/desktop/Nexus.app
```

You'll see the main window with an empty 2×1 grid layout.

## Step 3: Attach to Sessions

1. Click the **session dropdown** in the first pane (shows "Select...")
2. Choose `coder-1` from the list
3. The terminal output from that session appears in the pane

Repeat for the second pane with a different session.

## Step 4: Change the Layout

Click the **layout picker** in the toolbar (shows "2×1"):

- Select **3×2** for a 6-pane view
- Or choose **Custom...** for other configurations

## Step 5: Work with Your Agents

Now you can:

- **Monitor** multiple agents simultaneously
- **Switch sessions** using the dropdown in each pane header
- **Detach** a pane by clicking the ✕ button
- **Create new sessions** via the + button

## Session State

When you quit Nexus, your layout and pane assignments are saved.

On next launch, you'll be prompted:

> **Restore Previous Session?**
> Found a saved session from 5 minutes ago with 3×2 layout and 4 attached pane(s).

Click **Restore** to pick up where you left off.

## Next Steps

- [Grid Layout Guide](../guide/desktop/grid-layout.md) - Learn about layout configurations
- [Session Management](../guide/desktop/sessions.md) - Master session workflows
- [Keyboard Shortcuts](../guide/desktop/shortcuts.md) - Speed up your workflow

## Mobile Access (Optional)

To monitor agents from your phone:

1. Start the TUI Parser:
   ```bash
   cd services/tuiparser
   ./bin/tuiparser --port 9600
   ```

2. Find your Mac's IP address:
   ```bash
   ipconfig getifaddr en0
   # 192.168.1.100
   ```

3. On your phone, open Nexus Mobile and connect to `192.168.1.100:9600`

See the [Mobile Guide](../guide/mobile/overview.md) for details.
