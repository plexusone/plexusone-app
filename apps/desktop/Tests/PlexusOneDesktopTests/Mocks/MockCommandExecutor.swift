import Foundation
@testable import PlexusOneDesktop

/// Mock implementation of CommandExecuting for testing
final class MockCommandExecutor: CommandExecuting, @unchecked Sendable {
    /// Recorded calls for verification
    private(set) var executedCommands: [(path: String, arguments: [String])] = []

    /// Stub responses keyed by command path or pattern
    private var stubbedResults: [String: CommandResult] = [:]

    /// Default result when no stub matches
    var defaultResult: CommandResult = CommandResult(
        exitCode: 0,
        stdout: "",
        stderr: ""
    )

    /// Error to throw (if set, takes precedence over results)
    var errorToThrow: Error?

    // MARK: - Stubbing

    /// Stub a result for a specific command path
    func stub(path: String, result: CommandResult) {
        stubbedResults[path] = result
    }

    /// Stub a result for tmux commands (convenience method)
    func stubTmux(arguments: [String], result: CommandResult) {
        // Store by the first tmux argument as key
        let key = arguments.first ?? "tmux"
        stubbedResults["tmux:\(key)"] = result
    }

    /// Stub tmux list-sessions output
    func stubListSessions(_ output: String, exitCode: Int32 = 0) {
        stubbedResults["tmux:list-sessions"] = CommandResult(
            exitCode: exitCode,
            stdout: output,
            stderr: ""
        )
    }

    /// Stub tmux list-sessions with no server running
    func stubNoServerRunning() {
        stubbedResults["tmux:list-sessions"] = CommandResult(
            exitCode: 1,
            stdout: "",
            stderr: "no server running on /tmp/tmux-501/default"
        )
    }

    /// Stub tmux command success
    func stubTmuxSuccess(arguments: [String], stdout: String = "") {
        let key = arguments.first ?? "tmux"
        stubbedResults["tmux:\(key)"] = CommandResult(
            exitCode: 0,
            stdout: stdout,
            stderr: ""
        )
    }

    /// Stub tmux command failure
    func stubTmuxFailure(arguments: [String], stderr: String) {
        let key = arguments.first ?? "tmux"
        stubbedResults["tmux:\(key)"] = CommandResult(
            exitCode: 1,
            stdout: "",
            stderr: stderr
        )
    }

    // MARK: - CommandExecuting

    func execute(_ path: String, arguments: [String]) async throws -> CommandResult {
        // Record the call
        executedCommands.append((path: path, arguments: arguments))

        // Throw error if configured
        if let error = errorToThrow {
            throw error
        }

        // Check for exact path match
        if let result = stubbedResults[path] {
            return result
        }

        // Check for tmux-prefixed match (when tmux is in path or arguments)
        if path.contains("tmux") || arguments.first == "tmux" {
            let tmuxArg = path.contains("tmux") ? arguments.first : arguments.dropFirst().first
            if let arg = tmuxArg, let result = stubbedResults["tmux:\(arg)"] {
                return result
            }
        }

        return defaultResult
    }

    // MARK: - Verification

    /// Reset all recorded calls and stubs
    func reset() {
        executedCommands = []
        stubbedResults = [:]
        errorToThrow = nil
    }

    /// Check if a command was executed
    func wasExecuted(path: String) -> Bool {
        executedCommands.contains { $0.path == path }
    }

    /// Check if a command was executed with specific arguments
    func wasExecuted(path: String, arguments: [String]) -> Bool {
        executedCommands.contains { $0.path == path && $0.arguments == arguments }
    }

    /// Get number of times a command path was executed
    func executionCount(path: String) -> Int {
        executedCommands.filter { $0.path == path }.count
    }

    /// Get number of times tmux was called with a specific subcommand
    func tmuxExecutionCount(subcommand: String) -> Int {
        executedCommands.filter { cmd in
            (cmd.path.contains("tmux") && cmd.arguments.first == subcommand) ||
            (cmd.arguments.first == "tmux" && cmd.arguments.dropFirst().first == subcommand)
        }.count
    }
}
