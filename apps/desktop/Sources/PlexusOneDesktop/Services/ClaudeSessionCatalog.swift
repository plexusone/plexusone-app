import Foundation
import Observation

/// Lists Claude Code sessions with their tmux location, repositories, subject,
/// and how they ended, and keeps the observation log that makes "how they
/// ended" possible.
@MainActor
@Observable
final class ClaudeSessionCatalog {
    private(set) var sessions: [ClaudeSessionInfo] = []
    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var bootTime: Date?
    /// Live Claude sessions by tmux session name, for pane headers.
    private(set) var liveByTmuxSession: [String: ClaudeLiveRecord] = [:]

    private var registry = ClaudeSessionRegistry()
    private var latestSnapshot: SessionSnapshot?
    private var transcriptCache: [String: CachedTranscript] = [:]
    private var monitorTask: Task<Void, Never>?
    /// The @claude_name value last set on each tmux session.
    private var appliedClaudeNames: [String: String] = [:]

    private let claudeDir: URL
    private let registryURL: URL
    private let fileSystem: any FileSystemAccessing
    private let commandExecutor: any CommandExecuting
    private let pollInterval: TimeInterval = 5

    /// A start time this far from the live record's still counts as the same
    /// process; further off means the PID was reused.
    nonisolated static let startTolerance: TimeInterval = 60

    nonisolated init(
        fileSystem: any FileSystemAccessing = DefaultFileSystemAccessing(),
        commandExecutor: any CommandExecuting = ProcessCommandExecutor(),
        claudeDir: URL? = nil,
        registryURL: URL? = nil
    ) {
        let home = fileSystem.homeDirectoryForCurrentUser
        self.fileSystem = fileSystem
        self.commandExecutor = commandExecutor
        self.claudeDir = claudeDir ?? home.appendingPathComponent(".claude")
        self.registryURL = registryURL ?? home.appendingPathComponent(".plexusone/claude-sessions.json")
    }

    // MARK: - Monitoring

