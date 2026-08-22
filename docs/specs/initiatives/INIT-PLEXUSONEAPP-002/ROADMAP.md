# ROADMAP — Terminal Pane Focus and Input Routing

**Initiative:** `INIT-PLEXUSONEAPP-002`
**Repository:** `github.com/plexusone/plexusone-app`

## Phase 1 — Focus-Click Isolation
**Theme:** A click that only moves focus between panes must never be forwarded into the terminal

- [x] `RMI-PLEXUSONEAPP-009` Fix accidental mouse-report forwarding on pane focus-switch clicks
  - Delivered: `TerminalContainerView` overrides `hitTest(_:)` to claim the hit for itself while a pane is unfocused, instead of letting AppKit route the click directly to the terminal subview (which forwards it to the PTY as a mouse report when `allowMouseReporting && terminal.mouseMode.sendButtonPress()`). `mouseDown(with:)` on an unfocused pane now only moves focus.
  - Acceptance: clicking directly on the first option of a visible Claude Code Yes/No prompt in an unfocused pane moves focus only and does not select/execute anything; a click on an already-focused pane behaves exactly as before (text selection, mouse reporting).
