import Foundation

/// Adds and removes the app's Claude Code hooks in `~/.claude/settings.json`.
///
/// Only the app's own entries are touched: a SessionStart and a
/// UserPromptSubmit hook that run `PlexusOneDesktop claude-hook`. The file is
/// backed up to `settings.json.plexusone-backup` before each write, and its
/// permissions are kept. A symlinked settings file (from a dotfiles manager)
/// is updated in place, keeping the link. The JSON is rewritten with sorted
/// keys, so its formatting can change.
enum ClaudeHookInstaller {
    enum InstallError: Error, LocalizedError, Equatable {
        /// The app is running from a temporary or removable location.
        case unstableLocation(String)
        /// The settings file kept changing while being updated.
        case concurrentModification

        var errorDescription: String? {
            switch self {
            case .unstableLocation(let path):
                return "PlexusOne Desktop is running from a temporary location (\(path)). Move it to the Applications folder and open it from there, then install the hook."
            case .concurrentModification:
                return "~/.claude/settings.json changed while it was being updated. Try again."
            }
        }
    }

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

    /// The hook command for an app executable, quoted for the shell. Single
    /// quotes keep the shell from expanding anything in the path.
    static func hookCommand(executable: String) -> String {
        let escaped = executable.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)' \(ClaudeHookRecorder.command)"
    }

    /// Whether a hook pointing at `executable` would stop working later:
    /// macOS runs quarantined apps from a temporary copy (App Translocation),
    /// and an app opened from its disk image goes away when it is ejected.
    static func isUnstableLocation(_ executable: String) -> Bool {
        executable.contains("/AppTranslocation/") || executable.hasPrefix("/Volumes/")
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
        let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
        if isUnstableLocation(executable) {
            throw InstallError.unstableLocation(executable)
        }
        try updateSettings { installing(into: $0, command: hookCommand(executable: executable)) }
    }

    static func uninstall() throws {
        try updateSettings { removing(from: $0) }
    }

    /// The settings file itself: the target when `settings.json` is a symlink.
    private static var resolvedSettingsURL: URL {
        settingsURL.resolvingSymlinksInPath()
    }

    private static func readSettings() throws -> [String: Any] {
        try readSettingsWithData().settings
    }

    private static func readSettingsWithData() throws -> (settings: [String: Any], data: Data?) {
        let url = resolvedSettingsURL
        guard FileManager.default.fileExists(atPath: url.path) else { return ([:], nil) }
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        return (object, data)
    }

    /// Read, transform, and write the settings. If Claude Code (or anything
    /// else) changes the file in between, start over so its change is kept.
    private static func updateSettings(_ transform: ([String: Any]) -> [String: Any]) throws {
        for _ in 0..<3 {
            let (settings, original) = try readSettingsWithData()
            let updated = transform(settings)
            let current = try currentData()
            guard current == original else { continue }
            try writeSettings(updated)
            return
        }
        throw InstallError.concurrentModification
    }

    private static func currentData() throws -> Data? {
        let url = resolvedSettingsURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        let fm = FileManager.default
        // Write the link's target so a symlinked file stays linked.
        let url = resolvedSettingsURL
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var permissions: Any?
        if fm.fileExists(atPath: url.path) {
            permissions = try fm.attributesOfItem(atPath: url.path)[.posixPermissions]
            let backup = settingsURL.appendingPathExtension("plexusone-backup")
            if fm.fileExists(atPath: backup.path) {
                try fm.removeItem(at: backup)
            }
            try fm.copyItem(at: url, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
        if let permissions {
            try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }
}