    /// Load the observation log and start watching sessions (idempotent).
    func startMonitoring() {
        guard monitorTask == nil else { return }
        do {
            registry = try ClaudeSessionRegistry.load(from: registryURL, fileSystem: fileSystem)
        } catch {
            lastError = "Could not read \(registryURL.path): \(error.localizedDescription)"
        }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.observeOnce()
                let interval = self.pollInterval
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Take one snapshot and record what changed.
    func observeOnce() async {
        let snap = await Self.takeSnapshot(
            claudeDir: claudeDir,
            commandExecutor: commandExecutor
        )
        latestSnapshot = snap
        bootTime = snap.bootTime
        liveByTmuxSession = Self.liveByTmuxSession(snap.live)
        await syncClaudeNameOptions()
        if registry.observe(snap) {
            do {
                try registry.save(to: registryURL, fileSystem: fileSystem)
            } catch {
                lastError = "Could not save \(registryURL.path): \(error.localizedDescription)"
            }
        }
    }

    /// The live record for each tmux session. If several Claude sessions
    /// share a tmux session, the most recently started one wins.
    nonisolated static func liveByTmuxSession(_ live: [ClaudeLiveRecord]) -> [String: ClaudeLiveRecord] {
        var result: [String: ClaudeLiveRecord] = [:]
        for rec in live {
            guard let session = rec.tmuxTarget?.sessionName else { continue }
            if let existing = result[session], (existing.startedAt ?? 0) > (rec.startedAt ?? 0) {
                continue
            }
            result[session] = rec
        }
        return result
    }

    // MARK: - tmux @claude_name

    /// Keep the `@claude_name` user option on each tmux session equal to the
    /// name of the Claude session running in it, so a tmux status line can
    /// show it (see the Claude Sessions guide). Only changes call tmux.
    private func syncClaudeNameOptions() async {
        var wanted: [String: String] = [:]
        for (session, rec) in liveByTmuxSession {
            if let name = rec.name, !name.isEmpty { wanted[session] = name }
        }
        for (session, args) in Self.claudeNameOptionChanges(applied: appliedClaudeNames, wanted: wanted) {
            let (path, baseArgs) = TmuxEnvironment.findExecutable()
            do {
                let result = try await commandExecutor.execute(path, arguments: baseArgs + args)
                if !result.success {
                    // The tmux session may have closed already; nothing to update.
                    NSLog("PlexusOne: tmux %@ for %@: %@", args.joined(separator: " "), session, result.stderr)
                }
            } catch {
                NSLog("PlexusOne: tmux @claude_name for %@ failed: %@", session, error.localizedDescription)
            }
        }
        appliedClaudeNames = wanted
    }

    /// The tmux commands that move the applied @claude_name values to the
    /// wanted ones: set new or changed names, unset names whose Claude
    /// session ended.
    nonisolated static func claudeNameOptionChanges(
        applied: [String: String],
        wanted: [String: String]
    ) -> [(session: String, args: [String])] {
        var changes: [(session: String, args: [String])] = []
        for session in wanted.keys.sorted() where applied[session] != wanted[session] {
            changes.append((session, ["set-option", "-t", "=\(session):", "@claude_name", wanted[session] ?? ""]))
        }
        for session in applied.keys.sorted() where wanted[session] == nil {
            changes.append((session, ["set-option", "-u", "-t", "=\(session):", "@claude_name"]))
        }
        return changes
    }

    // MARK: - Listing

    /// Rebuild the list from transcripts active within `window` (nil for all).
    func reload(window: TimeInterval?) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        if latestSnapshot == nil {
            await observeOnce()
        }
        let projectsDir = claudeDir.appendingPathComponent("projects")
        let cutoff = window.map { Date().addingTimeInterval(-$0) }
        let cache = transcriptCache
        let snap = latestSnapshot
        let registry = registry

        let result = await Task.detached(priority: .userInitiated) {
            Self.build(projectsDir: projectsDir, cutoff: cutoff, cache: cache, snapshot: snap, registry: registry)
        }.value

        transcriptCache = result.cache
        sessions = result.sessions
        lastError = result.error
    }

    private struct CachedTranscript: Sendable {
        let modified: Date
        let size: Int
        let summary: TranscriptSummary?
    }

    private struct BuildResult: Sendable {
        let sessions: [ClaudeSessionInfo]
        let cache: [String: CachedTranscript]
        let error: String?
    }

