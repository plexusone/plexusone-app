import Foundation

/// Shared utility for tmux executable discovery and environment configuration.
/// Centralizes tmux path lookup logic used by SessionManager, AppTerminalView, and AppDelegate.
enum TmuxEnvironment {
    /// Standard tmux installation paths in priority order
    static let searchPaths: [String] = [
        "/opt/homebrew/bin/tmux",   // Homebrew Apple Silicon
        "/usr/local/bin/tmux",      // Homebrew Intel
        "/usr/bin/tmux"             // System installation
    ]

    /// Find the tmux executable path.
    /// - Returns: Tuple of (executable path, base arguments). If tmux is found directly,
    ///   returns the path with empty args. If not found, returns `/usr/bin/env` with `["tmux"]`
    ///   as a fallback to search PATH.
    static func findExecutable() -> (path: String, baseArgs: [String]) {
        for path in searchPaths {
            if FileManager.default.fileExists(atPath: path) {
                return (path, [])
            }
        }
        // Fallback - use env to find tmux in PATH
        return ("/usr/bin/env", ["tmux"])
    }

    /// Check if tmux is installed at any of the known paths.
    /// - Returns: `true` if tmux executable exists, `false` otherwise.
    static func isInstalled() -> Bool {
        searchPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// Get the path to the tmux executable, or `nil` if not found.
    static var executablePath: String? {
        searchPaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Environment variables for terminal processes.
    /// Sets TERM and LANG for proper terminal compatibility.
    static func terminalEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        if env["LANG"] == nil {
            env["LANG"] = "en_US.UTF-8"
        }
        return env
    }

    /// Environment as an array of "KEY=VALUE" strings for Process.
    static func terminalEnvironmentArray() -> [String] {
        terminalEnvironment().map { "\($0.key)=\($0.value)" }
    }
}
