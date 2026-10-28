# Multi-Window Support

PlexusOne Desktop supports multiple windows, each with its own independent grid layout while sharing the same session pool.

## Overview

With multi-window support, you can:

- Open multiple PlexusOne Desktop windows
- Configure different grid layouts per window (e.g., 3×2 on one monitor, 2×1 on another)
- View the same sessions across windows
- Have each window persist its layout independently

## Architecture

```
                    AppState (Singleton)
                    ├── SessionManager (shared)
                    └── WindowStateManager (tracks all windows)
                              │
            ┌─────────────────┴─────────────────┐
            │                                   │
    Window A (UUID)                     Window B (UUID)
    ├── paneManager (local)             ├── paneManager (local)
    └── gridConfig (local)              └── gridConfig (local)
```

### Shared vs Local State

| Component | Scope | Description |
|-----------|-------|-------------|
| `SessionManager` | Shared | Sessions are shared across all windows |
| `gridConfig` | Per-window | Each window has its own grid layout |
| `paneManager` | Per-window | Each window has its own pane-to-session mappings |
| `WindowStateManager` | Shared | Tracks all window configurations for persistence |

## Usage

### Opening New Windows

Use any of these methods:

- **Menu**: File → New Window
- **Keyboard**: `Cmd+Shift+N`
- **Pop-out**: Click the pop-out icon (↗) in any pane header

Each new window starts with a default 2×1 layout and can be configured independently.

### Pop-Out Sessions

Pop out a session to a dedicated 1×1 window without disrupting your grid:

1. Find the session in any pane
2. Click the **pop-out icon** (↗) next to the detach button (✕)
3. A new window opens with just that session

The original pane keeps the session attached, giving you two views of the same tmux session. This is useful when you need:

- Full-screen space for one agent while monitoring others
- The same session visible on multiple monitors
- Side-by-side comparison of the same session at different scroll positions

### Independent Layouts

Configure each window's layout independently:

1. Window A: Set to 3×2 layout for monitoring multiple agents
2. Window B: Set to 1×1 layout for focused work

Changes to one window's layout don't affect other windows.

### Session Synchronization

Sessions are shared across all windows:

- Create a session in Window A → it appears in Window B's session dropdown
- Kill a session from any window → it's removed everywhere
- Sessions refresh automatically every 5 seconds

### Closing Windows

- Click the red close button to close a single window
- Other windows remain open
- The app continues running even if all windows are closed (tmux sessions persist)

## Persistence

### State File

All window configurations are saved to:

```
~/.plexusone/state.json
```

### State Format (v2)

```json
{
  "windows": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "gridColumns": 3,
      "gridRows": 2,
      "paneAttachments": {
        "1": "claude-main",
        "2": "reviewer"
      },
      "frame": {
        "x": 100,
        "y": 100,
        "width": 1200,
        "height": 800
      }
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "gridColumns": 2,
      "gridRows": 1,
      "paneAttachments": {
        "1": "tests"
      }
    }
  ],
  "savedAt": "2024-03-28T12:00:00Z",
  "version": 2
}
```

### Restoration

On app launch:

1. If saved state exists, you're prompted to restore
2. Click "Restore" to restore all windows with their layouts
3. Click "Start Fresh" to start with a single default window

### Migration

Existing v1 state files (single-window format) are automatically migrated to v2 (multi-window format) on first load.

## Workflows

### Multi-Monitor Setup

Use multiple windows across monitors:

1. Open PlexusOne Desktop (Window 1 appears)
2. Press `Cmd+Shift+N` to open Window 2
3. Drag Window 2 to your second monitor
4. Configure each window's layout for its monitor size

### Agent Team + Focus Mode

Run a team of agents while keeping a focus window:

1. **Window 1** (3×2 layout): Monitor all agents
2. **Window 2** (1×1 layout): Focus on the current active task

Both windows share the same sessions, so you can switch between monitoring and focus modes.

## Tips

!!! tip "Use Descriptive Window Layouts"
    Configure layouts based on the monitor size and your workflow. A 4×2 layout works great on an ultrawide monitor.

!!! tip "Session Changes Sync Instantly"
    Create, rename, or kill sessions from any window. Changes propagate immediately to all windows.

!!! tip "Each Window is Independent"
    Closing one window doesn't affect others. Your work in other windows continues uninterrupted.

!!! tip "Pop Out for Focus"
    Use the pop-out button (↗) to expand a session to its own window without changing your grid layout. Great for when you need temporary full-screen access.
