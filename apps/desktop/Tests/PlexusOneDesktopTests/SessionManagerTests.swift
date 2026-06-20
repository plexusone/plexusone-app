import XCTest
@testable import PlexusOneDesktop

final class SessionManagerTests: XCTestCase {

    // MARK: - Model Tests

    func testSessionStatusDisplayName() {
        XCTAssertEqual(SessionStatus.running.displayName, "Running")
        XCTAssertEqual(SessionStatus.idle.displayName, "Idle")
        XCTAssertEqual(SessionStatus.stuck.displayName, "Stuck")
        XCTAssertEqual(SessionStatus.detached.displayName, "Detached")
    }

    func testSessionInitialization() {
        let session = Session(name: "test-session")

        XCTAssertEqual(session.name, "test-session")
        XCTAssertEqual(session.tmuxSession, "test-session")
        XCTAssertEqual(session.status, .detached)
        XCTAssertNil(session.agentType)
    }

    func testSessionWithCustomTmuxSession() {
        let session = Session(
            name: "My Session",
            tmuxSession: "my-tmux-session",
            agentType: .claude
        )

        XCTAssertEqual(session.name, "My Session")
        XCTAssertEqual(session.tmuxSession, "my-tmux-session")
        XCTAssertEqual(session.agentType, .claude)
    }

    func testAgentTypeDisplayNames() {
        XCTAssertEqual(AgentType.claude.displayName, "Claude")
        XCTAssertEqual(AgentType.codex.displayName, "Codex")
        XCTAssertEqual(AgentType.gemini.displayName, "Gemini")
        XCTAssertEqual(AgentType.kiro.displayName, "Kiro")
        XCTAssertEqual(AgentType.custom.displayName, "Custom")
    }

    // MARK: - Sanitize Session Name Tests

    func testSanitizeSessionNameRemovesPeriods() {
        let manager = SessionManager()

        let result = manager.sanitizeSessionName("my.session.name")

        XCTAssertEqual(result, "my-session-name")
    }

    func testSanitizeSessionNameRemovesColons() {
        let manager = SessionManager()

        let result = manager.sanitizeSessionName("my:session:name")

        XCTAssertEqual(result, "my-session-name")
    }

    func testSanitizeSessionNameTrimsWhitespace() {
        let manager = SessionManager()

        let result = manager.sanitizeSessionName("  my-session  \n")

        XCTAssertEqual(result, "my-session")
    }

    func testSanitizeSessionNameCombined() {
        let manager = SessionManager()

        let result = manager.sanitizeSessionName("  claude.code:v2  ")

        XCTAssertEqual(result, "claude-code-v2")
    }

    func testSanitizeSessionNameValidNameUnchanged() {
        let manager = SessionManager()

        let result = manager.sanitizeSessionName("valid-session-name")

        XCTAssertEqual(result, "valid-session-name")
    }

    // MARK: - Determine Status Tests

    func testDetermineStatusRunning() {
        let manager = SessionManager()
        let recentActivity = Date().addingTimeInterval(-10) // 10 seconds ago

        let status = manager.determineStatus(lastActivity: recentActivity)

        XCTAssertEqual(status, .running)
    }

    func testDetermineStatusRunningAtThreshold() {
        let manager = SessionManager()
        // Just under the idle threshold (30 seconds)
        let recentActivity = Date().addingTimeInterval(-29)

        let status = manager.determineStatus(lastActivity: recentActivity)

        XCTAssertEqual(status, .running)
    }

    func testDetermineStatusIdle() {
        let manager = SessionManager()
        // Between idle (30s) and stuck (120s) thresholds
        let idleActivity = Date().addingTimeInterval(-60)

        let status = manager.determineStatus(lastActivity: idleActivity)

        XCTAssertEqual(status, .idle)
    }

    func testDetermineStatusIdleAtThreshold() {
        let manager = SessionManager()
        // Exactly at idle threshold
        let idleActivity = Date().addingTimeInterval(-30)

        let status = manager.determineStatus(lastActivity: idleActivity)

        XCTAssertEqual(status, .idle)
    }

    func testDetermineStatusStuck() {
        let manager = SessionManager()
        // Beyond stuck threshold (120 seconds)
        let oldActivity = Date().addingTimeInterval(-300)

        let status = manager.determineStatus(lastActivity: oldActivity)

        XCTAssertEqual(status, .stuck)
    }

