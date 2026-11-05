import XCTest
@testable import PlexusOneDesktop

/// Tests for the Claude session log, hook, and tmux targeting fixes.
@MainActor
final class ClaudeSessionLogSafetyTests: XCTestCase {
    private let registryURL = URL(fileURLWithPath: "/tmp/mock-home/.plexusone/claude-sessions.json")
    private let backupURL = URL(fileURLWithPath: "/tmp/mock-home/.plexusone/claude-sessions.unreadable.json")

    func testUnreadableLogIsCopiedAsideBeforeSaving() {
        let fileSystem = MockFileSystem()
        let unreadable = Data(#"{"version": 99, "sessions": {"a": {"endState": "fromTheFuture"}}}"#.utf8)
        fileSystem.setFile(at: registryURL, content: unreadable)
        let catalog = ClaudeSessionCatalog(fileSystem: fileSystem, commandExecutor: MockCommandExecutor(), registryURL: registryURL)

        catalog.loadRegistry()

        XCTAssertEqual(fileSystem.getFile(at: backupURL), unreadable)
        XCTAssertTrue(catalog.canSaveRegistry)
        XCTAssertNotNil(catalog.lastError)
    }

    func testUnreadableLogIsLeftAloneWhenBackupFails() {
        let fileSystem = MockFileSystem()
        let unreadable = Data("not json".utf8)
        fileSystem.setFile(at: registryURL, content: unreadable)
        fileSystem.writeErrorToThrow = CocoaError(.fileWriteNoPermission)
        let catalog = ClaudeSessionCatalog(fileSystem: fileSystem, commandExecutor: MockCommandExecutor(), registryURL: registryURL)

        catalog.loadRegistry()

        XCTAssertFalse(catalog.canSaveRegistry)
        XCTAssertEqual(fileSystem.getFile(at: registryURL), unreadable)
        XCTAssertNotNil(catalog.lastError)
    }

    func testReadableLogLoadsWithoutError() throws {
        let fileSystem = MockFileSystem()
        try ClaudeSessionRegistry().save(to: registryURL, fileSystem: fileSystem)
        let catalog = ClaudeSessionCatalog(fileSystem: fileSystem, commandExecutor: MockCommandExecutor(), registryURL: registryURL)

        catalog.loadRegistry()

        XCTAssertTrue(catalog.canSaveRegistry)
        XCTAssertNil(catalog.lastError)
        XCTAssertNil(fileSystem.getFile(at: backupURL))
    }
}

final class ClaudeSessionSaveThrottleTests: XCTestCase {
    private func session(_ id: String, lastSeen: TimeInterval, running: Bool = true) -> ObservedSession {
        ObservedSession(
            sessionId: id,
            firstSeenAt: Date(timeIntervalSince1970: 0),
            lastSeenRunningAt: Date(timeIntervalSince1970: lastSeen),
            isRunning: running
        )
    }

    func testLastSeenTimesAloneAreNotSignificant() {
        let before = ["a": session("a", lastSeen: 10)]
        let after = ["a": session("a", lastSeen: 15)]
        XCTAssertFalse(ClaudeSessionRegistry.differsBeyondLastSeen(before, after))
    }

    func testStateChangesAreSignificant() {
        let before = ["a": session("a", lastSeen: 10)]
        XCTAssertTrue(ClaudeSessionRegistry.differsBeyondLastSeen(before, ["a": session("a", lastSeen: 10, running: false)]))
        XCTAssertTrue(ClaudeSessionRegistry.differsBeyondLastSeen(before, [:]))
        XCTAssertTrue(ClaudeSessionRegistry.differsBeyondLastSeen(before, ["b": session("b", lastSeen: 10)]))
    }

    func testShouldSave() {
        let now = Date(timeIntervalSince1970: 1000)
        let interval = ClaudeSessionCatalog.routineSaveInterval
        // Significant changes save at once.
        XCTAssertTrue(ClaudeSessionCatalog.shouldSave(changed: true, significant: true, lastSavedAt: now, now: now))
        // No change, no save.
        XCTAssertFalse(ClaudeSessionCatalog.shouldSave(changed: false, significant: false, lastSavedAt: nil, now: now))
        // Routine changes wait for the interval.
        XCTAssertFalse(ClaudeSessionCatalog.shouldSave(changed: true, significant: false,
                                                       lastSavedAt: now.addingTimeInterval(-interval + 1), now: now))
        XCTAssertTrue(ClaudeSessionCatalog.shouldSave(changed: true, significant: false,
                                                      lastSavedAt: now.addingTimeInterval(-interval), now: now))
        XCTAssertTrue(ClaudeSessionCatalog.shouldSave(changed: true, significant: false, lastSavedAt: nil, now: now))
    }

