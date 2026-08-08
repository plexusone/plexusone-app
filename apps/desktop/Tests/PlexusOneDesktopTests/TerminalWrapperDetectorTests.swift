import XCTest
@testable import PlexusOneDesktop

final class TerminalWrapperDetectorTests: XCTestCase {

    // MARK: - TerminalWrapper.detect

    func testDetectKiroCliTerm() {
        XCTAssertEqual(TerminalWrapper.detect(inCommand: "zsh (kiro-cli-term)"), .kiroCli)
    }

    func testDetectFigterm() {
        XCTAssertEqual(TerminalWrapper.detect(inCommand: "figterm"), .fig)
    }

    func testDetectAmazonQ() {
        XCTAssertEqual(TerminalWrapper.detect(inCommand: "bash (qterm)"), .amazonQ)
    }

    func testDetectPlainShellIsNil() {
        XCTAssertNil(TerminalWrapper.detect(inCommand: "-zsh"))
        XCTAssertNil(TerminalWrapper.detect(inCommand: "/bin/zsh"))
        XCTAssertNil(TerminalWrapper.detect(inCommand: "claude"))
    }

    func testMetadata() {
        XCTAssertEqual(TerminalWrapper.kiroCli.displayName, "Kiro CLI")
        XCTAssertEqual(TerminalWrapper.kiroCli.processMarker, "kiro-cli-term")
        XCTAssertEqual(TerminalWrapper.kiroCli.remediation, "kiro-cli integration uninstall dotfiles")
        XCTAssertTrue(TerminalWrapper.kiroCli.warning.contains("kiro-cli-term"))
    }

    // MARK: - TerminalWrapperDetector.parse

    func testParseFlagsOnlyWrappedSessions() {
        let paneList = """
        work|111
        pbhqweb|222
        mkt|333
        """
        let psOutput = """
          111 -zsh
          222 zsh (kiro-cli-term)
          333 /bin/zsh
          999 figterm
        """

        let result = TerminalWrapperDetector.parse(paneList: paneList, psOutput: psOutput)

        XCTAssertEqual(result, ["pbhqweb": .kiroCli])
        XCTAssertNil(result["work"])
        XCTAssertNil(result["mkt"])
    }

    func testParseFirstWrappedPaneWins() {
        // A session with multiple panes; one is wrapped.
        let paneList = """
        multi|10
        multi|11
        """
        let psOutput = """
          10 /bin/zsh
          11 zsh (kiro-cli-term)
        """
        let result = TerminalWrapperDetector.parse(paneList: paneList, psOutput: psOutput)
        XCTAssertEqual(result["multi"], .kiroCli)
    }

    func testParseHandlesEmptyInput() {
        XCTAssertTrue(TerminalWrapperDetector.parse(paneList: "", psOutput: "").isEmpty)
    }

    func testParseIgnoresMalformedLines() {
        let result = TerminalWrapperDetector.parse(
            paneList: "no-pipe-here\nsess|notanumber\ngood|55",
            psOutput: "  55 zsh (kiro-cli-term)\ngarbage line"
        )
        XCTAssertEqual(result, ["good": .kiroCli])
    }

    // MARK: - Async detection through the command executor

    func testDetectWrappersEndToEnd() async {
        let mock = MockCommandExecutor()
        // tmuxPaths [] forces the /usr/bin/env fallback for tmux.
        mock.stub(path: "/usr/bin/env", result: CommandResult(
            exitCode: 0,
            stdout: "pbhqweb|222\nwork|111",
            stderr: ""
        ))
        mock.stub(path: "/bin/ps", result: CommandResult(
            exitCode: 0,
            stdout: "  111 -zsh\n  222 zsh (kiro-cli-term)",
            stderr: ""
        ))

        let detector = TerminalWrapperDetector(commandExecutor: mock, tmuxPaths: [])
        let result = await detector.detectWrappers()

        XCTAssertEqual(result, ["pbhqweb": .kiroCli])
    }

    func testDetectWrappersReturnsEmptyOnTmuxFailure() async {
        let mock = MockCommandExecutor()
        mock.stub(path: "/usr/bin/env", result: CommandResult(
            exitCode: 1, stdout: "", stderr: "no server running"
        ))
        let detector = TerminalWrapperDetector(commandExecutor: mock, tmuxPaths: [])
        let result = await detector.detectWrappers()
        XCTAssertTrue(result.isEmpty)
    }
}
