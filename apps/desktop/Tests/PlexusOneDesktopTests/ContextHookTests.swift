import XCTest
@testable import PlexusOneDesktop

final class ContextHookTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ContextHookTests-\(UUID().uuidString)")
        for sub in ["roles", "decisions"] {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    private var rolesURL: URL { dir.appendingPathComponent("roles") }
    private var decisionsURL: URL { dir.appendingPathComponent("decisions") }

    private func write(_ json: String, to url: URL, modified: Date? = nil) throws {
        try Data(json.utf8).write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
    }

    private let roleJSON = """
    {"name": "app-agent", "status": "active", "mission": "Maintain the desktop app.",
     "autonomy": "execute",
     "repositories": [{"pattern": "github.com/example/app", "affinity": "steward"},
                      {"pattern": "github.com/example/*", "affinity": "contributor"}],
     "initiatives": ["INIT-EXAMPLE-001"], "peers": ["docs-agent"], "notes": "Ask before releases."}
    """

    private func environment(role: String?) -> [String: String] {
        var env = [ContextHook.rolesEnv: rolesURL.path, ContextHook.decisionsEnv: decisionsURL.path]
        env[ContextHook.roleEnv] = role
        return env
    }

    private func noRoadmap(_: [String]) -> [ContextHook.RoadmapItem] { [] }

    // MARK: - Finding the role

    func testNoRolePrintsNothing() throws {
        try write(roleJSON, to: rolesURL.appendingPathComponent("app-agent.json"))
        XCTAssertEqual(ContextHook.render(arguments: [], environment: environment(role: nil), roadmap: noRoadmap), "")
        XCTAssertEqual(ContextHook.render(arguments: [], environment: environment(role: "  "), roadmap: noRoadmap), "")
    }

    func testNoRolesDirectoryPrintsNothing() {
        XCTAssertEqual(ContextHook.render(arguments: [], environment: [ContextHook.roleEnv: "app-agent"], roadmap: noRoadmap), "")
    }

    func testMissingOrUnreadableRoleFilePrintsNothing() throws {
        XCTAssertEqual(ContextHook.render(arguments: [], environment: environment(role: "nobody"), roadmap: noRoadmap), "")
        try write("not json", to: rolesURL.appendingPathComponent("broken.json"))
        XCTAssertEqual(ContextHook.render(arguments: [], environment: environment(role: "broken"), roadmap: noRoadmap), "")
    }

    func testRoleNameCannotLeaveTheRolesDirectory() throws {
        // A role file outside the roles directory must not be reachable.
        try write(roleJSON, to: dir.appendingPathComponent("outside.json"))
        XCTAssertEqual(ContextHook.render(arguments: [], environment: environment(role: "../outside"), roadmap: noRoadmap), "")

        for bad in ["../x", "a/b", ".hidden", "", "rôle", String(repeating: "a", count: 101)] {
            XCTAssertFalse(ContextHook.isValidRoleName(bad), bad)
        }
        for good in ["plexusone-app", "docs_agent", "v1.2", "A9"] {
            XCTAssertTrue(ContextHook.isValidRoleName(good), good)
        }
    }

    func testConfigurationPrefersArgumentsOverEnvironment() {
        let env = [ContextHook.roleEnv: "app-agent", ContextHook.rolesEnv: "/env/roles",
                   ContextHook.decisionsEnv: "/env/decisions", "HOME": "/home/me"]

        var config = ContextHook.configuration(arguments: [], environment: env)
        XCTAssertEqual(config.role, "app-agent")
        XCTAssertEqual(config.roles, "/env/roles")
        XCTAssertEqual(config.decisions, "/env/decisions")

        config = ContextHook.configuration(arguments: ["--roles", "~/roles", "--decisions=/d"], environment: env)
        XCTAssertEqual(config.roles, "/home/me/roles")
        XCTAssertEqual(config.decisions, "/d")

        config = ContextHook.configuration(arguments: ["--roles=/r", "--decisions-dir", "/x"], environment: [:])
        XCTAssertNil(config.role)
        XCTAssertEqual(config.roles, "/r")
        XCTAssertEqual(config.decisions, "/x")

        config = ContextHook.configuration(arguments: ["--roles"], environment: [ContextHook.rolesEnv: ""])
        XCTAssertNil(config.roles, "a flag without a value and an empty variable mean no roles directory")
    }

    // MARK: - Decisions

    func testDecisionsNewestFirstAndOnlyBindingOnes() throws {
        let now = Date()
        try write(#"{"id":"D-1","title":"Old for all","status":"accepted","decision":"a","roles":[]}"#,
                  to: decisionsURL.appendingPathComponent("1.json"), modified: now.addingTimeInterval(-300))
        try write(#"{"id":"D-2","title":"New for me","status":"accepted","decision":"b","roles":["app-agent"]}"#,
                  to: decisionsURL.appendingPathComponent("2.json"), modified: now)
        try write(#"{"id":"D-3","title":"Superseded","status":"superseded","roles":[],"supersededBy":"D-2"}"#,
                  to: decisionsURL.appendingPathComponent("3.json"))
        try write(#"{"id":"D-4","title":"For another role","status":"accepted","roles":["docs-agent"]}"#,
                  to: decisionsURL.appendingPathComponent("4.json"))
        try write(#"{"id":"D-5","title":"No roles field","status":"Accepted"}"#,
                  to: decisionsURL.appendingPathComponent("5.json"), modified: now.addingTimeInterval(-600))
        try write("not json", to: decisionsURL.appendingPathComponent("bad.json"))
        try write("{}", to: decisionsURL.appendingPathComponent("notes.txt"))

        let loaded = ContextHook.loadDecisions(in: decisionsURL)
        XCTAssertEqual(loaded.count, 5, "unreadable and non-JSON files are skipped")

        XCTAssertEqual(ContextHook.binding(loaded, for: "app-agent").map(\.id), ["D-2", "D-1", "D-5"])
        XCTAssertEqual(ContextHook.binding(loaded, for: nil).map(\.id), ["D-1", "D-5"],
                       "without a role only decisions for every role apply")
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
        try write(roleJSON, to: rolesURL.appendingPathComponent("app-agent.json"))
        try write(#"{"id":"D-1","title":"Hooks run from the app","status":"accepted","decision":"No separate binary.","roles":[]}"#,
                  to: decisionsURL.appendingPathComponent("1.json"))

        var askedFor: [String] = []
        let output = ContextHook.render(
            arguments: [],
            environment: environment(role: "app-agent"),
            roadmap: { initiatives in
                askedFor = initiatives
                return [.init(id: "RMI-EXAMPLE-004", title: "Context hook", status: "in_progress", initiativeId: "INIT-EXAMPLE-001")]
            }
        )

        XCTAssertEqual(askedFor, ["INIT-EXAMPLE-001"], "the roadmap is filtered to the role's initiatives")
        for expected in [
            "## Session role app-agent",
            "Mission: Maintain the desktop app.",
            "Role: autonomy: execute, status: active",
            "Repositories it may change: github.com/example/app (steward), github.com/example/* (contributor)",
            "Peers: docs-agent",
            "Notes: Ask before releases.",
            "## Open roadmap items",
            "- RMI-EXAMPLE-004 [in_progress] Context hook",
            "## Decisions that bind this role",
            "- D-1: Hooks run from the app",
            "  No separate binary.",
        ] {
            XCTAssertTrue(output.contains(expected), "missing \(expected) in:\n\(output)")
        }
    }

    func testRoleFileWithoutNameUsesTheRoleName() throws {
        try write(#"{"mission": "m", "repositories": [{"pattern": "github.com/example/x"}]}"#,
                  to: rolesURL.appendingPathComponent("solo.json"))
        let output = ContextHook.render(arguments: ["--roles", rolesURL.path], environment: [ContextHook.roleEnv: "solo"],
                                        roadmap: noRoadmap)
        XCTAssertTrue(output.hasPrefix("## Session role solo\n"))
        XCTAssertTrue(output.contains("Repositories it may change: github.com/example/x\n"),
                      "a scope without affinity shows only its pattern")
        XCTAssertFalse(output.contains("## Open roadmap items"))
        XCTAssertFalse(output.contains("## Decisions"))
    }

    func testFormatLimits() {
        let role = ContextHook.Role(name: "busy", mission: String(repeating: "m", count: 1000))
        let items = (0..<20).map { ContextHook.RoadmapItem(id: "RMI-\($0)", title: "t", status: "ready", initiativeId: nil) }
        let decisions = (0..<20).map { ContextHook.Decision(id: "D-\($0)", title: "t", status: "accepted", decision: "d") }
        let output = ContextHook.format(role: role, roadmap: items, decisions: decisions)
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).dropLast()

        XCTAssertLessThanOrEqual(lines.count, ContextHook.maxLines)
        XCTAssertTrue(output.contains("- … 12 more"))
        XCTAssertTrue(output.contains("- … 14 more"))
        let mission = lines.first { $0.hasPrefix("Mission:") }!
        XCTAssertLessThanOrEqual(mission.count, "Mission: ".count + ContextHook.maxFieldLength)
    }

    func testShorten() {
        XCTAssertEqual(ContextHook.shorten("  a\nb  "), "a b")
        let long = ContextHook.shorten(String(repeating: "x", count: 500))
        XCTAssertEqual(long.count, ContextHook.maxFieldLength)
        XCTAssertTrue(long.hasSuffix("…"))
    }
}