    func testTmuxSessionIsGone() {
        XCTAssertTrue(ClaudeSessionCatalog.tmuxSessionIsGone(stderr: "can't find session: acad"))
        XCTAssertTrue(ClaudeSessionCatalog.tmuxSessionIsGone(stderr: "no server running on /tmp/tmux-501/default"))
        XCTAssertFalse(ClaudeSessionCatalog.tmuxSessionIsGone(stderr: "server exited unexpectedly"))
    }
}

final class ClaudeHookHardeningTests: XCTestCase {
    func testHookCommandUsesSingleQuotes() {
        XCTAssertEqual(
            ClaudeHookInstaller.hookCommand(executable: "/Applications/$HOME `x`/PlexusOneDesktop"),
            "'/Applications/$HOME `x`/PlexusOneDesktop' claude-hook"
        )
        XCTAssertEqual(
            ClaudeHookInstaller.hookCommand(executable: "/Applications/O'Brien Tools/PlexusOneDesktop"),
            #"'/Applications/O'\''Brien Tools/PlexusOneDesktop' claude-hook"#
        )
        XCTAssertTrue(ClaudeHookInstaller.isOurs(ClaudeHookInstaller.hookCommand(executable: "/Applications/PlexusOne Desktop.app/Contents/MacOS/PlexusOneDesktop")))
    }

    func testUnstableLocations() {
        XCTAssertTrue(ClaudeHookInstaller.isUnstableLocation("/private/var/folders/x/AppTranslocation/ABC/d/PlexusOne Desktop.app/Contents/MacOS/PlexusOneDesktop"))
        XCTAssertTrue(ClaudeHookInstaller.isUnstableLocation("/Volumes/PlexusOne Desktop/PlexusOne Desktop.app/Contents/MacOS/PlexusOneDesktop"))
        XCTAssertFalse(ClaudeHookInstaller.isUnstableLocation("/Applications/PlexusOne Desktop.app/Contents/MacOS/PlexusOneDesktop"))
    }

    func testAppendWritesWholeLines() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hook-\(UUID().uuidString)")
        defer {
            do {
                try FileManager.default.removeItem(at: dir)
            } catch {
                XCTFail("could not remove \(dir.path): \(error)")
            }
        }
        let url = dir.appendingPathComponent("events.jsonl")
        let first = ClaudeHookRecorder.Event(sessionId: "a", cwd: "/x", tmux: nil, event: "SessionStart", at: Date(timeIntervalSince1970: 1))
        let second = ClaudeHookRecorder.Event(sessionId: "b", cwd: nil, tmux: "s:@1.%2", event: "UserPromptSubmit", at: Date(timeIntervalSince1970: 2))

        try ClaudeHookRecorder.append(first, to: url)
        // A rotation deletes the file; the next append starts a new one.
        try FileManager.default.removeItem(at: url)
        try ClaudeHookRecorder.append(second, to: url)
        try ClaudeHookRecorder.append(first, to: url)

        let events = ClaudeHookRecorder.decodeEvents(try Data(contentsOf: url))
        XCTAssertEqual(events, [second, first])
    }
}

final class TmuxTargetTests: XCTestCase {
    func testExactSessionTarget() {
        XCTAssertEqual(TmuxEnvironment.exactSessionTarget("acad"), "=acad")
    }

    @MainActor
    func testKillTargetsSessionExactly() async throws {
        let executor = MockCommandExecutor()
        executor.stubTmuxSuccess(arguments: ["kill-session"])
        executor.stubListSessions("")
        let manager = SessionManager(commandExecutor: executor, tmuxPaths: ["/nonexistent/tmux"])

        try await manager.killSession(Session(name: "api"))

        XCTAssertTrue(executor.wasExecuted(path: "/usr/bin/env", arguments: ["tmux", "kill-session", "-t", "=api"]))
    }
}

final class TranscriptLongLastLineTests: XCTestCase {
    func testLastActivityFallsBackToFileDateWhenLastLineIsTooLong() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jsonl")
        defer {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                XCTFail("could not remove \(url.path): \(error)")
            }
        }
        let first = #"{"type":"user","timestamp":"2026-01-01T00:00:00Z","cwd":"/x","message":{"role":"user","content":"hi"}}"#
        // One line longer than the tail window, like a pasted image.
        let huge = #"{"type":"user","timestamp":"2026-01-02T00:00:00Z","message":{"role":"user","content":""# +
            String(repeating: "A", count: ClaudeTranscriptReader.tailBytes + 1024) + #""}}"#
        try Data((first + "\n" + huge + "\n").utf8).write(to: url)
        let modified = Date(timeIntervalSince1970: 1_800_000_000)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)

        let summary = try XCTUnwrap(ClaudeTranscriptReader.read(url: url))

        XCTAssertEqual(summary.lastActivityAt, modified)
    }
}
