# Keyboard Shortcuts

Keyboard shortcuts for efficient navigation and control.

## Application Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘ N` | New session |
| `⌘ R` | Refresh sessions |
| `⌘ ,` | Open settings |
| `⌘ Q` | Quit Nexus |

## Window Management

| Shortcut | Action |
|----------|--------|
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

Since Nexus attaches to tmux sessions, tmux shortcuts work:

| Shortcut | Action |
|----------|--------|
| `Ctrl B d` | Detach from session (use Nexus detach instead) |
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

## Planned Shortcuts

Future versions will add:

| Shortcut | Action |
|----------|--------|
| `⌘ 1-9` | Focus pane by number |
| `⌘ [` | Previous pane |
| `⌘ ]` | Next pane |
| `⌘ Shift N` | New window |
| `⌘ T` | New pane in current window |

## Customization

Keyboard shortcuts are not yet customizable. This feature is planned for a future release.

To request a shortcut, open an issue on [GitHub](https://github.com/plexusone/nexus/issues).
