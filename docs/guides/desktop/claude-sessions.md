# Claude Sessions

The Claude Sessions window lists your Claude Code sessions, where each one ran,
what it was about, and how it ended. Use it to bring sessions back after a crash
or restart.

Open it with **File > Claude Sessions...** (`⌘ ⇧ S`) or the list button in a
window's toolbar.

## What the list shows

| Column | Meaning |
|--------|---------|
| State | Running, with Claude's live status (`busy`, `idle`, or what it is waiting for, such as `waiting: permission prompt`), or how the session ended (see below) |
| tmux | The tmux session Claude ran in, if known |
| Claude Name | Claude Code's own name for the session, such as `github-com-8b`. Sessions use this name to address each other |
| Subject | Claude's title for the session, else the first prompt |
| Repository | The git repository of the session's directory, as `github.com/org/repo` |
| Last Active | When anything last happened in the session |
| Session | The start of the Claude Code session ID |

Select a session to see its full ID, directory, branch, every repository it
read or edited near the end, its first and last prompts, and the command that
resumes it.

Filter by how recently a session was active, by state, or by searching the
subject, repository, tmux name, or ID.

## Claude names in panes

Each pane's header shows the Claude name of the session running in it, after
the tmux session name. When the session is waiting for you, for example at a
permission prompt, an orange badge says what it is waiting for.

Claude Code names a session after the directory it started in and may rename
it later; the header follows the change within a few seconds.

## Claude names in the tmux status line

While PlexusOne Desktop runs, it keeps a tmux option, `@claude_name`, on each
tmux session equal to the Claude name running in it, and removes it when the
session ends. tmux's own status line can show it. Add these lines to
`~/.tmux.conf`:

```tmux
set -g status-left '[#S]#{?@claude_name,[#{@claude_name}],} '
set -g status-left-length 40
```

Then reload with `tmux source-file ~/.tmux.conf`. The status line reads
`[acad][github-com-8b]`; a tmux session without Claude shows just `[acad]`.
The length setting matters: tmux's default of 10 characters cuts the name off.

These lines change the status line in every tmux client, including other
terminals, so the app does not apply them for you. If PlexusOne Desktop is
not running, `@claude_name` is not updated, so a renamed or ended session can
show its old name until the app runs again.

## How a session ended

| State | Meaning |
|-------|---------|
| Running | Claude Code is running |
| Exited normally | Claude exited while its tmux pane stayed open, for example with `/exit` or Ctrl+C |
| tmux/terminal closed | The tmux pane, session, or server closed while Claude was running in it |
| System shutdown | Claude was still running when the machine shut down, restarted, or crashed |
| Crashed/killed | The Claude process died without cleaning up |
| Ended cleanly | Claude shut down cleanly while PlexusOne Desktop was not running, so it could not tell `/exit` from a closed terminal |
| Ended abnormally | Claude did not record a clean shutdown and the machine has not restarted since |
| Unknown | The session predates Claude Code versions that record a clean shutdown |

Claude Code's own files show whether it shut down cleanly, but a closed
terminal looks the same as `/exit` there. PlexusOne Desktop tells them apart by
watching while it runs: if Claude stops and its tmux pane is still open, you
exited; if the pane went away too, the terminal or tmux closed. For the same
reason, tmux names are only known for sessions the app has seen running.

The app keeps what it observes in `~/.plexusone/claude-sessions.json`.

## Restoring sessions

Double-click a session, or select several and choose **Restore Sessions in New
Window**. For each session:

- A running session in tmux is attached as it is.
- Otherwise `claude --resume <id>` is typed into a new shell in the session's
  directory: in a new window of its remembered tmux session if that session
  still exists, or in a new tmux session with the remembered name. A session
  with no remembered name gets one made from its directory and ID.

The restored sessions open together in a new window, one pane each, up to nine.

After a crash, a banner lists sessions that ended abnormally in the last 48
hours, with **Restore All**.
