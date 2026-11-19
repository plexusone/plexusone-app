import Foundation

/// Restores a long-lived Claude Code session's mission after a compaction.
///
/// Claude Code runs `PlexusOneDesktop context-hook` from a SessionStart hook,
/// typically with the matcher `compact` (and optionally `resume`), and adds
/// whatever the hook prints to the session's context. The hook prints a short
/// block with three parts:
///
/// - the session's role: its mission, the repositories it may change, its
///   autonomy level, its peers, and notes;
/// - its open roadmap items, from the `visionstudio` CLI when it is on PATH;
/// - the accepted decisions that bind the role.
///
/// A session declares its role with the `HIVE_ROLE` environment variable.
/// Roles are JSON files named after the role in a roles directory, and
/// decisions are JSON files in a decisions directory; both directories come
/// from `--roles` and `--decisions` or the environment variables
/// `PLEXUSONE_ROLES_DIR` and `PLEXUSONE_DECISIONS_DIR`. Without a role, or
/// without its file, the hook prints nothing. It always exits 0 and reports
/// problems only to the system log, so it can never block or fail a session
/// start.
enum ContextHook {
    /// Command-line argument that runs the hook instead of the app.
    static let command = "context-hook"

    static let roleEnv = "HIVE_ROLE"
    static let rolesEnv = "PLEXUSONE_ROLES_DIR"
    static let decisionsEnv = "PLEXUSONE_DECISIONS_DIR"

    /// Output limits, so the block stays a few dozen lines.
    static let maxLines = 40
    static let maxRoadmapItems = 8
    static let maxDecisions = 6
    static let maxFieldLength = 240

    // MARK: - File formats

    /// A role a session plays, independent of the session.
    struct Role: Codable, Equatable, Sendable {
        var name: String?
        /// draft, active, or retired.
        var status: String?
        var mission: String?
        /// observe, prepare, or execute.
        var autonomy: String?
        /// Repositories the role may change.
        var repositories: [RepositoryScope]?
        /// Initiatives whose roadmap items the role works on.
        var initiatives: [String]?
        /// Other roles it works with.
        var peers: [String]?
        var notes: String?
    }

    /// Repositories a role covers.
    struct RepositoryScope: Codable, Equatable, Sendable {
        /// `github.com/<org>/<repo>`, or `github.com/<org>/*` for every
        /// repository in an organization.
        var pattern: String
        /// steward or contributor.
        var affinity: String?
    }

    /// A recorded decision.
    struct Decision: Codable, Equatable, Sendable {
        var id: String?
        var title: String?
        /// accepted or superseded.
        var status: String?
        var decision: String?
        var reasons: [String]?
        var alternatives: [String]?
        var refs: [String]?
        /// Roles the decision binds; empty binds every role.
        var roles: [String]?
        var repositories: [String]?
        var supersedes: [String]?
        var supersededBy: String?
    }

    /// An open roadmap item, as `visionstudio rmi list --format json` reports it.
    struct RoadmapItem: Codable, Equatable, Sendable {
        var id: String
        var title: String?
        var status: String?
        var initiativeId: String?

        enum CodingKeys: String, CodingKey {
            case id, title, status
            case initiativeId = "initiative_id"
        }
    }

    // MARK: - Entry point

    /// Entry point for `PlexusOneDesktop context-hook`.
    static func run() {
        let output = render(
            arguments: Array(CommandLine.arguments.dropFirst(2)),
            environment: ProcessInfo.processInfo.environment,
            roadmap: visionstudioRoadmap
        )
        if !output.isEmpty {
            FileHandle.standardOutput.write(Data(output.utf8))
        }
    }

