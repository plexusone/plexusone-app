import XCTest
@testable import PlexusOneDesktop

final class ClaudeSessionTests: XCTestCase {

    // MARK: - tmux target

    func testTmuxTargetParsesClaudeField() throws {
        let target = try XCTUnwrap(TmuxTarget(claudeField: "p1app:@0.%12"))
        XCTAssertEqual(target.sessionName, "p1app")
        XCTAssertEqual(target.windowId, "@0")
        XCTAssertEqual(target.paneId, "%12")
    }

    func testTmuxTargetRejectsMalformedField() {
        XCTAssertNil(TmuxTarget(claudeField: "p1app"))
        XCTAssertNil(TmuxTarget(claudeField: ":@0.%1"))
        XCTAssertNil(TmuxTarget(claudeField: "p1app:0.1"))
    }

    // MARK: - Transcript

    private func line(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(data: data, encoding: .utf8)!
    }

    private func transcript(_ lines: [String]) -> Data {
        Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private func summarize(_ lines: [String]) -> TranscriptSummary? {
        ClaudeTranscriptReader.summarize(
            sessionId: "s1", path: "/x/s1.jsonl", head: transcript(lines), tail: Data(), tailStartsMidLine: false
        )
    }

    func testSummaryReadsPromptsTitleAndShutdownRecord() throws {
        let lines = [
            line(["type": "user", "timestamp": "2026-10-27T10:00:00.000Z", "cwd": "/repo", "version": "2.1.300",
                  "message": ["content": "Fix the login bug"]]),
            line(["type": "user", "timestamp": "2026-10-27T10:00:01.000Z", "isMeta": true,
                  "message": ["content": "injected context"]]),
            line(["type": "user", "timestamp": "2026-10-27T10:00:02.000Z",
                  "message": ["content": [["type": "tool_result", "content": "ok"]]]]),
            line(["type": "user", "timestamp": "2026-10-27T10:00:03.000Z",
                  "message": ["content": "<command-name>/clear</command-name>"]]),
            line(["type": "assistant", "timestamp": "2026-10-27T10:05:00.000Z", "gitBranch": "main",
                  "message": ["content": [["type": "tool_use", "name": "Edit",
                                           "input": ["file_path": "/other/repo/a.go"]]]]]),
            line(["type": "ai-title", "aiTitle": "Login bug fix"]),
            line(["type": "last-prompt", "lastPrompt": "now add a test"]),
            line(["type": "cost-state", "totalCostUSD": 1.0]),
        ]
        let s = try XCTUnwrap(summarize(lines))

        XCTAssertEqual(s.cwd, "/repo")
        XCTAssertEqual(s.gitBranch, "main")
        XCTAssertEqual(s.version, "2.1.300")
        XCTAssertEqual(s.title, "Login bug fix")
        XCTAssertEqual(s.firstPrompt, "Fix the login bug")
        XCTAssertEqual(s.lastPrompt, "now add a test")
        XCTAssertEqual(s.touchedPaths, ["/other/repo/a.go"])
        XCTAssertTrue(s.hasShutdownRecord)
        XCTAssertEqual(s.createdAt, ISO8601DateFormatter().date(from: "2026-10-27T10:00:00Z"))
        XCTAssertEqual(s.lastActivityAt, ISO8601DateFormatter().date(from: "2026-10-27T10:05:00Z"))
    }

    func testShutdownRecordMustFollowLastConversationRecord() throws {
        let lines = [
            line(["type": "user", "timestamp": "2026-10-27T10:00:00Z", "message": ["content": "hi"]]),
            line(["type": "cost-state"]),
            line(["type": "assistant", "timestamp": "2026-10-27T10:01:00Z", "message": ["content": [["type": "text", "text": "hello"]]]]),
        ]
        XCTAssertFalse(try XCTUnwrap(summarize(lines)).hasShutdownRecord)
    }

    func testSummaryWithoutTimestampsIsNil() {
        XCTAssertNil(summarize([line(["type": "ai-title", "aiTitle": "x"])]))
    }

    func testTailDropsCutFirstLineAndBadLastLine() throws {
        let head = transcript([line(["type": "user", "timestamp": "2026-10-27T10:00:00Z", "message": ["content": "start"]])])
        let tail = Data(("ime\":\"cut\"}\n"
            + line(["type": "assistant", "timestamp": "2026-10-27T11:00:00Z", "message": ["content": [["type": "text", "text": "x"]]]])
            + "\n{\"type\":\"user\",\"timest").utf8)
        let s = try XCTUnwrap(ClaudeTranscriptReader.summarize(
            sessionId: "s1", path: "/x", head: head, tail: tail, tailStartsMidLine: true
        ))
        XCTAssertEqual(s.lastActivityAt, ISO8601DateFormatter().date(from: "2026-10-27T11:00:00Z"))
        XCTAssertEqual(s.firstPrompt, "start")
    }

    func testVersionGateForShutdownRecord() {
        XCTAssertFalse(ClaudeTranscriptReader.writesShutdownRecord(version: "2.1.212"))
        XCTAssertTrue(ClaudeTranscriptReader.writesShutdownRecord(version: "2.1.286"))
        XCTAssertTrue(ClaudeTranscriptReader.writesShutdownRecord(version: "2.2.0"))
        XCTAssertFalse(ClaudeTranscriptReader.writesShutdownRecord(version: nil))
    }

    // MARK: - Git

    func testNormalizeRemote() {
        XCTAssertEqual(GitRepoResolver.normalizeRemote("git@github.com:org/repo.git"), "github.com/org/repo")
        XCTAssertEqual(GitRepoResolver.normalizeRemote("https://github.com/org/repo"), "github.com/org/repo")
        XCTAssertEqual(GitRepoResolver.normalizeRemote("https://user@github.com/org/repo.git/"), "github.com/org/repo")
        XCTAssertEqual(GitRepoResolver.normalizeRemote("ssh://git@github.com:22/org/repo.git"), "github.com/org/repo")
        XCTAssertNil(GitRepoResolver.normalizeRemote("/local/path/repo"))
    }

    func testOriginURLInConfig() {
        let config = """
        [core]
        \tbare = false
        [remote "upstream"]
        \turl = git@github.com:up/repo.git
        [remote "origin"]
        \turl = git@github.com:org/repo.git
        \tfetch = +refs/heads/*:refs/remotes/origin/*
        """
        XCTAssertEqual(GitRepoResolver.originURL(inConfig: config), "git@github.com:org/repo.git")
    }

    func testResolverFindsRepositoryAndRemote() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("repo-\(UUID().uuidString)")
        let gitDir = root.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("pkg/sub"), withIntermediateDirectories: true)
        try "[remote \"origin\"]\n\turl = https://github.com/org/repo.git\n"
            .write(to: gitDir.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                XCTFail("cleanup: \(error)")
            }
        }

        let repos = GitRepoResolver().repos(for: [
            root.appendingPathComponent("pkg/sub/file.go").path,
            root.path,
            "/definitely/not/a/repo/file",
        ])
        XCTAssertEqual(repos.count, 1)
        XCTAssertEqual(repos.first?.remoteId, "github.com/org/repo")
        XCTAssertEqual(repos.first?.path, root.standardizedFileURL.path)
    }

    // MARK: - Registry

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ id: String, pid: Int32 = 100, tmux: String? = "work:@0.%1") -> ClaudeLiveRecord {
        let json = """
        {"pid":\(pid),"sessionId":"\(id)","cwd":"/repo","startedAt":1800000000000\(tmux.map { ",\"tmux\":\"\($0)\"" } ?? "")}
        """
        return try! JSONDecoder().decode(ClaudeLiveRecord.self, from: Data(json.utf8))
    }

    private func snap(
        at offset: TimeInterval,
        live: [ClaudeLiveRecord] = [],
        stale: [ClaudeLiveRecord] = [],
        panes: Set<String> = ["%1"],
        server: Bool = true,
        boot: Date? = nil
    ) -> SessionSnapshot {
        SessionSnapshot(
            live: live, stale: stale, tmuxPaneIds: panes, tmuxServerRunning: server,
            bootTime: boot ?? Date(timeIntervalSince1970: 1_700_000_000), takenAt: t0.addingTimeInterval(offset)
        )
    }

    private func endState(after final: SessionSnapshot, tmux: String? = "work:@0.%1") -> SessionEndState? {
        var registry = ClaudeSessionRegistry()
        registry.observe(snap(at: 0, live: [record("a", tmux: tmux)]))
        registry.observe(final)
        XCTAssertEqual(registry.sessions["a"]?.isRunning, false)
        return registry.sessions["a"]?.endState
    }

    func testExitWithPaneStillOpenIsNormalExit() {
        XCTAssertEqual(endState(after: snap(at: 5, panes: ["%1"])), .exited)
    }

    func testPaneGoneIsTmuxClosed() {
        XCTAssertEqual(endState(after: snap(at: 5, panes: ["%2"])), .tmuxClosed)
    }

    func testTmuxServerGoneIsTmuxClosed() {
        XCTAssertEqual(endState(after: snap(at: 5, panes: [], server: false)), .tmuxClosed)
    }

    func testRecordLeftBehindIsCrash() {
        XCTAssertEqual(endState(after: snap(at: 5, stale: [record("a")])), .crashed)
    }

    func testBootAfterLastSeenIsSystemShutdown() {
        XCTAssertEqual(endState(after: snap(at: 600, boot: t0.addingTimeInterval(300))), .systemShutdown)
    }

    func testEndingWhileNotWatchingIsLeftToTranscript() {
        XCTAssertNil(endState(after: snap(at: 3600)))
    }

    func testEndingOutsideTmuxIsLeftToTranscript() {
        XCTAssertNil(endState(after: snap(at: 5), tmux: nil))
    }

    func testRegistryKeepsTmuxAndClearsEndWhenResumed() {
        var registry = ClaudeSessionRegistry()
        registry.observe(snap(at: 0, live: [record("a")]))
        registry.observe(snap(at: 5))
        registry.observe(snap(at: 10, live: [record("a", tmux: nil)]))
        let entry = registry.sessions["a"]
        XCTAssertEqual(entry?.isRunning, true)
        XCTAssertNil(entry?.endState)
        XCTAssertEqual(entry?.tmux?.sessionName, "work")
    }

    func testRegistryRoundTrip() throws {
        let fs = MockFileSystem()
        let url = URL(fileURLWithPath: "/tmp/test/claude-sessions.json")
        var registry = ClaudeSessionRegistry()
        registry.observe(snap(at: 0, live: [record("a")]))
        try registry.save(to: url, fileSystem: fs)
        let loaded = try ClaudeSessionRegistry.load(from: url, fileSystem: fs)
        XCTAssertEqual(loaded.sessions["a"]?.tmux?.paneId, "%1")
    }

    // MARK: - Classification

    private func summary(version: String = "2.1.300", shutdown: Bool, last: Date? = nil) -> TranscriptSummary {
        var s = TranscriptSummary(sessionId: "a", path: "/x")
        s.version = version
        s.hasShutdownRecord = shutdown
        s.lastActivityAt = last ?? t0
        return s
    }

    private func classify(
        _ t: TranscriptSummary?, live: ClaudeLiveRecord? = nil, stale: ClaudeLiveRecord? = nil,
        observed: ObservedSession? = nil, boot: Date? = nil
    ) -> SessionEndState {
        ClaudeSessionCatalog.classify(transcript: t, live: live, stale: stale, observed: observed, bootTime: boot)
    }

    func testClassification() {
        XCTAssertEqual(classify(summary(shutdown: false), live: record("a")), .running)
        XCTAssertEqual(classify(summary(shutdown: true)), .endedCleanly)
        XCTAssertEqual(classify(summary(shutdown: false)), .endedAbnormally)
        XCTAssertEqual(classify(summary(shutdown: false), boot: t0.addingTimeInterval(-60)), .endedAbnormally)
        XCTAssertEqual(classify(summary(shutdown: false), boot: t0.addingTimeInterval(60)), .systemShutdown)
        XCTAssertEqual(classify(summary(shutdown: true), boot: t0.addingTimeInterval(60)), .endedCleanly)
        XCTAssertEqual(classify(summary(version: "2.1.212", shutdown: false)), .unknown)
        XCTAssertEqual(classify(summary(shutdown: false), stale: record("a"), boot: t0.addingTimeInterval(60)), .systemShutdown)
        XCTAssertEqual(classify(summary(shutdown: false), stale: record("a"), boot: t0.addingTimeInterval(-60)), .crashed)
    }

    func testObservedEndingWins() {
        let observed = ObservedSession(
            sessionId: "a", firstSeenAt: t0, lastSeenRunningAt: t0, isRunning: false, endState: .tmuxClosed, endedAt: t0
        )
        XCTAssertEqual(classify(summary(shutdown: true), observed: observed), .tmuxClosed)
    }

    func testObservedRunningBeforeBootIsSystemShutdown() {
        let observed = ObservedSession(sessionId: "a", firstSeenAt: t0, lastSeenRunningAt: t0, isRunning: true)
        XCTAssertEqual(classify(summary(shutdown: true), observed: observed, boot: t0.addingTimeInterval(60)), .systemShutdown)
    }

    func testReadLiveRecordsSplitsLiveFromStale() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sessions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: dir)
            } catch {
                XCTFail("cleanup: \(error)")
            }
        }
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        for (pid, id) in [(1, "alive"), (2, "reused"), (3, "gone")] {
            let json = "{\"pid\":\(pid),\"sessionId\":\"\(id)\",\"startedAt\":1800000000000}"
            try json.write(to: dir.appendingPathComponent("\(pid).json"), atomically: true, encoding: .utf8)
        }
        try "not json".write(to: dir.appendingPathComponent("4.json"), atomically: true, encoding: .utf8)

        let (live, stale) = ClaudeSessionCatalog.readLiveRecords(in: dir) { pid in
            switch pid {
            case 1: return started.addingTimeInterval(2)
            case 2: return started.addingTimeInterval(3600) // PID reused by a later process
            default: return nil
            }
        }
        XCTAssertEqual(live.map(\.sessionId), ["alive"])
        XCTAssertEqual(Set(stale.map(\.sessionId)), ["reused", "gone"])
    }

    // MARK: - Restore

    private func info(state: SessionEndState, tmux: String? = "work:@0.%1", cwd: String? = "/repo") -> ClaudeSessionInfo {
        ClaudeSessionInfo(
            sessionId: "6a68b401-de14-455b-80be-3427cbace96a",
            cwd: cwd,
            tmux: tmux.flatMap(TmuxTarget.init(claudeField:)),
            endState: state
        )
    }

    func testRestoreRunningSessionJustAttaches() async throws {
        let mock = MockCommandExecutor()
        let name = try await ClaudeSessionRestorer(commandExecutor: mock, directoryExists: { _ in true })
            .restore(info(state: .running))
        XCTAssertEqual(name, "work")
        XCTAssertTrue(mock.executedCommands.isEmpty)
    }

    func testRestoreCreatesTmuxSessionAndTypesResume() async throws {
        let mock = MockCommandExecutor()
        mock.stubTmuxFailure(arguments: ["has-session"], stderr: "can't find session")
        mock.stubTmuxSuccess(arguments: ["new-session"], stdout: "%7\n")
        let name = try await ClaudeSessionRestorer(commandExecutor: mock, directoryExists: { _ in true })
            .restore(info(state: .systemShutdown))

        XCTAssertEqual(name, "work")
        XCTAssertEqual(mock.tmuxExecutionCount(subcommand: "new-session"), 1)
        XCTAssertEqual(mock.tmuxExecutionCount(subcommand: "new-window"), 0)
        let typed = mock.executedCommands.map(\.arguments).filter { $0.contains("send-keys") }
        XCTAssertEqual(typed.count, 2)
        XCTAssertTrue(typed[0].contains("claude --resume 6a68b401-de14-455b-80be-3427cbace96a"))
        XCTAssertTrue(typed[0].contains("%7"))
    }

    func testRestoreAddsWindowToExistingTmuxSession() async throws {
        let mock = MockCommandExecutor()
        mock.stubTmuxSuccess(arguments: ["has-session"])
        mock.stubTmuxSuccess(arguments: ["new-window"], stdout: "%9\n")
        _ = try await ClaudeSessionRestorer(commandExecutor: mock, directoryExists: { _ in true })
            .restore(info(state: .exited))
        XCTAssertEqual(mock.tmuxExecutionCount(subcommand: "new-window"), 1)
        XCTAssertEqual(mock.tmuxExecutionCount(subcommand: "new-session"), 0)
    }

    func testRestoreRefusesMissingDirectoryAndRunningOutsideTmux() async {
        let restorer = ClaudeSessionRestorer(commandExecutor: MockCommandExecutor(), directoryExists: { _ in false })
        do {
            _ = try await restorer.restore(info(state: .crashed))
            XCTFail("expected missingDirectory")
        } catch {
            XCTAssertEqual(error as? RestoreError, .missingDirectory("/repo"))
        }
        do {
            _ = try await restorer.restore(info(state: .running, tmux: nil))
            XCTFail("expected runningOutsideTmux")
        } catch {
            XCTAssertEqual(error as? RestoreError, .runningOutsideTmux("6a68b401-de14-455b-80be-3427cbace96a"))
        }
    }

    func testRestoreUsesChosenTmuxName() async throws {
        let mock = MockCommandExecutor()
        mock.stubTmuxFailure(arguments: ["has-session"], stderr: "can't find session")
        mock.stubTmuxSuccess(arguments: ["new-session"], stdout: "%3\n")
        let name = try await ClaudeSessionRestorer(commandExecutor: mock, directoryExists: { _ in true })
            .restore(info(state: .systemShutdown, tmux: nil), tmuxName: " omni.agent ")
        XCTAssertEqual(name, "omni-agent")
        XCTAssertTrue(mock.executedCommands.contains { $0.arguments.contains("omni-agent") && $0.arguments.contains("new-session") })
    }

    func testTmuxNameFallsBackToDirectory() {
        XCTAssertEqual(ClaudeSessionRestorer.tmuxName(for: info(state: .exited, tmux: nil, cwd: "/src/my.app")), "my-app-6a68b401")
    }

    func testGridFitting() {
        XCTAssertEqual(GridConfig.fitting(1), GridConfig(columns: 1, rows: 1))
        XCTAssertEqual(GridConfig.fitting(4), GridConfig(columns: 2, rows: 2))
        XCTAssertEqual(GridConfig.fitting(6), GridConfig(columns: 3, rows: 2))
        XCTAssertEqual(GridConfig.fitting(20), GridConfig(columns: 3, rows: 3))
    }
}
