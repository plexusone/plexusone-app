import Foundation

/// What the app has seen of one Claude session.
struct ObservedSession: Codable, Hashable {
    let sessionId: String
    var cwd: String?
    /// Last tmux location seen. Kept after the session ends, so it can be
    /// resumed under the same tmux name.
    var tmux: TmuxTarget?
    var pid: Int32?
    /// Claude Code's name for the session, last seen.
    var name: String?
    var firstSeenAt: Date
    var lastSeenRunningAt: Date
    var isRunning: Bool
    /// How it ended, when the app could tell. nil while running, or when it
    /// ended while the app was not watching (the transcript decides then).
    var endState: SessionEndState?
    var endedAt: Date?
}

/// One look at the machine: which Claude sessions run and which tmux panes exist.
struct SessionSnapshot {
    /// Live records whose process is alive and started when the record says.
    var live: [ClaudeLiveRecord]
    /// Live records left behind by a process that is gone (or whose PID was reused).
    var stale: [ClaudeLiveRecord]
    /// Pane IDs (e.g. `%3`) of every tmux pane, empty when no server runs.
    var tmuxPaneIds: Set<String>
    var tmuxServerRunning: Bool
    var bootTime: Date?
    var takenAt: Date
}

/// Persistent log of Claude sessions the app has seen running, and how each
/// one stopped. Stored at `~/.plexusone/claude-sessions.json`.
///
/// It is the only source that separates `/exit` from a closed terminal, and
/// that remembers tmux names after Claude deletes its own records.
struct ClaudeSessionRegistry: Codable {
    var version = 1
    var sessions: [String: ObservedSession] = [:]
    /// When the previous snapshot was applied.
    var lastObservedAt: Date?
    /// Bytes of the hook events file already folded in.
    var eventsOffset: UInt64?

    /// Longest gap between snapshots that still counts as watching continuously.
    static let continuousGap: TimeInterval = 60
    /// Entries not seen running for this long are dropped.
    static let retention: TimeInterval = 90 * 24 * 3600

    /// Apply a snapshot. Returns true if anything changed.
    @discardableResult
    mutating func observe(_ snap: SessionSnapshot) -> Bool {
        let before = sessions
        let wasWatching = lastObservedAt.map { snap.takenAt.timeIntervalSince($0) <= Self.continuousGap } ?? false
        let previousObservation = lastObservedAt

        var liveIds = Set<String>()
        for rec in snap.live {
            liveIds.insert(rec.sessionId)
            var entry = sessions[rec.sessionId] ?? ObservedSession(
                sessionId: rec.sessionId,
                firstSeenAt: snap.takenAt,
                lastSeenRunningAt: snap.takenAt,
                isRunning: true
            )
            entry.cwd = rec.cwd ?? entry.cwd
            entry.tmux = rec.tmuxTarget ?? entry.tmux
            entry.name = rec.name ?? entry.name
            entry.pid = rec.pid
            entry.lastSeenRunningAt = snap.takenAt
            entry.isRunning = true
            entry.endState = nil
            entry.endedAt = nil
            sessions[rec.sessionId] = entry
        }

        let staleIds = Set(snap.stale.map(\.sessionId))
        for (id, var entry) in sessions where entry.isRunning && !liveIds.contains(id) {
            entry.isRunning = false
            let sawItRunningLastTime = wasWatching && entry.lastSeenRunningAt == previousObservation
            entry.endState = Self.endState(
                for: entry,
                staleRecord: staleIds.contains(id),
                observedTransition: sawItRunningLastTime,
                snapshot: snap
            )
            entry.endedAt = sawItRunningLastTime ? snap.takenAt : nil
            sessions[id] = entry
        }

        sessions = sessions.filter { snap.takenAt.timeIntervalSince($0.value.lastSeenRunningAt) < Self.retention }
        lastObservedAt = snap.takenAt
        return sessions != before
    }

    /// How a session the app thought was running ended.
    static func endState(
        for entry: ObservedSession,
        staleRecord: Bool,
        observedTransition: Bool,
        snapshot snap: SessionSnapshot
    ) -> SessionEndState? {
        if let boot = snap.bootTime, boot > entry.lastSeenRunningAt {
            return .systemShutdown
        }
        if staleRecord {
            return .crashed
        }
        guard observedTransition else {
            return nil // ended while the app was not watching
        }
        guard let tmux = entry.tmux else {
            return nil // not in tmux: nothing to tell exit from a closed terminal
        }
        if !snap.tmuxServerRunning || !snap.tmuxPaneIds.contains(tmux.paneId) {
            return .tmuxClosed
        }
        return .exited
    }

    /// Fold in events recorded by the Claude Code hook. An event means the
    /// session was running at that time in that tmux pane. Sessions the app
    /// is already watching only gain a missing tmux location, so their
    /// observed exit is not disturbed.
    @discardableResult
    mutating func fold(_ events: [ClaudeHookRecorder.Event]) -> Bool {
        let before = sessions
        for event in events {
            let tmux = event.tmux.flatMap(TmuxTarget.init(claudeField:))
            if var entry = sessions[event.sessionId] {
                if entry.isRunning {
                    entry.tmux = entry.tmux ?? tmux
                    entry.cwd = entry.cwd ?? event.cwd
                } else if event.at > entry.lastSeenRunningAt {
                    entry.tmux = tmux ?? entry.tmux
                    entry.cwd = event.cwd ?? entry.cwd
                    entry.lastSeenRunningAt = event.at
                    entry.isRunning = true
                    entry.endState = nil
                    entry.endedAt = nil
                }
                sessions[event.sessionId] = entry
            } else {
                sessions[event.sessionId] = ObservedSession(
                    sessionId: event.sessionId,
                    cwd: event.cwd,
                    tmux: tmux,
                    firstSeenAt: event.at,
                    lastSeenRunningAt: event.at,
                    isRunning: true
                )
            }
        }
        return sessions != before
    }

    // MARK: - Persistence

    static func load(from url: URL, fileSystem: any FileSystemAccessing) throws -> ClaudeSessionRegistry {
        guard fileSystem.fileExists(atPath: url.path) else { return ClaudeSessionRegistry() }
        let data = try fileSystem.contents(at: url)
        return try makeDecoder().decode(ClaudeSessionRegistry.self, from: data)
    }

    func save(to url: URL, fileSystem: any FileSystemAccessing) throws {
        try fileSystem.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Atomic, so a crash mid-write leaves the previous file intact.
        try fileSystem.write(try encoder.encode(self), to: url, options: .atomic)
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