    /// The block to print, or "" when the session has no role or its file
    /// cannot be read. Problems go to the system log, never to the output.
    static func render(
        arguments: [String],
        environment: [String: String],
        roadmap: ([String]) -> [RoadmapItem]
    ) -> String {
        let config = configuration(arguments: arguments, environment: environment)
        guard let roleName = config.role, let rolesDir = config.roles else { return "" }
        guard isValidRoleName(roleName) else {
            NSLog("PlexusOne context-hook: ignoring invalid role name %@", roleName)
            return ""
        }

        let roleURL = URL(fileURLWithPath: rolesDir, isDirectory: true).appendingPathComponent("\(roleName).json")
        guard FileManager.default.fileExists(atPath: roleURL.path) else { return "" }
        var role: Role
        do {
            role = try JSONDecoder().decode(Role.self, from: Data(contentsOf: roleURL))
        } catch {
            NSLog("PlexusOne context-hook: cannot read role %@: %@", roleURL.path, error.localizedDescription)
            return ""
        }
        if role.name?.isEmpty ?? true {
            role.name = roleName
        }

        var decisions: [Decision] = []
        if let dir = config.decisions {
            decisions = loadDecisions(in: URL(fileURLWithPath: dir, isDirectory: true))
        }
        let items = roadmap(role.initiatives ?? [])
        return format(role: role, roadmap: items, decisions: binding(decisions, for: roleName))
    }

    // MARK: - Configuration

    /// The session's role (from `HIVE_ROLE`) and the roles and decisions
    /// directories. `--roles` and `--decisions` take precedence over the
    /// environment; a leading `~/` is expanded.
    static func configuration(arguments: [String], environment: [String: String])
        -> (role: String?, roles: String?, decisions: String?) {
        var roles = environment[rolesEnv]
        var decisions = environment[decisionsEnv]
        var i = 0
        while i < arguments.count {
            let arg = arguments[i]
            let next = i + 1 < arguments.count ? arguments[i + 1] : nil
            switch arg {
            case "--roles", "--roles-dir":
                roles = next
                i += 1
            case "--decisions", "--decisions-dir":
                decisions = next
                i += 1
            default:
                if arg.hasPrefix("--roles=") {
                    roles = String(arg.dropFirst("--roles=".count))
                } else if arg.hasPrefix("--decisions=") {
                    decisions = String(arg.dropFirst("--decisions=".count))
                }
            }
            i += 1
        }
        let role = environment[roleEnv]?.trimmingCharacters(in: .whitespaces)
        return (role?.isEmpty == false ? role : nil,
                expand(roles, home: environment["HOME"]),
                expand(decisions, home: environment["HOME"]))
    }

