import Foundation

/// How a Claude Code session ended, or that it is still running.
///
/// Claude Code's own files separate a clean shutdown from a crash or kill, but
/// not `/exit` from a closed terminal: both delete the live-process record and
/// write a final `cost-state` record. The app tells those two apart by
/// watching: if Claude stops while its tmux pane stays open, the user exited;
/// if the pane goes away with it, the terminal or tmux was closed.
enum SessionEndState: String, Codable, Hashable, CaseIterable {
    /// The Claude process is alive.
    case running
    /// Observed: Claude exited while its tmux pane stayed open (`/exit`, Ctrl+C, Ctrl+D).
    case exited
    /// Observed: Claude's tmux pane, session, or server closed with it.
    case tmuxClosed
    /// It was running when the machine shut down, restarted, or crashed.
    case systemShutdown
    /// The process died without cleaning up (killed or crashed).
    case crashed
    /// A clean shutdown was recorded, but the app did not see whether it was
    /// `/exit` or a closed terminal.
    case endedCleanly
    /// No clean shutdown was recorded: likely a crash, kill, or power loss.
    case endedAbnormally
    /// Too old to tell: Claude Code versions before shutdown records.
    case unknown

    var displayName: String {
        switch self {
        case .running: return "Running"
        case .exited: return "Exited normally"
        case .tmuxClosed: return "tmux/terminal closed"
        case .systemShutdown: return "System shutdown"
        case .crashed: return "Crashed/killed"
        case .endedCleanly: return "Ended cleanly"
        case .endedAbnormally: return "Ended abnormally"
        case .unknown: return "Unknown"
        }
    }

    var explanation: String {
        switch self {
        case .running:
            return "Claude Code is running."
        case .exited:
            return "Claude exited while its tmux pane stayed open, for example with /exit or Ctrl+C."
        case .tmuxClosed:
            return "The tmux pane, session, or server closed while Claude was running in it."
        case .systemShutdown:
            return "Claude was still running when the machine shut down, restarted, or crashed: it never shut down cleanly, and the machine has booted since."
        case .crashed:
            return "The Claude process died without cleaning up, for example it was killed or crashed."
        case .endedCleanly:
            return "Claude shut down cleanly. PlexusOne was not running, so it could not see whether this was /exit or a closed terminal."
        case .endedAbnormally:
            return "Claude did not record a clean shutdown and the machine has not restarted since, so the process was likely killed or crashed."
        case .unknown:
            return "This session predates the shutdown records Claude Code writes, so how it ended is unknown."
        }
    }

    /// true for a normal ending, false for an abnormal one, nil when unclear.
    var isNormalEnding: Bool? {
        switch self {
        case .exited: return true
        case .tmuxClosed, .systemShutdown, .crashed, .endedAbnormally: return false
        case .running, .endedCleanly, .unknown: return nil
        }
    }
}

/// Where a tmux pane is: `session:@window.%pane`, as Claude Code records it.
struct TmuxTarget: Codable, Hashable {
    let sessionName: String
    let windowId: String
    let paneId: String

    /// Parse Claude Code's `tmux` field, e.g. `p1app:@0.%0`.
    /// tmux session names cannot contain ":", so the last ":" splits the name.
    init?(claudeField field: String) {
        guard let colon = field.lastIndex(of: ":") else { return nil }
        let name = String(field[..<colon])
        let rest = field[field.index(after: colon)...]
        guard !name.isEmpty, let dot = rest.firstIndex(of: ".") else { return nil }
        let window = String(rest[..<dot])
        let pane = String(rest[rest.index(after: dot)...])
        guard window.hasPrefix("@"), pane.hasPrefix("%") else { return nil }
        self.sessionName = name
        self.windowId = window
        self.paneId = pane
    }

    init(sessionName: String, windowId: String, paneId: String) {
        self.sessionName = sessionName
        self.windowId = windowId
        self.paneId = paneId
    }
}

