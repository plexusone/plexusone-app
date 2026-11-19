import Foundation

/// Restores a long-lived Claude Code session's mission after a compaction.
///
/// Claude Code runs `PlexusOneDesktop context-hook` from a SessionStart hook,
/// typically with the matcher `compact` (and optionally `resume`), and adds
/// whatever the hook prints to the session's context. The hook prints a short
/// block with three parts:
///
/// - the session's charter: its mission, the repositories it may change, its
///   autonomy level, and notes;
/// - its open roadmap items, from the `visionstudio` CLI when it is on PATH;
/// - the accepted decisions that bind it.
///
/// Inputs are files: a charter JSON file and a directory of decision JSON
/// files, given with `--charter` and `--decisions` or the environment
/// variables `PLEXUSONE_CHARTER` and `PLEXUSONE_DECISIONS_DIR`. With no
/// charter configured the hook prints nothing. It always exits 0 and reports
/// problems only to the system log, so it can never block or fail a session
/// start.
enum ContextHook {
    /// Command-line argument that runs the hook instead of the app.
    static let command = "context-hook"

    static let charterEnv = "PLEXUSONE_CHARTER"
    static let decisionsEnv = "PLEXUSONE_DECISIONS_DIR"

    /// Output limits, so the block stays a few dozen lines.
    static let maxLines = 40
    static let maxRoadmapItems = 8
    static let maxDecisions = 6
    static let maxFieldLength = 240

    // MARK: - File formats

    /// A session's charter.
    struct Charter: Codable, Equatable, Sendable {
        var name: String?
        var status: String?
        var mission: String?
        /// Repositories the session may change.
        var repositories: [String]?
        /// Initiatives whose roadmap items the session works on.
        var initiatives: [String]?
        /// Other sessions it works with.
        var peers: [String]?
        /// observe, prepare, or execute.
        var autonomy: String?
        var notes: String?
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
        /// Sessions the decision binds; empty binds every session.
        var agents: [String]?
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

    /// The block to print, or "" when there is no charter or it cannot be
    /// read. Problems go to the system log, never to the output.
    static func render(
        arguments: [String],
        environment: [String: String],
        roadmap: ([String]) -> [RoadmapItem]
    ) -> String {
        let paths = configuredPaths(arguments: arguments, environment: environment)
        guard let charterPath = paths.charter else { return "" }

        let charter: Charter
        do {
            charter = try JSONDecoder().decode(Charter.self, from: Data(contentsOf: URL(fileURLWithPath: charterPath)))
        } catch {
            NSLog("PlexusOne context-hook: cannot read charter %@: %@", charterPath, error.localizedDescription)
            return ""
        }

        var decisions: [Decision] = []
        if let dir = paths.decisions {
            decisions = loadDecisions(in: URL(fileURLWithPath: dir, isDirectory: true))
        }
        let items = roadmap(charter.initiatives ?? [])
        return format(charter: charter, roadmap: items, decisions: binding(decisions, for: charter.name))
    }

    // MARK: - Configuration

    /// The charter file and decisions directory: `--charter` and
    /// `--decisions` (or `--decisions-dir`) take precedence over the
    /// environment. A leading `~/` is expanded.
    static func configuredPaths(arguments: [String], environment: [String: String]) -> (charter: String?, decisions: String?) {
        var charter = environment[charterEnv]
        var decisions = environment[decisionsEnv]
        var i = 0
        while i < arguments.count {
            let arg = arguments[i]
            let next = i + 1 < arguments.count ? arguments[i + 1] : nil
            switch arg {
            case "--charter":
                charter = next
                i += 1
            case "--decisions", "--decisions-dir":
                decisions = next
                i += 1
            default:
                if arg.hasPrefix("--charter=") {
                    charter = String(arg.dropFirst("--charter=".count))
                } else if arg.hasPrefix("--decisions=") {
                    decisions = String(arg.dropFirst("--decisions=".count))
                }
            }
            i += 1
        }
        return (expand(charter, home: environment["HOME"]), expand(decisions, home: environment["HOME"]))
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

    /// Accepted decisions that bind the named session: those whose `agents`
    /// is empty or includes the name.
    static func binding(_ decisions: [Decision], for name: String?) -> [Decision] {
        decisions.filter { d in
            guard d.status?.lowercased() == "accepted" else { return false }
            let agents = d.agents ?? []
            return agents.isEmpty || (name.map { agents.contains($0) } ?? false)
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
    static func format(charter: Charter, roadmap: [RoadmapItem], decisions: [Decision]) -> String {
        var lines: [String] = []
        let name = charter.name.map { " \($0)" } ?? ""
        lines.append("## Session charter\(name)")
        lines.append("This session's standing context, restored after the conversation was compacted.")
        if let mission = nonEmpty(charter.mission) {
            lines.append("Mission: \(shorten(mission))")
        }
        var facts: [String] = []
        if let autonomy = nonEmpty(charter.autonomy) { facts.append("autonomy: \(autonomy)") }
        if let status = nonEmpty(charter.status) { facts.append("status: \(status)") }
        if !facts.isEmpty {
            lines.append("Charter: " + facts.joined(separator: ", "))
        }
        if let repos = charter.repositories, !repos.isEmpty {
            lines.append("Repositories it may change: \(shorten(repos.joined(separator: ", ")))")
        }
        if let initiatives = charter.initiatives, !initiatives.isEmpty {
            lines.append("Initiatives: \(shorten(initiatives.joined(separator: ", ")))")
        }
        if let peers = charter.peers, !peers.isEmpty {
            lines.append("Peers: \(shorten(peers.joined(separator: ", ")))")
        }
        if let notes = nonEmpty(charter.notes) {
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
            lines.append("## Decisions that bind this session")
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
