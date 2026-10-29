import Foundation

/// Records Claude Code sessions while the app is not running.
///
/// Claude Code runs `PlexusOneDesktop claude-hook` from a SessionStart and a
/// UserPromptSubmit hook (see `ClaudeHookInstaller`). Each run appends one
/// event line with the session ID, directory, and tmux pane to
/// `~/.plexusone/claude-session-events.jsonl`; the app folds the events into
/// its observation log. The hook prints nothing (Claude Code would add hook
/// output to the conversation) and never fails, so it cannot disturb Claude.
enum ClaudeHookRecorder {
    /// Command-line argument that runs the recorder instead of the app.
    static let command = "claude-hook"

    struct Event: Codable, Equatable, Sendable {
        let sessionId: String
        let cwd: String?
        /// "session:@window.%pane", when the session runs in tmux.
        let tmux: String?
        let event: String?
        let at: Date
    }

    static var eventsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".plexusone/claude-session-events.jsonl")
    }

    /// Entry point for `PlexusOneDesktop claude-hook`.
    static func run() {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard let event = makeEvent(hookInput: input, tmux: currentTmuxTarget(), now: Date()) else { return }
        do {
            try append(event, to: eventsURL)
        } catch {
            // Hook output would reach the conversation, so record failures
            // only in the system log.
            NSLog("PlexusOne claude-hook: %@", error.localizedDescription)
        }
    }

    /// Build an event from the JSON Claude Code passes a hook on stdin.
    static func makeEvent(hookInput: Data, tmux: String?, now: Date) -> Event? {
        guard let object = try? JSONSerialization.jsonObject(with: hookInput) as? [String: Any],
              let sessionId = object["session_id"] as? String, !sessionId.isEmpty else {
            return nil
        }
        return Event(
            sessionId: sessionId,
            cwd: object["cwd"] as? String,
            tmux: tmux,
            event: object["hook_event_name"] as? String,
            at: now
        )
    }

    /// The tmux pane this process runs in, from `$TMUX_PANE`.
    static func currentTmuxTarget() -> String? {
        let env = ProcessInfo.processInfo.environment
        guard env["TMUX"] != nil, let pane = env["TMUX_PANE"], !pane.isEmpty else { return nil }
        let (path, baseArgs) = TmuxEnvironment.findExecutable()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = baseArgs + ["display-message", "-p", "-t", pane, "#{session_name}:#{window_id}.#{pane_id}"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let target = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return TmuxTarget(claudeField: target) != nil ? target : nil
    }

    /// Append one JSON line. A single write to a file opened for appending,
    /// so concurrent hooks do not interleave lines.
    static func append(_ event: Event, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var line = try encoder.encode(event)
        line.append(UInt8(ascii: "\n"))
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        let written = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written == line.count else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    }

    /// Decode event lines, skipping any that are cut off or malformed.
    static func decodeEvents(_ data: Data) -> [Event] {
        data.split(separator: UInt8(ascii: "\n")).compactMap { try? decoder.decode(Event.self, from: Data($0)) }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
