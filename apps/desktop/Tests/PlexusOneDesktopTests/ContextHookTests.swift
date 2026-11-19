import XCTest
@testable import PlexusOneDesktop

final class ContextHookTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ContextHookTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("decisions"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    private var charterURL: URL { dir.appendingPathComponent("charter.json") }
    private var decisionsURL: URL { dir.appendingPathComponent("decisions") }

    private func write(_ json: String, to url: URL, modified: Date? = nil) throws {
        try Data(json.utf8).write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
    }

    private let charterJSON = """
    {"name": "app-agent", "status": "active", "mission": "Maintain the desktop app.",
     "repositories": ["github.com/example/app"], "initiatives": ["INIT-EXAMPLE-001"],
     "peers": ["docs-agent"], "autonomy": "execute", "notes": "Ask before releases."}
    """

    private func noRoadmap(_: [String]) -> [ContextHook.RoadmapItem] { [] }

    // MARK: - Configuration

    func testNoCharterPrintsNothing() {
        XCTAssertEqual(ContextHook.render(arguments: [], environment: [:], roadmap: noRoadmap), "")
    }

    func testUnreadableCharterPrintsNothing() throws {
        try write("not json", to: charterURL)
        XCTAssertEqual(ContextHook.render(arguments: ["--charter", charterURL.path], environment: [:], roadmap: noRoadmap), "")
        XCTAssertEqual(ContextHook.render(arguments: ["--charter", dir.appendingPathComponent("missing.json").path],
                                          environment: [:], roadmap: noRoadmap), "")
    }

    func testConfiguredPathsPreferArgumentsOverEnvironment() {
        let env = [ContextHook.charterEnv: "/env/charter.json", ContextHook.decisionsEnv: "/env/decisions", "HOME": "/home/me"]

        var paths = ContextHook.configuredPaths(arguments: [], environment: env)
        XCTAssertEqual(paths.charter, "/env/charter.json")
        XCTAssertEqual(paths.decisions, "/env/decisions")

        paths = ContextHook.configuredPaths(arguments: ["--charter", "~/c.json", "--decisions=/d"], environment: env)
        XCTAssertEqual(paths.charter, "/home/me/c.json")
        XCTAssertEqual(paths.decisions, "/d")

        paths = ContextHook.configuredPaths(arguments: ["--charter=/a.json", "--decisions-dir", "/x"], environment: [:])
        XCTAssertEqual(paths.charter, "/a.json")
        XCTAssertEqual(paths.decisions, "/x")

        paths = ContextHook.configuredPaths(arguments: ["--charter"], environment: [ContextHook.charterEnv: ""])
        XCTAssertNil(paths.charter, "a flag without a value and an empty variable mean no charter")
    }

    // MARK: - Decisions

    func testDecisionsNewestFirstAndOnlyBindingOnes() throws {
        let now = Date()
        try write(#"{"id":"D-1","title":"Old for all","status":"accepted","decision":"a","agents":[]}"#,
                  to: decisionsURL.appendingPathComponent("1.json"), modified: now.addingTimeInterval(-300))
        try write(#"{"id":"D-2","title":"New for me","status":"accepted","decision":"b","agents":["app-agent"]}"#,
                  to: decisionsURL.appendingPathComponent("2.json"), modified: now)
        try write(#"{"id":"D-3","title":"Superseded","status":"superseded","agents":[]}"#,
                  to: decisionsURL.appendingPathComponent("3.json"))
        try write(#"{"id":"D-4","title":"For someone else","status":"accepted","agents":["docs-agent"]}"#,
                  to: decisionsURL.appendingPathComponent("4.json"))
        try write(#"{"id":"D-5","title":"No agents field","status":"Accepted"}"#,
                  to: decisionsURL.appendingPathComponent("5.json"), modified: now.addingTimeInterval(-600))
        try write("not json", to: decisionsURL.appendingPathComponent("bad.json"))
        try write("{}", to: decisionsURL.appendingPathComponent("notes.txt"))

        let loaded = ContextHook.loadDecisions(in: decisionsURL)
        XCTAssertEqual(loaded.count, 5, "unreadable and non-JSON files are skipped")

        let binding = ContextHook.binding(loaded, for: "app-agent")
        XCTAssertEqual(binding.map(\.id), ["D-2", "D-1", "D-5"])
        XCTAssertEqual(ContextHook.binding(loaded, for: nil).map(\.id), ["D-1", "D-5"],
                       "without a name only decisions for everyone apply")
    }

    func testMissingDecisionsDirectory() {
        XCTAssertEqual(ContextHook.loadDecisions(in: dir.appendingPathComponent("nope")), [])
    }

    // MARK: - Roadmap

    func testOpenItemsOrdering() {
        let items: [ContextHook.RoadmapItem] = [
            .init(id: "RMI-3", title: "c", status: "proposed", initiativeId: "I"),
            .init(id: "RMI-2", title: "b", status: "ready", initiativeId: "I"),
            .init(id: "RMI-1", title: "a", status: "completed", initiativeId: "I"),
            .init(id: "RMI-4", title: "d", status: "in_progress", initiativeId: "I"),
            .init(id: "RMI-0", title: "e", status: "ready", initiativeId: "I"),
        ]
        XCTAssertEqual(ContextHook.openItems(items).map(\.id), ["RMI-4", "RMI-0", "RMI-2", "RMI-3"])
    }

    func testRoadmapItemDecodesVisionstudioJSON() throws {
        let json = #"[{"id":"RMI-X-001","initiative_id":"INIT-X-001","title":"Do it","status":"ready","required":true}]"#
        let items = try JSONDecoder().decode([ContextHook.RoadmapItem].self, from: Data(json.utf8))
        XCTAssertEqual(items, [.init(id: "RMI-X-001", title: "Do it", status: "ready", initiativeId: "INIT-X-001")])
    }

    func testRunWithTimeout() {
        XCTAssertEqual(ContextHook.runWithTimeout("/bin/echo", ["hi"], timeout: 5).map { String(decoding: $0, as: UTF8.self) }, "hi\n")
        XCTAssertNil(ContextHook.runWithTimeout("/usr/bin/false", [], timeout: 5), "a failing command gives nil")
        XCTAssertNil(ContextHook.runWithTimeout("/no/such/tool", [], timeout: 5), "a missing command gives nil")
        let start = Date()
        XCTAssertNil(ContextHook.runWithTimeout("/bin/sleep", ["10"], timeout: 0.3), "a slow command gives nil")
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testMissingVisionstudioIsSkipped() {
        // /usr/bin/env exits 127 when the tool is not on PATH.
        XCTAssertNil(ContextHook.runWithTimeout("/usr/bin/env", ["plexusone-no-such-tool"], timeout: 5))
    }

    // MARK: - Output

    func testRenderFullBlock() throws {
        try write(charterJSON, to: charterURL)
        try write(#"{"id":"D-1","title":"Hooks run from the app","status":"accepted","decision":"No separate binary.","agents":[]}"#,
                  to: decisionsURL.appendingPathComponent("1.json"))

        var askedFor: [String] = []
        let output = ContextHook.render(
            arguments: [],
            environment: [ContextHook.charterEnv: charterURL.path, ContextHook.decisionsEnv: decisionsURL.path],
            roadmap: { initiatives in
                askedFor = initiatives
                return [.init(id: "RMI-EXAMPLE-004", title: "Context hook", status: "in_progress", initiativeId: "INIT-EXAMPLE-001")]
            }
        )

        XCTAssertEqual(askedFor, ["INIT-EXAMPLE-001"], "the roadmap is filtered to the charter's initiatives")
        for expected in [
            "## Session charter app-agent",
            "Mission: Maintain the desktop app.",
            "Charter: autonomy: execute, status: active",
            "Repositories it may change: github.com/example/app",
            "Peers: docs-agent",
            "Notes: Ask before releases.",
            "## Open roadmap items",
            "- RMI-EXAMPLE-004 [in_progress] Context hook",
            "## Decisions that bind this session",
            "- D-1: Hooks run from the app",
            "  No separate binary.",
        ] {
            XCTAssertTrue(output.contains(expected), "missing \(expected) in:\n\(output)")
        }
    }

    func testRenderOmitsEmptySections() throws {
        try write(#"{"name": "solo"}"#, to: charterURL)
        let output = ContextHook.render(arguments: ["--charter", charterURL.path], environment: [:], roadmap: noRoadmap)
        XCTAssertTrue(output.hasPrefix("## Session charter solo\n"))
        XCTAssertFalse(output.contains("## Open roadmap items"))
        XCTAssertFalse(output.contains("## Decisions"))
        XCTAssertFalse(output.contains("Mission:"))
    }

    func testFormatLimits() {
        let charter = ContextHook.Charter(name: "busy", mission: String(repeating: "m", count: 1000))
        let items = (0..<20).map { ContextHook.RoadmapItem(id: "RMI-\($0)", title: "t", status: "ready", initiativeId: nil) }
        let decisions = (0..<20).map { ContextHook.Decision(id: "D-\($0)", title: "t", status: "accepted", decision: "d") }
        let output = ContextHook.format(charter: charter, roadmap: items, decisions: decisions)
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).dropLast()

        XCTAssertLessThanOrEqual(lines.count, ContextHook.maxLines)
        XCTAssertTrue(output.contains("- … 12 more"))
        XCTAssertTrue(output.contains("- … 14 more"))
        let mission = lines.first { $0.hasPrefix("Mission:") }!
        XCTAssertLessThanOrEqual(mission.count, "Mission: ".count + ContextHook.maxFieldLength)
    }

    func testFormatCapsTotalLines() {
        let charter = ContextHook.Charter(name: "x", status: "s", mission: "m", repositories: ["r"], initiatives: ["i"],
                                          peers: ["p"], autonomy: "a", notes: "n")
        let decisions = (0..<6).map { ContextHook.Decision(id: "D-\($0)", title: "t", status: "accepted", decision: "d") }
        let items = (0..<8).map { ContextHook.RoadmapItem(id: "RMI-\($0)", title: "t", status: "ready", initiativeId: nil) }
        var output = ContextHook.format(charter: charter, roadmap: items, decisions: decisions)
        XCTAssertLessThanOrEqual(output.split(separator: "\n").count, ContextHook.maxLines)

        // Even with every section full, the block never exceeds the cap.
        output = ContextHook.format(charter: charter, roadmap: items + items, decisions: decisions + decisions)
        XCTAssertLessThanOrEqual(output.split(separator: "\n").count, ContextHook.maxLines)
    }

    func testShorten() {
        XCTAssertEqual(ContextHook.shorten("  a\nb  "), "a b")
        let long = ContextHook.shorten(String(repeating: "x", count: 500))
        XCTAssertEqual(long.count, ContextHook.maxFieldLength)
        XCTAssertTrue(long.hasSuffix("…"))
    }
}
