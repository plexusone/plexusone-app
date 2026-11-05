import XCTest
@testable import PlexusOneDesktop

@MainActor
final class CompanionTerminalStoreTests: XCTestCase {
    private var launches: [(terminal: AppTerminalView, directory: String)] = []
    private var store: CompanionTerminalStore!
    private let key = CompanionKey(paneId: 1, tmuxSession: "acad")
    private let owner = UUID.forTmuxSession(named: "acad")

    override func setUp() {
        super.setUp()
        launches = []
        // Record launches instead of starting shells.
        store = CompanionTerminalStore { [unowned self] terminal, directory in
            self.launches.append((terminal, directory))
        }
    }

    func testShowStartsShellOnceInDirectory() throws {
        let directory = NSTemporaryDirectory()
        store.show(key, ownerSessionId: owner, directory: directory)

        XCTAssertTrue(store.isVisible(key))
        XCTAssertEqual(launches.count, 1)
        XCTAssertEqual(launches.first?.directory, directory)
        XCTAssertEqual(store.directories[key], directory)

        let terminal = try XCTUnwrap(store.terminal(for: key))
        XCTAssertEqual(terminal.paneId, 1)
        XCTAssertEqual(terminal.focusSessionId, owner)
        XCTAssertFalse(terminal.isSessionAttached)

        // Hiding keeps the shell; showing again reuses it.
        store.hide(key)
        XCTAssertFalse(store.isVisible(key))
        XCTAssertTrue(store.hasShell(key))
        store.show(key, ownerSessionId: owner, directory: "/elsewhere")
        XCTAssertEqual(launches.count, 1)
        XCTAssertTrue(store.terminal(for: key) === terminal)
    }

    func testMissingDirectoryFallsBackToHome() {
        store.show(key, ownerSessionId: owner, directory: "/no/such/directory")
        XCTAssertEqual(launches.first?.directory, FileManager.default.homeDirectoryForCurrentUser.path)
    }

    func testSessionsInSamePaneGetSeparateShells() {
        let other = CompanionKey(paneId: 1, tmuxSession: "other")
        store.show(key, ownerSessionId: owner, directory: nil)
        store.show(other, ownerSessionId: UUID(), directory: nil)

        XCTAssertEqual(launches.count, 2)
        XCTAssertFalse(store.terminal(for: key) === store.terminal(for: other))
    }

    func testCloseEndsShell() {
        store.show(key, ownerSessionId: owner, directory: nil)
        store.close(key)

        XCTAssertFalse(store.isVisible(key))
        XCTAssertFalse(store.hasShell(key))
        XCTAssertNil(store.directories[key])
    }

    func testPruneEndsShellsOfEndedSessions() {
        let kept = CompanionKey(paneId: 2, tmuxSession: "kept")
        store.show(key, ownerSessionId: owner, directory: nil)
        store.show(kept, ownerSessionId: UUID(), directory: nil)

        store.prune(keepingSessions: ["kept"])

        XCTAssertFalse(store.hasShell(key))
        XCTAssertTrue(store.hasShell(kept))
    }

    func testCloseAll() {
        store.show(key, ownerSessionId: owner, directory: nil)
        store.show(CompanionKey(paneId: 2, tmuxSession: "b"), ownerSessionId: UUID(), directory: nil)

        store.closeAll()

        XCTAssertTrue(store.visible.isEmpty)
        XCTAssertFalse(store.hasShell(key))
    }

    func testFractionFollowsDefaultUntilResized() {
        XCTAssertNil(store.customFraction(forPane: 1))
        XCTAssertEqual(store.fraction(forPane: 1, defaultPercent: 35), 0.35, accuracy: 0.0001)
        // A pane that was not resized follows a changed default.
        XCTAssertEqual(store.fraction(forPane: 1, defaultPercent: 50), 0.5, accuracy: 0.0001)

        store.setFraction(0.6, forPane: 1)
        XCTAssertEqual(store.fraction(forPane: 1, defaultPercent: 35), 0.6, accuracy: 0.0001)
        XCTAssertEqual(store.fraction(forPane: 2, defaultPercent: 35), 0.35, accuracy: 0.0001)

        store.resetFraction(forPane: 1)
        XCTAssertNil(store.customFraction(forPane: 1))
        XCTAssertEqual(store.fraction(forPane: 1, defaultPercent: 40), 0.4, accuracy: 0.0001)
    }

