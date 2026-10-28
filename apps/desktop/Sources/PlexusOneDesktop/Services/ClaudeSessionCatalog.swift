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

    private var registry = ClaudeSessionRegistry()
    private var latestSnapshot: SessionSnapshot?
    private var transcriptCache: [String: CachedTranscript] = [:]
    private var monitorTask: Task<Void, Never>?

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
        if registry.observe(snap) {
            do {
                try registry.save(to: registryURL, fileSystem: fileSystem)
            } catch {
                lastError = "Could not save \(registryURL.path): \(error.localizedDescription)"
            }
        }
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
            title: t.title ?? live?.name,
            firstPrompt: t.firstPrompt,
            lastPrompt: t.lastPrompt,
            createdAt: t.createdAt,
            lastActivityAt: t.lastActivityAt,
            version: t.version,
            tmux: live?.tmuxTarget ?? stale?.tmuxTarget ?? observed?.tmux,
            pid: live?.pid,
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
        let (live, stale) = readLiveRecords(in: claudeDir.appendingPathComponent("sessions"))
        let panes = await tmuxPanes(commandExecutor: commandExecutor)
        return SessionSnapshot(
            live: live,
            stale: stale,
            tmuxPaneIds: panes ?? [],
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

    /// Every tmux pane ID, or nil when no tmux server is running.
    nonisolated static func tmuxPanes(commandExecutor: any CommandExecuting) async -> Set<String>? {
        let (path, baseArgs) = TmuxEnvironment.findExecutable()
        do {
            let result = try await commandExecutor.execute(path, arguments: baseArgs + ["list-panes", "-a", "-F", "#{pane_id}"])
            guard result.success else { return nil }
            return Set(result.stdout.split(separator: "\n").map(String.init))
        } catch {
            return nil
        }
    }
}
