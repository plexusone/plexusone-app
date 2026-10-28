# ADR 0001: Detecting how a Claude Code session ended

**Status:** Accepted

## Context

After a crash or restart, tmux sessions are gone but Claude Code
transcripts survive, so any conversation can be resumed. The Claude
Sessions window needs to say which sessions ended abnormally and which
tmux session each ran in.

Claude Code was observed to behave as follows on each exit path:

| Exit | Live-process record (`~/.claude/sessions/<pid>.json`) | Transcript ends with `cost-state` |
|------|------|------|
| `/exit` | deleted | yes |
| tmux or terminal closed (SIGHUP) | deleted | yes |
| `kill -9`, crash, power loss | left behind | no |

The `cost-state` shutdown record appears from Claude Code 2.1.286. The
live-process record carries the tmux pane (`session:@window.%pane`), but
Claude Code removes stale records after a restart. Neither file is a
documented interface.

## Decision

Classify each session from the strongest available evidence:

1. A live-process record whose process is alive and started when the
   record says → **running**.
2. What the app observed (it polls every 5 seconds): Claude stopped while
   its tmux pane stayed open → **exited normally**; the pane, session, or
   server closed with it → **tmux/terminal closed**; seen running before
   the last boot → **system shutdown**.
3. A live-process record left behind by a dead process → **crashed** or,
   if the machine has booted since, **system shutdown**.
4. The transcript: a trailing shutdown record → **ended cleanly**; none,
   on a version that writes one → **system shutdown** if the machine has
   booted since, else **ended abnormally**; older versions → **unknown**.

The app persists its observations, including tmux names, in
`~/.plexusone/claude-sessions.json`.

## Consequences

- `/exit` and a closed terminal can only be told apart while the app is
  running; otherwise both show as "ended cleanly".
- tmux names are known only for sessions the app has seen running.
- The classification depends on undocumented Claude Code files, verified
  against 2.1.309. A change there degrades results to "unknown" rather
  than failing.

## Alternatives considered

- **Shell out to an external session catalog.** It would avoid parsing
  transcripts in Swift, but would make the app depend on a separately
  installed tool, and it does not track tmux names or exit causes.
- **Claude Code hooks.** A hook on each prompt could record bindings
  without the app running, but needs per-user hook setup.
