# ADR 0003: Recording sessions with a Claude Code hook

**Status:** Accepted

## Context

The app learns which tmux session each Claude Code session runs in by
reading Claude Code's live-process records while it runs (ADR 0001). A
session that starts and ends while the app is closed, including one ended by
a crash, is never recorded, and after a restart Claude Code removes the
records that would have named its tmux session.

## Decision

Offer an opt-in Claude Code hook that records sessions without the app
running:

- The app executable has a command mode, `PlexusOneDesktop claude-hook`.
  Claude Code runs it from a `SessionStart` and a `UserPromptSubmit` hook. It
  reads the hook input on stdin (`session_id`, `cwd`, `hook_event_name`),
  finds the tmux pane from `$TMUX_PANE`, and appends one JSON line to
  `~/.plexusone/claude-session-events.jsonl` with a single append write.
- It prints nothing, because Claude Code adds the output of these hooks to
  the conversation, and always exits 0, so it cannot block or alter a prompt.
- The app folds new lines into its observation log on each check, tracking
  how far it has read. A session the app is already watching only gains a
  missing tmux location, so its observed exit is not disturbed.
- Settings installs, updates, and removes the hooks in
  `~/.claude/settings.json`, touching only its own entries, after backing the
  file up and keeping its permissions.

## Consequences

- tmux names survive crashes even when the app was not running.
- Each prompt waits about 0.1 seconds for the hook (measured with a release
  build; most of it is the tmux lookup).
- Rewriting `settings.json` sorts its keys and changes its formatting; the
  backup keeps the original.
- The hook command names the app's path. Moving the app breaks it until
  Settings updates it, and Settings shows when that is needed.

## Alternatives considered

- **A background agent** polling like the app does. More moving parts, and
  it still would not see a session that starts and crashes between polls.
- **A shell script hook.** Parsing JSON reliably in a shell needs a tool such
  as `jq` that may not be installed; the app binary is always present.
