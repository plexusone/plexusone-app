import Foundation

/// Detects `figterm`-style PTY autocomplete wrappers (see `TerminalWrapper`) in
/// running tmux panes, so the UI can warn that a session is at risk of freezing.
///
/// The wrapper re-execs as the pane's top process, so its marker appears in the
/// `ps` command of `#{pane_pid}` — no process-tree walking is required.
struct TerminalWrapperDetector: Sendable {
    private let commandExecutor: any CommandExecuting
    private let tmuxPaths: [String]

    init(
        commandExecutor: any CommandExecuting = ProcessCommandExecutor(),
        tmuxPaths: [String]? = nil
    ) {
        self.commandExecutor = commandExecutor
        self.tmuxPaths = tmuxPaths ?? TmuxEnvironment.searchPaths
    }

    /// Map of tmux session name → detected wrapper, for every session with at
    /// least one wrapped pane. Sessions without a wrapper are omitted. Returns an
    /// empty map on any failure, so detection never blocks session listing.
    func detectWrappers() async -> [String: TerminalWrapper] {
        do {
            let panes = try await runTmux(["list-panes", "-a", "-F", "#{session_name}|#{pane_pid}"])
            guard panes.success, !panes.stdout.isEmpty else { return [:] }

            let ps = try await commandExecutor.execute("/bin/ps", arguments: ["-Ao", "pid=,command="])
            guard ps.success else { return [:] }

            return Self.parse(paneList: panes.stdout, psOutput: ps.stdout)
        } catch {
            return [:]
        }
    }

    /// Pure parsing step, separated for deterministic testing.
    /// - Parameters:
    ///   - paneList: `#{session_name}|#{pane_pid}` lines from `tmux list-panes -a`.
    ///   - psOutput: `pid command…` lines from `ps -Ao pid=,command=`.
    /// - Returns: session name → the wrapper found in its first wrapped pane.
    static func parse(paneList: String, psOutput: String) -> [String: TerminalWrapper] {
        // Build pid → command from ps output.
        var commandByPID: [Int: String] = [:]
        for line in psOutput.split(separator: "\n") {
            let trimmed = line.drop { $0 == " " }
            guard let space = trimmed.firstIndex(of: " "),
                  let pid = Int(trimmed[..<space]) else { continue }
            commandByPID[pid] = String(trimmed[trimmed.index(after: space)...])
        }

        // For each pane, flag its session if the pane process is a known wrapper.
        var result: [String: TerminalWrapper] = [:]
        for line in paneList.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let pid = Int(parts[1]) else { continue }
            let session = String(parts[0])
            guard result[session] == nil else { continue } // first wrapped pane wins
            if let command = commandByPID[pid],
               let wrapper = TerminalWrapper.detect(inCommand: command) {
                result[session] = wrapper
            }
        }
        return result
    }

    private func runTmux(_ arguments: [String]) async throws -> CommandResult {
        for path in tmuxPaths where FileManager.default.fileExists(atPath: path) {
            return try await commandExecutor.execute(path, arguments: arguments)
        }
        return try await commandExecutor.execute("/usr/bin/env", arguments: ["tmux"] + arguments)
    }
}