    private nonisolated static func build(
        projectsDir: URL,
        cutoff: Date?,
        cache: [String: CachedTranscript],
        snapshot: SessionSnapshot?,
        registry: ClaudeSessionRegistry
    ) -> BuildResult {
        var newCache: [String: CachedTranscript] = [:]
        var summaries: [TranscriptSummary] = []
        var failures: [String] = []
        let fm = FileManager.default

        let dirs: [URL]
        do {
            dirs = try fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: [.isDirectoryKey])
        } catch {
            return BuildResult(sessions: [], cache: cache, error: "Could not read \(projectsDir.path): \(error.localizedDescription)")
        }

        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        for dir in dirs {
            let files: [URL]
            do {
                files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)
            } catch {
                continue // not a directory
            }
            for file in files where file.pathExtension == "jsonl" {
                let values = try? file.resourceValues(forKeys: Set(keys))
                let modified = values?.contentModificationDate ?? .distantPast
                let size = values?.fileSize ?? 0
                if let cutoff, modified < cutoff { continue }

                if let cached = cache[file.path], cached.modified == modified, cached.size == size {
                    newCache[file.path] = cached
                    if let s = cached.summary { summaries.append(s) }
                    continue
                }
                do {
                    let summary = try ClaudeTranscriptReader.read(url: file)
                    newCache[file.path] = CachedTranscript(modified: modified, size: size, summary: summary)
                    if let summary { summaries.append(summary) }
                } catch {
                    failures.append(file.lastPathComponent)
                }
            }
        }

        let resolver = GitRepoResolver()
        let live = Dictionary((snapshot?.live ?? []).map { ($0.sessionId, $0) }, uniquingKeysWith: { a, _ in a })
        let stale = Dictionary((snapshot?.stale ?? []).map { ($0.sessionId, $0) }, uniquingKeysWith: { a, _ in a })

        var infos = summaries.map { t in
            makeInfo(
                transcript: t,
                live: live[t.sessionId],
                stale: stale[t.sessionId],
                observed: registry.sessions[t.sessionId],
                bootTime: snapshot?.bootTime,
                resolver: resolver
            )
        }
        infos.sort { ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast) }

        let error = failures.isEmpty ? nil : "Could not read \(failures.count) transcript(s)"
        return BuildResult(sessions: infos, cache: newCache, error: error)
    }

    nonisolated static func makeInfo(
        transcript t: TranscriptSummary,
        live: ClaudeLiveRecord?,
        stale: ClaudeLiveRecord?,
        observed: ObservedSession?,
        bootTime: Date?,
        resolver: GitRepoResolver
    ) -> ClaudeSessionInfo {
        let cwd = t.cwd ?? live?.cwd ?? observed?.cwd
        var repoPaths: [String] = []
        if let cwd { repoPaths.append(cwd) }
        repoPaths += t.touchedPaths

        return ClaudeSessionInfo(
            sessionId: t.sessionId,
            cwd: cwd,
            gitBranch: t.gitBranch,
            title: t.title ?? live?.name ?? observed?.name,
            firstPrompt: t.firstPrompt,
            lastPrompt: t.lastPrompt,
            createdAt: t.createdAt,
            lastActivityAt: t.lastActivityAt,
            version: t.version,
            tmux: live?.tmuxTarget ?? stale?.tmuxTarget ?? observed?.tmux,
            pid: live?.pid,
            claudeName: live?.name ?? stale?.name ?? observed?.name,
            liveStatus: live?.status,
            waitingFor: live?.waitingFor,
            repos: resolver.repos(for: repoPaths),
            endState: classify(transcript: t, live: live, stale: stale, observed: observed, bootTime: bootTime),
            endedAt: observed?.endedAt
        )
    }

    /// Decide how a session ended. Evidence, strongest first: a live
    /// process; what the app observed; a record left behind by a dead
    /// process; the transcript's shutdown record.
    nonisolated static func classify(
        transcript t: TranscriptSummary?,
        live: ClaudeLiveRecord?,
        stale: ClaudeLiveRecord?,
        observed: ObservedSession?,
        bootTime: Date?
    ) -> SessionEndState {
        if live != nil {
            return .running
        }
        if let observed {
            if !observed.isRunning, let state = observed.endState {
                return state
            }
            // Seen running before the last boot and never seen to stop.
            if observed.isRunning, let bootTime, bootTime > observed.lastSeenRunningAt {
                return .systemShutdown
            }
        }
        if let stale {
            let last = t?.lastActivityAt ?? stale.startDate ?? .distantFuture
            if let bootTime, last < bootTime {
                return .systemShutdown
            }
            return .crashed
        }
        guard let t else { return .unknown }
        if t.hasShutdownRecord {
            return .endedCleanly
        }
        guard ClaudeTranscriptReader.writesShutdownRecord(version: t.version) else {
            return .unknown
        }
        // No clean shutdown. If the machine has booted since, the restart is
        // what ended it; otherwise the process was killed or crashed.
        if let bootTime, let last = t.lastActivityAt, last < bootTime {
            return .systemShutdown
        }
        return .endedAbnormally
    }

    // MARK: - Snapshot

    nonisolated static func takeSnapshot(
        claudeDir: URL,
        commandExecutor: any CommandExecuting
    ) async -> SessionSnapshot {
        let now = Date()
        var (live, stale) = readLiveRecords(in: claudeDir.appendingPathComponent("sessions"))
        let panes = await tmuxPanes(commandExecutor: commandExecutor)
        if let panes {
            live = live.map { withTmuxFromProcessTree($0, panes: panes, parentPid: SystemProbe.parentPid) }
        }
        return SessionSnapshot(
            live: live,
            stale: stale,
            tmuxPaneIds: Set((panes ?? []).map(\.target.paneId)),
            tmuxServerRunning: panes != nil,
            bootTime: SystemProbe.bootTime(),
            takenAt: now
        )
    }

    /// Split Claude's live-process records into ones whose process is alive
    /// and ones left behind. A record left by a crash can name a PID that has
    /// since been reused, so the process start time must match too.
    nonisolated static func readLiveRecords(
        in dir: URL,
        processStart: (Int32) -> Date? = SystemProbe.processStartTime
    ) -> (live: [ClaudeLiveRecord], stale: [ClaudeLiveRecord]) {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        } catch {
            return ([], []) // no directory: Claude Code has not run
        }
        var live: [ClaudeLiveRecord] = []
        var stale: [ClaudeLiveRecord] = []
        let decoder = JSONDecoder()
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let record = try? decoder.decode(ClaudeLiveRecord.self, from: data),
                  record.pid > 0, !record.sessionId.isEmpty else {
                continue // removed mid-read, or not a session record
            }
            if let started = processStart(record.pid), let recorded = record.startDate,
               abs(started.timeIntervalSince(recorded)) <= startTolerance {
                live.append(record)
            } else {
                stale.append(record)
            }
        }
        return (live, stale)
    }

    /// A tmux pane and the process tmux started in it.
    struct TmuxPane: Equatable, Sendable {
        let target: TmuxTarget
        let pid: Int32
    }

    /// Every tmux pane, or nil when no tmux server is running.
    nonisolated static func tmuxPanes(commandExecutor: any CommandExecuting) async -> [TmuxPane]? {
        let (path, baseArgs) = TmuxEnvironment.findExecutable()
        do {
            let format = "#{pane_id}\t#{pane_pid}\t#{window_id}\t#{session_name}"
            let result = try await commandExecutor.execute(path, arguments: baseArgs + ["list-panes", "-a", "-F", format])
            guard result.success else { return nil }
            return parseTmuxPanes(result.stdout)
        } catch {
            return nil
        }
    }

    /// Parse `list-panes -F "#{pane_id}\t#{pane_pid}\t#{window_id}\t#{session_name}"`.
    nonisolated static func parseTmuxPanes(_ output: String) -> [TmuxPane] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4, let pid = Int32(parts[1]) else { return nil }
            return TmuxPane(
                target: TmuxTarget(sessionName: String(parts[3]), windowId: String(parts[2]), paneId: String(parts[0])),
                pid: pid
            )
        }
    }

    /// Fill in a record's tmux location from the process tree when Claude
    /// Code did not record one: walk up from the Claude process until
    /// reaching the process tmux started in a pane.
    nonisolated static func withTmuxFromProcessTree(
        _ record: ClaudeLiveRecord,
        panes: [TmuxPane],
        parentPid: (Int32) -> Int32?
    ) -> ClaudeLiveRecord {
        guard record.tmuxTarget == nil else { return record }
        let byPid = Dictionary(panes.map { ($0.pid, $0.target) }, uniquingKeysWith: { a, _ in a })
        var pid: Int32? = record.pid
        var steps = 0
        while let current = pid, current > 1, steps < 64 {
            if let target = byPid[current] {
                var resolved = record
                resolved.tmux = "\(target.sessionName):\(target.windowId).\(target.paneId)"
                return resolved
            }
            pid = parentPid(current)
            steps += 1
        }
        return record
    }
}
