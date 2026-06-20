import XCTest
@testable import PlexusOneDesktop

final class AppStateTests: XCTestCase {

    // MARK: - Initialization Tests

    func testAppStateInitializesWithDefaultDependencies() {
        let appState = AppState()

        XCTAssertNotNil(appState.sessionManager)
        XCTAssertNotNil(appState.windowStateManager)
        XCTAssertFalse(appState.isInitialized)
        XCTAssertNil(appState.pendingPopOutSession)
    }

    func testAppStateInitializesWithCustomDependencies() {
        let mockExecutor = MockCommandExecutor()
        let sessionManager = SessionManager(commandExecutor: mockExecutor)
        let mockFileSystem = MockFileSystem()
        let windowStateManager = WindowStateManager(
            fileSystem: mockFileSystem,
            stateDirectory: URL(fileURLWithPath: "/tmp/test")
        )

        let appState = AppState(
            sessionManager: sessionManager,
            windowStateManager: windowStateManager
        )

        XCTAssertTrue(appState.sessionManager === sessionManager)
        // windowStateManager is a value type, so we can just verify it exists
        XCTAssertNotNil(appState.windowStateManager)
    }

    // MARK: - Monitoring Tests

    func testStartMonitoringInitializesOnce() async {
        let mockExecutor = MockCommandExecutor()
        mockExecutor.stubNoServerRunning()

        let sessionManager = SessionManager(
            commandExecutor: mockExecutor,
            tmuxPaths: ["/opt/homebrew/bin/tmux"]
        )

        let appState = AppState(sessionManager: sessionManager)

        XCTAssertFalse(appState.isInitialized)

        await appState.startMonitoring()

        XCTAssertTrue(appState.isInitialized)

        // Second call should be no-op
        let executionCountBefore = mockExecutor.executedCommands.count
        await appState.startMonitoring()
        let executionCountAfter = mockExecutor.executedCommands.count

        XCTAssertEqual(executionCountBefore, executionCountAfter)
    }

    func testStartMonitoringWithTmuxAvailable() async {
        let mockExecutor = MockCommandExecutor()
        mockExecutor.stubNoServerRunning()

        let sessionManager = SessionManager(
            commandExecutor: mockExecutor,
            tmuxPaths: ["/opt/homebrew/bin/tmux"]
        )

        let appState = AppState(sessionManager: sessionManager)

        await appState.startMonitoring()

        XCTAssertTrue(appState.isInitialized)
        // checkTmuxAvailable now uses TmuxEnvironment.isInstalled() directly
        // (no command execution needed)
    }

    func testStartMonitoringCompletesEvenWithoutTmux() async {
        let mockExecutor = MockCommandExecutor()
        // Don't stub any tmux commands - simulates tmux not available

        let sessionManager = SessionManager(
            commandExecutor: mockExecutor,
            tmuxPaths: ["/nonexistent/tmux"]
        )

        let appState = AppState(sessionManager: sessionManager)

        await appState.startMonitoring()

        // Should still complete initialization even if tmux unavailable
        XCTAssertTrue(appState.isInitialized)
    }

    // MARK: - Pending Pop-Out Session Tests

    func testPendingPopOutSession() {
        let appState = AppState()

        XCTAssertNil(appState.pendingPopOutSession)

        let session = Session(name: "test-session")
        appState.pendingPopOutSession = session

        XCTAssertEqual(appState.pendingPopOutSession?.name, "test-session")

        appState.pendingPopOutSession = nil
        XCTAssertNil(appState.pendingPopOutSession)
    }

    // MARK: - Integration Tests

    func testAppStateIntegration() async {
        let mockExecutor = MockCommandExecutor()
        let now = Date()
        let timestamp = Int(now.timeIntervalSince1970) - 10

        // Set up mocks for session listing
        mockExecutor.stubTmuxSuccess(arguments: ["list-sessions"])
        mockExecutor.stubListSessions("session-1|\(timestamp)|0\nsession-2|\(timestamp)|1")

        let sessionManager = SessionManager(
            commandExecutor: mockExecutor,
            tmuxPaths: ["/opt/homebrew/bin/tmux"]
        )

        let mockFileSystem = MockFileSystem()
        let windowStateManager = WindowStateManager(
            fileSystem: mockFileSystem,
            stateDirectory: URL(fileURLWithPath: "/tmp/test-integration")
        )

        let appState = AppState(
            sessionManager: sessionManager,
            windowStateManager: windowStateManager
        )

        await appState.startMonitoring()

        XCTAssertTrue(appState.isInitialized)
        XCTAssertEqual(appState.sessionManager.sessions.count, 2)
    }
}
