# Grid Layout

The grid layout allows you to view multiple agent sessions simultaneously.

## Layout Presets

Click the layout picker in the toolbar to choose from presets:

| Preset | Panes | Best For |
|--------|-------|----------|
| 1×1 | 1 | Focused work |
| 2×1 | 2 | Side-by-side comparison |
| 3×1 | 3 | Three agents in a row |
| 2×2 | 4 | Quad view |
| 3×2 | 6 | Full team |
| 4×2 | 8 | Large projects |
| 3×3 | 9 | Maximum visibility |

## Custom Layouts

Select **Custom...** from the layout picker to create any configuration:

- **Columns**: 1-4
- **Rows**: 1-4

This gives you up to 16 panes.

## Pane Behavior

### Pane Numbering

Panes are numbered left-to-right, top-to-bottom:

```
┌─────┬─────┬─────┐
│  1  │  2  │  3  │
├─────┼─────┼─────┤
│  4  │  5  │  6  │
└─────┴─────┴─────┘
```

The pane number is shown in the header (e.g., `#1`).

### Empty Panes

Panes without attached sessions show:

- "No Session" message
- Quick session picker
- "New" button to create a session

### Pane Sizing

All panes are equal size. The grid divides available space evenly.

!!! note "Future Enhancement"
    Adjustable pane sizes are planned for a future release.

### Pane Terminal

A pane can show a second terminal below its coding session: a plain shell
(not tmux) that starts in the folder the session works in. Use it to look
at the files the agent is changing, run tests, or use git, without
leaving the pane.

Click the **terminal** icon in the pane header to show it, and again to
hide it. Hiding keeps the shell running, so its history and current
folder are still there when you show it again.

```
┌─────────────────────────────────┐
│ ● acad ▾           #1  >_  ↗  ✕ │  ← >_ shows or hides the terminal
│                                 │
│   Claude Code                   │
│                                 │
├─ ~/src/acad ──────────────── ⌄ ─┤  ← drag to resize; ⌄ hides
│ ~/src/acad $ git status         │
└─────────────────────────────────┘
```

- **Starting folder**: where the Claude session in the pane started, or
  otherwise the current folder of the tmux pane. The bar above the shell
  shows it.
- **Resize**: drag the bar up or down.
- **Focus**: click the shell to type in it. `⌘ ]` and `⌘ [` move through
  each pane's session and its shell.
- **One per session**: switching the pane to another session shows that
  session's shell instead; switching back returns to the first.
- **When it ends**: typing `exit` closes the shell. It also ends when its
  tmux session ends or the window closes. Shells are not restored when the
  app restarts.

## Layout Changes

### Reducing Panes

When you switch to a smaller layout:

- **Sessions are preserved** - they keep running
- **Extra panes are hidden** - sessions detach but don't stop
- **State is maintained** - switch back and they're still there

Example: Going from 3×2 (6 panes) to 2×1 (2 panes):

- Panes 1-2 remain visible
- Panes 3-6 sessions detach but keep running
- Switching to 3×2 doesn't restore assignments (start fresh)

### Expanding Panes

When you switch to a larger layout:

- **Existing assignments stay** - panes 1-N remain attached
- **New panes are empty** - ready for new sessions

## Layout Persistence

Your layout choice is saved automatically:

```json
// ~/.plexusone/state.json
{
  "gridColumns": 3,
  "gridRows": 2,
  "paneAttachments": {
    "1": "coder-1",
    "2": "coder-2",
    "4": "reviewer"
  }
}
```

On restart, you're prompted to restore this configuration.

## Tips

!!! tip "Match Layout to Screen Size"
    - **Laptop**: 2×1 or 2×2
    - **External monitor**: 3×2 or larger
    - **Ultra-wide**: 4×1 or 4×2

!!! tip "Use Layouts for Workflows"
    Save different layouts mentally for different tasks:
    - **Development**: 3×1 (code, test, review)
    - **Debugging**: 2×2 (code, logs, db, terminal)
    - **Monitoring**: 4×2 (all agents visible)
