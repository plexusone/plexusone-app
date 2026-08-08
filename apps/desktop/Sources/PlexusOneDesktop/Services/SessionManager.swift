import Foundation
import Observation

/// Manages tmux sessions: listing, creating, attaching, and monitoring
@Observable
final class SessionManager {
    private(set) var sessions: [Session] = []
    private(set) var isLoading = false
    private(set) var error: SessionManagerError?

    private var refreshTask: Task<Void, Never>?
    private let refreshInterval: TimeInterval = 5.0

    // Status thresholds (in seconds)
    let idleThreshold: TimeInterval = 30
    let stuckThreshold: TimeInterval = 120

    // Injected dependencies for testing
    private let commandExecutor: any CommandExecuting
    private let tmuxPaths: [String]

    init(
        commandExecutor: any CommandExecuting = ProcessCommandExecutor(),
        tmuxPaths: [String]? = nil
    ) {
        self.commandExecutor = commandExecutor
        self.tmuxPaths = tmuxPaths ?? TmuxEnvironment.searchPaths
    }

    /// Start periodic refresh (call from view's onAppear)
    func startMonitoring() {
        guard refreshTask == nil else { return }
        startPeriodicRefresh()
    }

    deinit {
        refreshTask?.cancel()
    }

    // MARK: - Public API

    /// Clear the current error (call after displaying to user)
    func clearError() {
        error = nil
    }

    /// Refresh the list of tmux sessions
    func refresh() async {
        isLoading = true
        error = nil

        do {
            sessions = try await listTmuxSessions()
        } catch let err as SessionManagerError {
            error = err
        } catch {
            self.error = .unknown(error.localizedDescription)
        }

        isLoading = false
    }

    /// Create a new tmux session
    func createSession(name: String, command: String? = nil) async throws -> Session {
        let sanitizedName = sanitizeSessionName(name)

        // Check if session already exists
        if sessions.contains(where: { $0.tmuxSession == sanitizedName }) {
            throw SessionManagerError.sessionAlreadyExists(sanitizedName)
        }

        let shell = command ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        let result = try await runTmux(["new-session", "-d", "-s", sanitizedName, shell])
        if !result.success {
            throw SessionManagerError.createFailed(result.stderr)
        }

        // Refresh to pick up the new session
        await refresh()

        guard let session = sessions.first(where: { $0.tmuxSession == sanitizedName }) else {
            throw SessionManagerError.createFailed("Session created but not found")
        }

        return session
    }

    /// Kill a tmux session
    func killSession(_ session: Session) async throws {
        let result = try await runTmux(["kill-session", "-t", session.tmuxSession])
        if !result.success {
            throw SessionManagerError.killFailed(result.stderr)
        }

        await refresh()
    }

    /// Rename a tmux session
    func renameSession(_ session: Session, to newName: String) async throws {
        let sanitizedName = sanitizeSessionName(newName)
        let result = try await runTmux(["rename-session", "-t", session.tmuxSession, sanitizedName])
        if !result.success {
            throw SessionManagerError.renameFailed(result.stderr)
        }

        await refresh()
    }

    /// Check if tmux is available by checking known installation paths
    func checkTmuxAvailable() -> Bool {
        TmuxEnvironment.isInstalled()
    }

    // MARK: - Private Methods

    private func startPeriodicRefresh() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(self?.refreshInterval ?? 5.0))
            }
        }
    }

    private func listTmuxSessions() async throws -> [Session] {
        // Check if tmux server is running
        let hasServer = try await runTmux(["list-sessions", "-F", ""])
        if !hasServer.success {
            // No server running = no sessions
            if hasServer.stderr.contains("no server running") {
                return []
            }
        }

        // Get session info: name|activity_timestamp|attached_count
        let result = try await runTmux([
            "list-sessions",
            "-F",
            "#{session_name}|#{session_activity}|#{session_attached}"
        ])

        if !result.success {
            if result.stderr.contains("no server running") {
                return []
            }
            throw SessionManagerError.listFailed(result.stderr)
        }

        return parseSessionOutput(result.stdout)
    }

    /// Determine session status based on elapsed time since last activity
    /// Made internal (not private) for direct testing
    func determineStatus(lastActivity: Date) -> SessionStatus {
        let elapsed = Date().timeIntervalSince(lastActivity)

        if elapsed < idleThreshold {
            return .running
        } else if elapsed < stuckThreshold {
            return .idle
        } else {
            return .stuck
        }
    }

    /// Sanitize session name for tmux compatibility
    /// Made internal (not private) for direct testing
    func sanitizeSessionName(_ name: String) -> String {
        // tmux session names can't contain periods or colons
        name.replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parse tmux list-sessions output into Session objects
    /// Made internal (not private) for direct testing
    /// - Parameters:
    ///   - output: Raw stdout from tmux list-sessions -F "#{session_name}|#{session_activity}|#{session_attached}"
    ///   - referenceDate: Date to use for status calculation (allows deterministic testing)
    /// - Returns: Array of parsed Session objects, sorted by name
    func parseSessionOutput(_ output: String, referenceDate: Date = Date()) -> [Session] {
        let lines = output.split(separator: "\n")
        var sessions: [Session] = []

        for line in lines {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }

            let name = String(parts[0])
            let activityTimestamp = TimeInterval(parts[1]) ?? referenceDate.timeIntervalSince1970
            // parts[2] contains attached count - available for future use if needed

            let lastActivity = Date(timeIntervalSince1970: activityTimestamp)
            let status = determineStatus(lastActivity: lastActivity)

            let session = Session(
                id: .forTmuxSession(named: name),
                name: name,
                tmuxSession: name,
                status: status,
                lastActivity: lastActivity
            )
            sessions.append(session)
        }

        return sessions.sorted { $0.name < $1.name }
    }

    private func runTmux(_ arguments: [String]) async throws -> CommandResult {
        // Try configured tmux locations
        for path in tmuxPaths {
            if FileManager.default.fileExists(atPath: path) {
                return try await commandExecutor.execute(path, arguments: arguments)
            }
        }

        // Fallback to PATH lookup
        return try await commandExecutor.execute("/usr/bin/env", arguments: ["tmux"] + arguments)
    }
}

// MARK: - Supporting Types

struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var success: Bool { exitCode == 0 }
}

enum SessionManagerError: Error, LocalizedError, Equatable {
    case tmuxNotInstalled
    case listFailed(String)
    case createFailed(String)
    case killFailed(String)
    case renameFailed(String)
    case sessionAlreadyExists(String)
    case sessionNotFound(String)
    case commandFailed(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .tmuxNotInstalled:
            return "tmux is not installed. Please install it with: brew install tmux"
        case .listFailed(let msg):
            return "Failed to list sessions: \(msg)"
        case .createFailed(let msg):
            return "Failed to create session: \(msg)"
        case .killFailed(let msg):
            return "Failed to kill session: \(msg)"
        case .renameFailed(let msg):
            return "Failed to rename session: \(msg)"
        case .sessionAlreadyExists(let name):
            return "Session '\(name)' already exists"
        case .sessionNotFound(let name):
            return "Session '\(name)' not found"
        case .commandFailed(let msg):
            return "Command failed: \(msg)"
        case .unknown(let msg):
            return "Unknown error: \(msg)"
        }
    }
}
