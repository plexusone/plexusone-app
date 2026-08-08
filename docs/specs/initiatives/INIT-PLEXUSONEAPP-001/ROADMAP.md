# Desktop Terminal Scrolling & Rendering Performance — Roadmap

**Initiative:** `INIT-PLEXUSONEAPP-001`
**Repository:** `github.com/plexusone/plexusone-app`
**Status:** Phase 1 in progress

> RMI IDs are stable and permanent. Commits implementing an item carry the trailer `Refs: RMI-<REPOSLUG>-<NNN>`. Phase status is derived from member RMIs — a phase is complete only when all its required RMIs are complete.

## Phase 1 — Scroll Integration Fixes

**Theme:** Remove double-dispatch and smooth trackpad scrolling
**Status:** In progress — 2 of 4 items completed

- [ ] `RMI-PLEXUSONEAPP-001` Remove double-dispatched scroll path (NSEvent monitor + custom wheel handler)
  - Delete the app-wide NSEvent.addLocalMonitorForEvents scroll monitor and Coordinator.handleScrollEvent in TerminalViewRepresentable.swift, the custom AppTerminalView.handleMouseWheelEvent, and the TerminalContainerView.scrollWheel forward. SwiftTerm's built-in scrollWheel already handles mouse reporting, alternate-screen conversion, and native scrollback; the current setup processes every wheel event twice and installs one app-wide monitor per pane.
- [ ] `RMI-PLEXUSONEAPP-002` Fractional scroll-delta accumulation for trackpad smoothness
  - SwiftTerm's scrollWheel truncates event.deltaY to whole lines and drops small fractional trackpad deltas, causing steppy scrolling. Accumulate fractional deltas in the AppTerminalView subclass and emit line scrolls when the accumulator crosses a cell height. Consider upstreaming to SwiftTerm.
- [x] `RMI-PLEXUSONEAPP-003` Stable Session identity across 5s refresh cycles
  - SessionManager.parseSessionOutput mints a new UUID for every Session on every refresh, breaking SwiftUI ForEach identity and the session-picker checkmark, and forcing needless view rebuilds. Derive identity deterministically from the tmux session name.
- [x] `RMI-PLEXUSONEAPP-004` Pin SwiftTerm to a fixed revision instead of branch main
  - Package.swift tracks SwiftTerm branch main, an unpinned moving target whose perf characteristics can shift under us. Pin to a specific revision (currently b6ce28a) or tagged release.

## Phase 2 — Rendering & Measurement

**Theme:** Enable Metal renderer and profile before/after
**Status:** Planned — 0 of 2 items completed

- [ ] `RMI-PLEXUSONEAPP-005` Enable SwiftTerm Metal renderer with CoreGraphics fallback
  - The pinned SwiftTerm revision ships MetalTerminalRenderer (glyph atlas + GPU quads) behind setUseMetal(true), which the app never calls. Enable it after the view is added to a window, falling back to CoreGraphics if MetalError is thrown.
- [ ] `RMI-PLEXUSONEAPP-006` Profile heavy-output scrolling with Instruments (baseline vs Metal)
  - No profiling data exists behind the Rust-migration discussion. Capture Instruments time-profiles during heavy AI-agent output bursts and sustained scrolling, before and after the phase-1 fixes and Metal enablement. Decide whether SwiftTerm core (parser/buffer) is a real bottleneck; only then revisit the alacritty_terminal FFI option from IDEATION_CHAT_RUST.md.

## Phase 3 — tmux Strategy

**Theme:** Mouse mode now, control mode (-CC) evaluation for native scrollback
**Status:** Planned — 0 of 2 items completed

- [ ] `RMI-PLEXUSONEAPP-007` Enable tmux mouse mode for app-created sessions
  - Sessions attach via tmux attach on the alternate screen, so wheel events degrade to arrow keys and SwiftTerm's 10k scrollback goes unused. Set mouse mode (set -g mouse on) for sessions the app creates so scrolling enters copy-mode smoothly.
- [ ] `RMI-PLEXUSONEAPP-008` Evaluate tmux control mode (-CC) integration for native scrollback
  - iTerm2-class fluidity (native scrollback over tmux history, no copy-mode round-trip) requires speaking the tmux control-mode protocol and owning the buffer in-app. Scope the protocol work in Swift, estimate effort, and prototype attach/detach with one session. This is the feature that defines professional-grade for a tmux orchestrator; it is protocol work, not a rendering rewrite.
