# Keyboard Shortcuts

Keyboard shortcuts for efficient navigation and control.

## Application Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘ N` | New session |
| `⌘ R` | Refresh sessions |
| `⌘ ,` | Open settings |
| `⌘ Q` | Quit PlexusOne Desktop |

## Window Management

| Shortcut | Action |
|----------|--------|
| `⌘ ⇧ N` | New window |
| `⌘ ⇧ S` | Claude Sessions window |
| `⌥ ⌘ A` | Attach a session to the focused pane |
| `⌘ ⇧ A` | Detach the focused pane |
| `⌘ ]` / `⌘ [` | Next / previous pane |
| `⌘ J` | Jump to the next Claude session waiting for you |
| `⌘ M` | Minimize window |
| `⌘ W` | Close window |
| `⌘ 1-9` | Switch to pane 1-9 (planned) |

## Terminal Interaction

When a pane is focused, standard terminal shortcuts work:

| Shortcut | Action |
|----------|--------|
| `⌘ C` | Copy selection |
| `⌘ V` | Paste |
| `⌘ K` | Clear terminal (in some shells) |
| `Ctrl C` | Interrupt current command |
| `Ctrl D` | Send EOF / exit |

## tmux Passthrough

Since PlexusOne Desktop attaches to tmux sessions, tmux shortcuts work:

| Shortcut | Action |
|----------|--------|
| `Ctrl B d` | Detach from session (use PlexusOne Desktop detach instead) |
| `Ctrl B [` | Enter scroll mode |
| `Ctrl B ]` | Paste buffer |

!!! note "tmux Prefix"
    Default tmux prefix is `Ctrl B`. If you've customized it, your prefix applies.

## Scrolling

| Shortcut | Action |
|----------|--------|
| Scroll wheel | Scroll terminal output |
| `Page Up` | Scroll up one page |
| `Page Down` | Scroll down one page |
| `⌘ ↑` | Scroll to top |
| `⌘ ↓` | Scroll to bottom |

!!! note "Scrolling inside tmux"
    PlexusOne Desktop turns on tmux mouse mode for each session it attaches,
    so the trackpad scrolls back through the session's history. In Claude
    Code, use `↑` and `↓` to step through past prompts. Hold `Shift` while
    dragging to select text normally. To keep your own tmux mouse setting,
    turn off **Settings > Sessions > Trackpad scrolls conversation history**.

## Planned Shortcuts

Future versions will add:

| Shortcut | Action |
|----------|--------|
| `⌘ 1-9` | Focus pane by number |
| `⌘ [` | Previous pane |
| `⌘ ]` | Next pane |
| `⌘ T` | New pane in current window |

## Customization

Keyboard shortcuts are not yet customizable. This feature is planned for a future release.

To request a shortcut, open an issue on [GitHub](https://github.com/plexusone/plexusone-app/issues).