    func testFractionsAreClamped() {
        store.setFraction(0.99, forPane: 1)
        XCTAssertEqual(store.customFraction(forPane: 1), CompanionTerminalStore.fractionRange.upperBound)
        store.setFraction(-1, forPane: 1)
        XCTAssertEqual(store.customFraction(forPane: 1), CompanionTerminalStore.fractionRange.lowerBound)
        XCTAssertEqual(CompanionTerminalStore.fraction(percent: 5), CompanionTerminalStore.fractionRange.lowerBound)
        XCTAssertEqual(CompanionTerminalStore.fraction(percent: 100), CompanionTerminalStore.fractionRange.upperBound)
    }

    func testPercentRangeMatchesFractionRange() {
        XCTAssertEqual(CompanionTerminalStore.heightPercentRange.lowerBound / 100,
                       Double(CompanionTerminalStore.fractionRange.lowerBound), accuracy: 0.0001)
        XCTAssertEqual(CompanionTerminalStore.heightPercentRange.upperBound / 100,
                       Double(CompanionTerminalStore.fractionRange.upperBound), accuracy: 0.0001)
        XCTAssertTrue(CompanionTerminalStore.heightPercentRange.contains(CompanionTerminalStore.standardHeightPercent))
    }
}

final class CompanionShellLaunchTests: XCTestCase {
    func testLoginShellPrefersShellVariable() {
        let path = CompanionTerminalStore.loginShellPath(
            environment: ["SHELL": "/opt/homebrew/bin/fish"],
            accountShell: "/bin/zsh",
            isExecutable: { _ in true }
        )
        XCTAssertEqual(path, "/opt/homebrew/bin/fish")
    }

    func testLoginShellFallsBackToAccountShell() {
        let path = CompanionTerminalStore.loginShellPath(
            environment: ["SHELL": "/missing/shell"],
            accountShell: "/bin/bash",
            isExecutable: { $0 == "/bin/bash" }
        )
        XCTAssertEqual(path, "/bin/bash")
    }

    func testLoginShellFallsBackToZsh() {
        let path = CompanionTerminalStore.loginShellPath(
            environment: [:],
            accountShell: nil,
            isExecutable: { _ in false }
        )
        XCTAssertEqual(path, "/bin/zsh")
    }

    func testShellEnvironmentDropsTmuxVariables() {
        let env = CompanionTerminalStore.shellEnvironment(base: [
            "TMUX": "/tmp/tmux-501/default,1,0",
            "TMUX_PANE": "%3",
            "TERM": "xterm-256color"
        ])
        XCTAssertEqual(env, ["TERM=xterm-256color"])
    }

    func testUsableDirectory() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let temp = NSTemporaryDirectory()
        XCTAssertEqual(CompanionTerminalStore.usableDirectory(temp), temp)
        XCTAssertEqual(CompanionTerminalStore.usableDirectory(nil), home)
        XCTAssertEqual(CompanionTerminalStore.usableDirectory(""), home)
        // A file is not a folder to start in.
        let file = temp + "/companion-\(UUID().uuidString)"
        XCTAssertTrue(FileManager.default.createFile(atPath: file, contents: Data()))
        defer {
            do {
                try FileManager.default.removeItem(atPath: file)
            } catch {
                XCTFail("could not remove \(file): \(error)")
            }
        }
        XCTAssertEqual(CompanionTerminalStore.usableDirectory(file), home)
    }
}

@MainActor
final class SessionManagerCurrentPathTests: XCTestCase {
    func testCurrentPathTargetsSessionExactly() async {
        let executor = MockCommandExecutor()
        executor.stubTmuxSuccess(arguments: ["display-message"], stdout: "/Users/me/project\n")
        let manager = SessionManager(commandExecutor: executor, tmuxPaths: ["/nonexistent/tmux"])

        let path = await manager.currentPath(ofSession: "acad")

        XCTAssertEqual(path, "/Users/me/project")
        XCTAssertTrue(executor.wasExecuted(
            path: "/usr/bin/env",
            arguments: ["tmux", "display-message", "-p", "-t", "=acad:", "#{pane_current_path}"]
        ))
    }

    func testCurrentPathNilWhenTmuxFails() async {
        let executor = MockCommandExecutor()
        executor.stubTmuxFailure(arguments: ["display-message"], stderr: "can't find session: acad")
        let manager = SessionManager(commandExecutor: executor, tmuxPaths: ["/nonexistent/tmux"])

        let path = await manager.currentPath(ofSession: "acad")
        XCTAssertNil(path)
    }

    func testCurrentPathNilWhenEmpty() async {
        let executor = MockCommandExecutor()
        executor.stubTmuxSuccess(arguments: ["display-message"], stdout: "\n")
        let manager = SessionManager(commandExecutor: executor, tmuxPaths: ["/nonexistent/tmux"])

        let path = await manager.currentPath(ofSession: "acad")
        XCTAssertNil(path)
    }
}
