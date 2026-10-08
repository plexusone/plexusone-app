# ROADMAP — Terminal Pane Focus and Input Routing

**Initiative:** `INIT-PLEXUSONEAPP-002`
**Repository:** `github.com/plexusone/plexusone-app`

## Phase 1 — Focus-Click Isolation
**Theme:** A click that only moves focus between panes must never be forwarded into the terminal

- [x] `RMI-PLEXUSONEAPP-009` Fix accidental mouse-report forwarding on pane focus-switch clicks
  - Delivered: `TerminalContainerView` overrides `hitTest(_:)` to claim the hit for itself while a pane is unfocused, instead of letting AppKit route the click directly to the terminal subview (which forwards it to the PTY as a mouse report when `allowMouseReporting && terminal.mouseMode.sendButtonPress()`). `mouseDown(with:)` on an unfocused pane now only moves focus.
  - Acceptance: clicking directly on the first option of a visible Claude Code Yes/No prompt in an unfocused pane moves focus only and does not select/execute anything; a click on an already-focused pane behaves exactly as before (text selection, mouse reporting).

## Phase 2 — Installable Releases
**Theme:** A fix that ships but cannot be installed is not released

- [ ] `RMI-PLEXUSONEAPP-010` Ad-hoc code-sign release app bundles before packaging
  - The release workflow copied the binary and Info.plist into a bundle and never ran `codesign`, so artifacts carried only the linker's automatic signature. On a quarantined download Gatekeeper reports the thin builds as "damaged" (invalid signature, no escape hatch) and the universal build as unverified. Sign the whole bundle ad-hoc in both build jobs and verify it, so every artifact gets the standard "Open Anyway" path.
  - Acceptance: a freshly downloaded v0.5.2 DMG installs and opens via System Settings > Privacy & Security > Open Anyway on macOS 15 for all three artifacts; none reports "damaged".
- [ ] `RMI-PLEXUSONEAPP-011` Developer ID signing and notarization
  - Sign with a Developer ID Application certificate from repository secrets (`--options runtime --timestamp`), submit the DMG with `xcrun notarytool submit --wait`, and staple the ticket, so first launch needs no Gatekeeper prompt. Requires an Apple Developer Program membership.
  - Depends on: `RMI-PLEXUSONEAPP-010`