    /// Whether a role name is a plain file name: ASCII letters, digits, `.`,
    /// `_` and `-`, not starting with `.`. This keeps `HIVE_ROLE` from naming
    /// a file outside the roles directory.
    static func isValidRoleName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 100, !name.hasPrefix(".") else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "._-".unicodeScalars.contains(scalar))
        }
    }

    private static func expand(_ path: String?, home: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("~/") {
            let base = home ?? FileManager.default.homeDirectoryForCurrentUser.path
            return base + path.dropFirst(1)
        }
        return path
    }

    // MARK: - Decisions

    /// Decisions in `dir`, newest file first. Unreadable files are skipped.
    static func loadDecisions(in dir: URL) -> [Decision] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else {
            NSLog("PlexusOne context-hook: cannot list decisions in %@", dir.path)
            return []
        }
        var dated: [(Decision, Date)] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let decision = try? JSONDecoder().decode(Decision.self, from: data) else {
                NSLog("PlexusOne context-hook: skipping unreadable decision %@", url.lastPathComponent)
                continue
            }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            dated.append((decision, modified))
        }
        return dated
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : ($0.0.id ?? "") > ($1.0.id ?? "") }
            .map(\.0)
    }

    /// Accepted decisions that bind the role: those whose `roles` is empty or
    /// includes it.
    static func binding(_ decisions: [Decision], for role: String?) -> [Decision] {
        decisions.filter { d in
            guard d.status?.lowercased() == "accepted" else { return false }
            let roles = d.roles ?? []
            return roles.isEmpty || (role.map { roles.contains($0) } ?? false)
        }
    }

    // MARK: - Roadmap

    /// Statuses that mean a roadmap item is no longer open.
    static let closedStatuses: Set<String> = ["completed", "done", "cancelled", "canceled", "rejected", "superseded", "dropped"]

    /// Open items for the initiatives, in progress first. Returns nothing
    /// when `visionstudio` is not on PATH, fails, or takes too long.
    static func visionstudioRoadmap(initiatives: [String]) -> [RoadmapItem] {
        var items: [RoadmapItem] = []
        for initiative in initiatives.prefix(3) {
            guard let data = runWithTimeout(
                "/usr/bin/env", ["visionstudio", "rmi", "list", "--initiative", initiative, "--format", "json"],
                timeout: 3
            ) else { continue }
            if let decoded = try? JSONDecoder().decode([RoadmapItem].self, from: data) {
                items += decoded
            }
        }
        return openItems(items)
    }

    /// Open items, in progress first, then ready, then the rest, each group
    /// in ID order.
    static func openItems(_ items: [RoadmapItem]) -> [RoadmapItem] {
        func rank(_ status: String?) -> Int {
            switch status {
            case "in_progress": return 0
            case "ready": return 1
            default: return 2
            }
        }
        return items
            .filter { !closedStatuses.contains($0.status ?? "") }
            .sorted { rank($0.status) != rank($1.status) ? rank($0.status) < rank($1.status) : $0.id < $1.id }
    }

    /// Runs a command and returns its stdout, or nil when it fails or does not
    /// finish within `timeout` seconds.
    static func runWithTimeout(_ path: String, _ arguments: [String], timeout: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }

        var data = Data()
        let read = DispatchGroup()
        read.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            data = stdout.fileHandleForReading.readDataToEndOfFile()
            read.leave()
        }
        if read.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = read.wait(timeout: .now() + 1)
            NSLog("PlexusOne context-hook: %@ timed out", arguments.first ?? path)
            return nil
        }
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    // MARK: - Output

    /// The context block. Long fields are shortened and the whole block is
    /// capped at `maxLines`.
    static func format(role: Role, roadmap: [RoadmapItem], decisions: [Decision]) -> String {
        var lines: [String] = []
        let name = role.name.map { " \($0)" } ?? ""
        lines.append("## Session role\(name)")
        lines.append("This session's standing context, restored after the conversation was compacted.")
        if let mission = nonEmpty(role.mission) {
            lines.append("Mission: \(shorten(mission))")
        }
        var facts: [String] = []
        if let autonomy = nonEmpty(role.autonomy) { facts.append("autonomy: \(autonomy)") }
        if let status = nonEmpty(role.status) { facts.append("status: \(status)") }
        if !facts.isEmpty {
            lines.append("Role: " + facts.joined(separator: ", "))
        }
        if let repos = role.repositories, !repos.isEmpty {
            let list = repos.map { r in r.affinity.map { "\(r.pattern) (\($0))" } ?? r.pattern }
            lines.append("Repositories it may change: \(shorten(list.joined(separator: ", ")))")
        }
        if let initiatives = role.initiatives, !initiatives.isEmpty {
            lines.append("Initiatives: \(shorten(initiatives.joined(separator: ", ")))")
        }
        if let peers = role.peers, !peers.isEmpty {
            lines.append("Peers: \(shorten(peers.joined(separator: ", ")))")
        }
        if let notes = nonEmpty(role.notes) {
            lines.append("Notes: \(shorten(notes))")
        }

        if !roadmap.isEmpty {
            lines.append("")
            lines.append("## Open roadmap items")
            for item in roadmap.prefix(maxRoadmapItems) {
                let status = item.status.map { " [\($0)]" } ?? ""
                lines.append("- \(item.id)\(status) \(shorten(item.title ?? ""))")
            }
            if roadmap.count > maxRoadmapItems {
                lines.append("- … \(roadmap.count - maxRoadmapItems) more")
            }
        }

        if !decisions.isEmpty {
            lines.append("")
            lines.append("## Decisions that bind this role")
            for d in decisions.prefix(maxDecisions) {
                let id = d.id.map { "\($0): " } ?? ""
                lines.append("- \(id)\(shorten(d.title ?? d.decision ?? ""))")
                if let text = nonEmpty(d.decision), d.title != nil {
                    lines.append("  \(shorten(text))")
                }
            }
            if decisions.count > maxDecisions {
                lines.append("- … \(decisions.count - maxDecisions) more")
            }
        }

        if lines.count > maxLines {
            lines = Array(lines.prefix(maxLines - 1)) + ["(truncated)"]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }

    /// One line, at most `maxFieldLength` characters.
    static func shorten(_ s: String) -> String {
        let oneLine = s.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard oneLine.count > maxFieldLength else { return oneLine }
        return String(oneLine.prefix(maxFieldLength - 1)) + "…"
    }
}
