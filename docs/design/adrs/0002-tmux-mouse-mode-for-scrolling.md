# ADR 0002: tmux mouse mode for trackpad scrolling

**Status:** Accepted

## Context

With tmux mouse mode off, tmux keeps the outer terminal on its alternate
screen, which has no scrollback. SwiftTerm, like other terminals, then
sends the scroll wheel as Up/Down keys (alternate scroll mode). In Claude
Code those keys step through past prompts, so the trackpad could not
scroll back through a conversation.

## Decision

When a pane attaches to a tmux session, the app sets mouse mode for that
session only (`set-option -t =name: mouse on`). The wheel is then
reported to tmux, which scrolls the pane's history in copy mode. A
setting turns this off; when off, the app removes the session's own value
(`set-option -u`) so the user's global tmux setting applies.

## Consequences

- The trackpad scrolls the conversation; Up/Down keys still navigate
  prompt history.
- Dragging selects inside tmux. Holding Shift bypasses mouse reporting
  for a normal terminal selection.
- The option belongs to the tmux session, so the same session opened in
  another terminal also has mouse mode on.
- The user's `~/.tmux.conf` and sessions never shown in the app are
  unaffected.

## Alternatives considered

- **Scroll depending on the pointer or the last click** (prompt history
  over the input box, conversation elsewhere). Rejected: it needs a guess
  at the input box's extent and more state for little gain over the
  arrow keys.