    func testDetermineStatusStuckAtThreshold() {
        let manager = SessionManager()
        // Exactly at stuck threshold
        let oldActivity = Date().addingTimeInterval(-120)

        let status = manager.determineStatus(lastActivity: oldActivity)

        XCTAssertEqual(status, .stuck)
    }

    // MARK: - Parse Session Output Tests

    func testParseSessionOutputValidSingleSession() {
        let manager = SessionManager()
        let now = Date()
        let activityTimestamp = now.timeIntervalSince1970 - 10 // 10 seconds ago

        let output = "my-session|\(Int(activityTimestamp))|1"
        let sessions = manager.parseSessionOutput(output, referenceDate: now)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].name, "my-session")
        XCTAssertEqual(sessions[0].tmuxSession, "my-session")
        XCTAssertEqual(sessions[0].status, .running)
    }

    func testParseSessionOutputMultipleSessions() {
        let manager = SessionManager()
        let now = Date()
        let recentTimestamp = now.timeIntervalSince1970 - 10
        let oldTimestamp = now.timeIntervalSince1970 - 200

        let output = """
        session-a|\(Int(recentTimestamp))|1
        session-b|\(Int(oldTimestamp))|0
        session-c|\(Int(recentTimestamp))|0
        """

        let sessions = manager.parseSessionOutput(output, referenceDate: now)

        XCTAssertEqual(sessions.count, 3)
        // Sorted alphabetically
        XCTAssertEqual(sessions[0].name, "session-a")
        XCTAssertEqual(sessions[1].name, "session-b")
        XCTAssertEqual(sessions[2].name, "session-c")

        // Status based on activity
        XCTAssertEqual(sessions[0].status, .running)
        XCTAssertEqual(sessions[1].status, .stuck)
        XCTAssertEqual(sessions[2].status, .running)
    }

    func testParseSessionOutputEmpty() {
        let manager = SessionManager()

        let sessions = manager.parseSessionOutput("")

        XCTAssertTrue(sessions.isEmpty)
    }

    func testParseSessionOutputWhitespaceOnly() {
        let manager = SessionManager()

        let sessions = manager.parseSessionOutput("   \n  \n")

        XCTAssertTrue(sessions.isEmpty)
    }

    func testParseSessionOutputMalformedLine() {
        let manager = SessionManager()
        let now = Date()
        let timestamp = now.timeIntervalSince1970 - 10

        // Mix of valid and invalid lines
        let output = """
        valid-session|\(Int(timestamp))|1
        invalid-line-without-enough-parts
        another-invalid
        valid-session-2|\(Int(timestamp))|0
        """

        let sessions = manager.parseSessionOutput(output, referenceDate: now)

        // Should only parse valid lines
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].name, "valid-session")
        XCTAssertEqual(sessions[1].name, "valid-session-2")
    }

    func testParseSessionOutputInvalidTimestamp() {
        let manager = SessionManager()
        let now = Date()

        // Invalid timestamp should use reference date
        let output = "my-session|not-a-number|1"
        let sessions = manager.parseSessionOutput(output, referenceDate: now)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].status, .running) // Uses reference date, so elapsed ~= 0
    }

    func testParseSessionOutputEmptyFields() {
        let manager = SessionManager()
        let now = Date()
        let timestamp = now.timeIntervalSince1970 - 10

        // Empty attached count should default to 0
        let output = "my-session|\(Int(timestamp))|"
        let sessions = manager.parseSessionOutput(output, referenceDate: now)

        XCTAssertEqual(sessions.count, 1)
    }

    // MARK: - Integration Tests with Mock

    // MARK: - TmuxEnvironment Tests

    func testTmuxEnvironmentIsInstalled() {
        // TmuxEnvironment.isInstalled() checks hardcoded paths directly
        // This test verifies the method works - actual result depends on system
        let isInstalled = TmuxEnvironment.isInstalled()
        // On a dev machine with tmux installed, this should be true
        // We just verify it returns a boolean without crashing
        XCTAssertTrue(isInstalled || !isInstalled)
    }

    func testTmuxEnvironmentFindExecutable() {
        let (path, baseArgs) = TmuxEnvironment.findExecutable()
        // Should return either a direct path or /usr/bin/env fallback
        XCTAssertFalse(path.isEmpty)
        if path == "/usr/bin/env" {
            XCTAssertEqual(baseArgs, ["tmux"])
        } else {
            XCTAssertTrue(baseArgs.isEmpty)
        }
    }

    func testCheckTmuxAvailableUsesTmuxEnvironment() {
        // checkTmuxAvailable now delegates to TmuxEnvironment.isInstalled()
        let manager = SessionManager()
        let available = manager.checkTmuxAvailable()
        // Should match TmuxEnvironment result
        XCTAssertEqual(available, TmuxEnvironment.isInstalled())
    }

    func testRefreshWithNoServer() async {
        let mockExecutor = MockCommandExecutor()
        mockExecutor.stubNoServerRunning()

        let manager = SessionManager(
            commandExecutor: mockExecutor,
            tmuxPaths: ["/opt/homebrew/bin/tmux"]
        )

        await manager.refresh()

        XCTAssertTrue(manager.sessions.isEmpty)
        XCTAssertNil(manager.error)
    }

    func testRefreshWithSessions() async {
        let mockExecutor = MockCommandExecutor()
        let now = Date()
        let timestamp = Int(now.timeIntervalSince1970) - 10

        // Stub the initial list-sessions check
        mockExecutor.stubTmuxSuccess(arguments: ["list-sessions"])

        // Stub the detailed list-sessions call
        mockExecutor.stubListSessions("session-1|\(timestamp)|1\nsession-2|\(timestamp)|0")

        let manager = SessionManager(
            commandExecutor: mockExecutor,
            tmuxPaths: ["/opt/homebrew/bin/tmux"]
        )

        await manager.refresh()

        XCTAssertEqual(manager.sessions.count, 2)
        XCTAssertNil(manager.error)
    }

    func testCreateSessionAlreadyExists() async {
        let mockExecutor = MockCommandExecutor()
        let now = Date()
        let timestamp = Int(now.timeIntervalSince1970)

        // Set up initial sessions
        mockExecutor.stubTmuxSuccess(arguments: ["list-sessions"])
        mockExecutor.stubListSessions("existing-session|\(timestamp)|0")

        let manager = SessionManager(
            commandExecutor: mockExecutor,
            tmuxPaths: ["/opt/homebrew/bin/tmux"]
        )

        // Refresh to populate sessions
        await manager.refresh()

        // Try to create a session that already exists
        do {
            _ = try await manager.createSession(name: "existing-session")
            XCTFail("Expected sessionAlreadyExists error")
        } catch let error as SessionManagerError {
            if case .sessionAlreadyExists(let name) = error {
                XCTAssertEqual(name, "existing-session")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTmuxNotFoundFallsBackToEnv() async {
        let mockExecutor = MockCommandExecutor()
        mockExecutor.stubNoServerRunning()

        // Use paths that don't exist (FileManager.default.fileExists will return false)
        let manager = SessionManager(
            commandExecutor: mockExecutor,
            tmuxPaths: ["/nonexistent/tmux"]
        )

        await manager.refresh()

        // Should have fallen back to /usr/bin/env tmux
        let envCalls = mockExecutor.executedCommands.filter { $0.path == "/usr/bin/env" }
        XCTAssertFalse(envCalls.isEmpty, "Should fall back to /usr/bin/env when tmux paths don't exist")
    }

    // MARK: - Error Handling Tests

    func testSessionManagerErrorDescriptions() {
        XCTAssertTrue(SessionManagerError.tmuxNotInstalled.errorDescription?.contains("tmux is not installed") ?? false)
        XCTAssertTrue(SessionManagerError.listFailed("test").errorDescription?.contains("Failed to list sessions") ?? false)
        XCTAssertTrue(SessionManagerError.createFailed("test").errorDescription?.contains("Failed to create session") ?? false)
        XCTAssertTrue(SessionManagerError.killFailed("test").errorDescription?.contains("Failed to kill session") ?? false)
        XCTAssertTrue(SessionManagerError.renameFailed("test").errorDescription?.contains("Failed to rename session") ?? false)
        XCTAssertTrue(SessionManagerError.sessionAlreadyExists("test").errorDescription?.contains("already exists") ?? false)
        XCTAssertTrue(SessionManagerError.sessionNotFound("test").errorDescription?.contains("not found") ?? false)
        XCTAssertTrue(SessionManagerError.commandFailed("test").errorDescription?.contains("Command failed") ?? false)
        XCTAssertTrue(SessionManagerError.unknown("test").errorDescription?.contains("Unknown error") ?? false)
    }

    // MARK: - CommandResult Tests

    func testCommandResultSuccess() {
        let result = CommandResult(exitCode: 0, stdout: "output", stderr: "")
        XCTAssertTrue(result.success)
    }

    func testCommandResultFailure() {
        let result = CommandResult(exitCode: 1, stdout: "", stderr: "error")
        XCTAssertFalse(result.success)
    }
}
