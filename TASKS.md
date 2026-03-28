# Nexus Tasks

## Open

### Desktop App

- [ ] **Scroll position indicator**: Display line position (e.g., "123/615") while scrolling through terminal scrollback. Shows current position relative to total lines.

- [ ] **macOS app icon**: Create a polished, "glassy" macOS-friendly icon for PlexusOne/Nexus. Should follow Apple HIG with proper squircle shape, gradients, and depth effects.

- [ ] **Scrollbar visibility**: Verify scrollbar thumb appears and is draggable when there's scrollback content (native scrollback, not tmux).

## Completed

### Desktop App

- [x] **Terminal trackpad scrolling**: Fixed two-finger trackpad scrolling by sending mouse wheel escape sequences (button 64/65) to terminal applications like tmux. Updated SwiftTerm to main branch for NSScroller Auto Layout fix. (2026-03-28)
