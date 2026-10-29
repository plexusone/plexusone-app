import Foundation

enum RestoreError: Error, LocalizedError, Equatable {
    case invalidSessionId(String)
    case missingDirectory(String?)
    case runningOutsideTmux(String)
    case tmuxFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidSessionId(let id):
            return "'\(id)' is not a Claude session ID"
        case .missingDirectory(let dir):
            if let dir {
                return "The session's directory no longer exists: \(dir)"
            }
            return "The session's directory is unknown"
        case .runningOutsideTmux(let id):
            return "Session \(id.prefix(8)) is running outside tmux, so it cannot be attached here"
        case .tmuxFailed(let message):
            return "tmux failed: \(message)"
        }
    }
}

/// Re-establishes a Claude session in tmux so a pane can attach to it.
struct ClaudeSessionRestorer {
    private let commandExecutor: any CommandExecuting
    private let directoryExists: (String) -> Bool

    init(
        commandExecutor: any CommandExecuting = ProcessCommandExecutor(),
        directoryExists: @escaping (String) -> Bool = { path in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }
    ) {
        self.commandExecutor = commandExecutor
        self.directoryExists = directoryExists
    }

    /// Make sure the session runs in tmux and return the tmux session name
    /// to attach to.
    ///
    /// - A running session is left alone; its tmux session is returned.
    /// - Otherwise `claude --resume <id>` starts in the session's directory:
    ///   in a new window of its remembered tmux session if that still exists,
    ///   else in a new tmux session with the remembered (or derived) name.
    ///
    /// The command is typed into a login shell rather than run as the pane's
    /// command, so PATH matches a normal terminal and the pane stays open
    /// after Claude exits.
    /// - Parameter tmuxName: Name for the tmux session; nil uses the
    ///   remembered or derived name. Ignored for a running session.
    func restore(_ info: ClaudeSessionInfo, tmuxName: String? = nil) async throws -> String {
        if info.endState == .running {
            guard let tmux = info.tmux else { throw RestoreError.runningOutsideTmux(info.sessionId) }
            return tmux.sessionName
        }
        guard UUID(uuidString: info.sessionId) != nil else {
            throw RestoreError.invalidSessionId(info.sessionId)
        }
        guard let cwd = info.cwd, directoryExists(cwd) else {
            throw RestoreError.missingDirectory(info.cwd)
        }

        let name = tmuxName.map(Self.sanitizeName).flatMap { $0.isEmpty ? nil : $0 } ?? Self.tmuxName(for: info)
        let exists = try await runTmux(["has-session", "-t", "=\(name)"]).success
        let create = exists
            ? Self.newWindowArguments(session: name, cwd: cwd)
            : Self.newSessionArguments(session: name, cwd: cwd)
        let created = try await runTmux(create)
        guard created.success else {
            throw RestoreError.tmuxFailed(created.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let paneId = created.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard paneId.hasPrefix("%") else {
            throw RestoreError.tmuxFailed("unexpected pane ID '\(paneId)'")
        }

        for args in Self.sendResumeArguments(paneId: paneId, sessionId: info.sessionId) {
            let sent = try await runTmux(args)
            guard sent.success else {
                throw RestoreError.tmuxFailed(sent.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return name
    }

    /// The remembered tmux name, else one derived from the directory name.
    static func tmuxName(for info: ClaudeSessionInfo) -> String {
        if let name = info.tmux?.sessionName, !name.isEmpty {
            return name
        }
        let base = info.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "claude"
        let cleaned = sanitizeName(base)
        return "\(cleaned.isEmpty ? "claude" : cleaned)-\(info.shortId)"
    }

    /// Make a string usable as a tmux session name, which cannot contain
    /// "." or ":".
    static func sanitizeName(_ name: String) -> String {
        name.replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func newSessionArguments(session: String, cwd: String) -> [String] {
        ["new-session", "-d", "-s", session, "-c", cwd, "-P", "-F", "#{pane_id}"]
    }

    static func newWindowArguments(session: String, cwd: String) -> [String] {
        // "=name:" targets the session exactly and lets tmux pick the window index.
        ["new-window", "-t", "=\(session):", "-c", cwd, "-P", "-F", "#{pane_id}"]
    }

    /// Type the resume command, then press Enter. `-l` sends the text
    /// literally so nothing in it is read as a key name.
    static func sendResumeArguments(paneId: String, sessionId: String) -> [[String]] {
        [
            ["send-keys", "-t", paneId, "-l", "claude --resume \(sessionId)"],
            ["send-keys", "-t", paneId, "Enter"],
        ]
    }

    // MARK: - Rename

    /// Rename a running Claude session by typing `/rename <name>` into its
    /// pane. Only safe while the session is idle at its prompt, which the
    /// caller checks.
    func rename(_ info: ClaudeSessionInfo, to newName: String) async throws {
        guard let paneId = info.tmux?.paneId else {
            throw RestoreError.runningOutsideTmux(info.sessionId)
        }
        guard let name = Self.validRenameName(newName) else {
            throw RestoreError.tmuxFailed("'\(newName)' is not a usable session name")
        }
        for args in Self.renameArguments(paneId: paneId, name: name) {
            let result = try await runTmux(args)
            guard result.success else {
                throw RestoreError.tmuxFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    /// The name trimmed, or nil if it is empty, multi-line, or over 80 characters.
    static func validRenameName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80, !trimmed.contains(where: \.isNewline) else { return nil }
        return trimmed
    }

    static func renameArguments(paneId: String, name: String) -> [[String]] {
        [
            ["send-keys", "-t", paneId, "-l", "/rename \(name)"],
            ["send-keys", "-t", paneId, "Enter"],
        ]
    }

    /// Whether typing into the session is safe: running in tmux, idle, and
    /// not waiting for anything.
    static func canRename(_ info: ClaudeSessionInfo) -> Bool {
        info.endState == .running && info.tmux != nil && info.liveStatus == "idle"
            && (info.waitingFor ?? "").isEmpty
    }

    private func runTmux(_ arguments: [String]) async throws -> CommandResult {
        let (path, baseArgs) = TmuxEnvironment.findExecutable()
        return try await commandExecutor.execute(path, arguments: baseArgs + arguments)
    }
}
