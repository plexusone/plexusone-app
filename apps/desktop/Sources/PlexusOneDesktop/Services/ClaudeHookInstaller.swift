import Foundation

/// Adds and removes the app's Claude Code hooks in `~/.claude/settings.json`.
///
/// Only the app's own entries are touched: a SessionStart and a
/// UserPromptSubmit hook that run `PlexusOneDesktop claude-hook`. The file is
/// backed up to `settings.json.plexusone-backup` before each write, and its
/// permissions are kept. The JSON is rewritten with sorted keys, so its
/// formatting can change.
enum ClaudeHookInstaller {
    static let events = ["SessionStart", "UserPromptSubmit"]

    enum Status: Equatable {
        case notInstalled
        case installed
        /// Installed, but pointing at a different copy of the app.
        case outdated
    }

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// The hook command for an app executable, quoted for the shell.
    static func hookCommand(executable: String) -> String {
        let escaped = executable.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\" \(ClaudeHookRecorder.command)"
    }

    /// Whether a hook command is one this app installed.
    static func isOurs(_ command: String) -> Bool {
        command.contains("PlexusOneDesktop") && command.hasSuffix(" \(ClaudeHookRecorder.command)")
    }

    // MARK: - Pure transforms

    static func status(in settings: [String: Any], command: String) -> Status {
        let ours = ourCommands(in: settings)
        if ours.isEmpty { return .notInstalled }
        let complete = events.allSatisfy { event in
            commands(in: settings, event: event).contains(command)
        }
        return complete ? .installed : .outdated
    }

    /// `settings` with the app's hooks for every event, replacing any older ones.
    static func installing(into settings: [String: Any], command: String) -> [String: Any] {
        var result = removing(from: settings)
        var hooks = result["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.append(["hooks": [["type": "command", "command": command, "timeout": 5]]])
            hooks[event] = groups
        }
        result["hooks"] = hooks
        return result
    }

    /// `settings` without the app's hooks; other hooks are left as they are.
    static func removing(from settings: [String: Any]) -> [String: Any] {
        var result = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return result }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept: [[String: Any]] = groups.compactMap { group in
                guard let entries = group["hooks"] as? [[String: Any]] else { return group }
                let remaining = entries.filter { !isOurs($0["command"] as? String ?? "") }
                if remaining.isEmpty { return nil }
                var copy = group
                copy["hooks"] = remaining
                return copy
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        result["hooks"] = hooks.isEmpty ? nil : hooks
        return result
    }

    private static func commands(in settings: [String: Any], event: String) -> [String] {
        guard let hooks = settings["hooks"] as? [String: Any],
              let groups = hooks[event] as? [[String: Any]] else { return [] }
        return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    private static func ourCommands(in settings: [String: Any]) -> [String] {
        events.flatMap { commands(in: settings, event: $0) }.filter(isOurs)
    }

    // MARK: - File access

    static var currentCommand: String {
        hookCommand(executable: Bundle.main.executablePath ?? CommandLine.arguments[0])
    }

    static func currentStatus() throws -> Status {
        status(in: try readSettings(), command: currentCommand)
    }

    static func install() throws {
        try writeSettings(installing(into: try readSettings(), command: currentCommand))
    }

    static func uninstall() throws {
        try writeSettings(removing(from: try readSettings()))
    }

    private static func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: settingsURL.path])
        }
        return object
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var permissions: Any?
        if fm.fileExists(atPath: settingsURL.path) {
            permissions = try fm.attributesOfItem(atPath: settingsURL.path)[.posixPermissions]
            let backup = settingsURL.appendingPathExtension("plexusone-backup")
            if fm.fileExists(atPath: backup.path) {
                try fm.removeItem(at: backup)
            }
            try fm.copyItem(at: settingsURL, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
        if let permissions {
            try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: settingsURL.path)
        }
    }
}