/// Claude Code's per-process record, `~/.claude/sessions/<pid>.json`.
/// It exists while the process runs and is deleted on a clean exit.
struct ClaudeLiveRecord: Decodable, Hashable {
    let pid: Int32
    let sessionId: String
    let cwd: String?
    /// Epoch milliseconds.
    let startedAt: Double?
    /// "session:@window.%pane". Filled in from the process tree when Claude
    /// Code does not record it.
    var tmux: String?
    /// Claude Code's name for the session, e.g. "systemforge-61". Sessions
    /// use it to address each other; it can change while the session runs.
    let name: String?
    /// "busy", "idle", "waiting", "shell", ...
    let status: String?
    /// What a waiting session needs, e.g. "permission prompt".
    let waitingFor: String?

    var startDate: Date? {
        startedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    var tmuxTarget: TmuxTarget? {
        tmux.flatMap(TmuxTarget.init(claudeField:))
    }
}

/// A git repository a session worked in.
struct RepoRef: Codable, Hashable, Identifiable {
    /// Repository root on disk.
    let path: String
    /// Remote ID such as `github.com/org/repo`, when it has an origin remote.
    let remoteId: String?

    var id: String { path }
    var displayName: String { remoteId ?? path }
}

/// What a transcript says about a session, from bounded reads of its start and end.
struct TranscriptSummary: Hashable {
    var sessionId: String
    var path: String
    var cwd: String?
    var gitBranch: String?
    var version: String?
    var createdAt: Date?
    var lastActivityAt: Date?
    var title: String?
    var firstPrompt: String?
    var lastPrompt: String?
    /// Absolute file paths the agent read or edited near the end of the transcript.
    var touchedPaths: [String] = []
    /// A `cost-state` record follows the last conversation record.
    var hasShutdownRecord = false
}

/// One row of the sessions list: a Claude session joined with what is known
/// about its tmux location and how it ended.
struct ClaudeSessionInfo: Identifiable, Hashable {
    let sessionId: String
    var id: String { sessionId }

    var cwd: String?
    var gitBranch: String?
    var title: String?
    var firstPrompt: String?
    var lastPrompt: String?
    var createdAt: Date?
    var lastActivityAt: Date?
    var version: String?

    /// Current tmux location if running, else the last one observed.
    var tmux: TmuxTarget?
    var pid: Int32?
    /// Claude Code's name for the session, e.g. "github-com-8b".
    var claudeName: String?
    /// Live status while running ("busy", "idle", "waiting", ...).
    var liveStatus: String?
    /// What a waiting session needs, e.g. "permission prompt".
    var waitingFor: String?
    var repos: [RepoRef] = []
    var endState: SessionEndState
    /// When the app saw it end, if it did.
    var endedAt: Date?

    /// Short live status for display, e.g. "waiting: permission prompt".
    var liveStatusText: String? {
        ClaudeLiveStatus.text(status: liveStatus, waitingFor: waitingFor)
    }

    var subject: String {
        title ?? firstPrompt ?? lastPrompt ?? "(untitled)"
    }

    var shortId: String {
        String(sessionId.prefix(8))
    }

    var resumeCommand: String {
        let dir = cwd.map { "cd \(ShellQuote.quote($0)) && " } ?? ""
        return "\(dir)claude --resume \(sessionId)"
    }
}

enum ClaudeLiveStatus {
    /// "waiting: permission prompt" when a session is blocked, else the
    /// status as Claude Code reports it ("busy", "idle", ...).
    static func text(status: String?, waitingFor: String?) -> String? {
        if let waitingFor, !waitingFor.isEmpty {
            return "waiting: \(waitingFor)"
        }
        guard let status, !status.isEmpty else { return nil }
        return status
    }

    /// Whether the session needs the user.
    static func isWaiting(status: String?, waitingFor: String?) -> Bool {
        (waitingFor?.isEmpty == false) || status == "waiting"
    }
}

enum ShellQuote {
    /// Quote a string for a POSIX shell.
    static func quote(_ s: String) -> String {
        if !s.isEmpty, s.allSatisfy({ $0.isLetter || $0.isNumber || "/._-+=:@%".contains($0) }) {
            return s
        }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
