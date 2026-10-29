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
| Repository | The repository the session worked in most, as `github.com/org/repo`, ranked by how many of the files it read or edited fall in each |
| Last Prompt | The last prompt you typed in the session |
| Cost | The session's cost as Claude Code last recorded it, usually at shutdown |
| Last Active | When anything last happened in the session |
| Session | The start of the Claude Code session ID |

Select a session to see its full ID, directory, branch, every repository it
read or edited near the end, its first and last prompts, and the command that
resumes it.

Filter by how recently a session was active, by state, or by searching the
subject, repository, tmux name, or ID.

## When a session needs you

When a Claude session starts waiting for you, for example at a permission
prompt, PlexusOne Desktop posts a notification such as *"github-com-8b in
tmux acad is waiting: permission prompt"*. Click it to go to that session.
Turn notifications off in **Settings > Sessions**.

The Dock icon shows how many sessions are waiting. **Window > Jump to Next
Waiting Session** (`⌘ J`) cycles through them.

Going to a session focuses the pane already showing it, in whichever window
it is; a window opens only when no pane shows it. Double-clicking a running
session in the list does the same.

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
reason, tmux names are only known for sessions the app has seen running, or
that the Claude Code hook recorded (see below).

The app keeps what it observes in `~/.plexusone/claude-sessions.json`.

## Renaming a session

Right-click a running session and choose **Rename Claude Session...**. The app
types `/rename <name>` into the session's pane, as if you had typed it. It is
available only while the session is idle at its prompt, so the command cannot
interrupt work; make sure the session's input box is empty.

## Recording sessions while PlexusOne is closed

By itself the app records a session's tmux name only while it is running. To
keep the mapping when it is not, install the Claude Code hook in **Settings >
Sessions > Install Hook**:

- It adds two hooks to `~/.claude/settings.json`, which run at the start of
  each Claude session and on every prompt. The file is backed up to
  `settings.json.plexusone-backup` first, and only the app's own entries are
  added or removed. The file is rewritten with sorted keys.
- Each hook run appends one line, with the session ID, directory, and tmux
  pane, to `~/.plexusone/claude-session-events.jsonl`. It prints nothing and
  never fails, and adds about a tenth of a second to each prompt.
- The app reads those lines into its session log when it next runs.
- The hooks apply to Claude sessions started after installing.

If you move the app, Settings shows **Update Hook** so the hooks point at the
new copy. **Remove Hook** takes them out again.

## Restoring sessions

Double-click a session, or select several and choose **Restore Sessions in New
Window**. A session that is running and already shown in a pane is focused
instead. For the others, a sheet asks which tmux session each one should run
in, filled in with the remembered name, or one made from its directory and ID.
Then, for each session:

- A running session in tmux is attached as it is.
- Otherwise `claude --resume <id>` is typed into a new shell in the session's
  directory: in a new window of that tmux session if it exists, or in a new
  tmux session with that name.

The restored sessions open together in a new window, one pane each, up to nine.

After a crash, a banner lists sessions that ended abnormally in the last 48
hours, with **Restore All**.

## After a crash or restart

When PlexusOne Desktop starts with saved windows, choose **Restore**. tmux
sessions the windows expect but that no longer exist are recreated first, by
resuming the Claude session that last ran in each under the same name. The
windows then open with their saved layouts, so the panes come back where they
were.
