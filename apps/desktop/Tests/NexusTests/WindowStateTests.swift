import XCTest
@testable import Nexus

final class WindowStateTests: XCTestCase {

    // MARK: - WindowFrame Tests

    func testWindowFrameEncoding() throws {
        let frame = WindowFrame(x: 100, y: 200, width: 800, height: 600)

        let encoder = JSONEncoder()
        let data = try encoder.encode(frame)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"x\":100"))
        XCTAssertTrue(json.contains("\"y\":200"))
        XCTAssertTrue(json.contains("\"width\":800"))
        XCTAssertTrue(json.contains("\"height\":600"))
    }

    func testWindowFrameDecoding() throws {
        let json = """
        {"x": 50, "y": 75, "width": 1024, "height": 768}
        """

        let decoder = JSONDecoder()
        let frame = try decoder.decode(WindowFrame.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(frame.x, 50)
        XCTAssertEqual(frame.y, 75)
        XCTAssertEqual(frame.width, 1024)
        XCTAssertEqual(frame.height, 768)
    }

    func testWindowFrameEquatable() {
        let frame1 = WindowFrame(x: 100, y: 100, width: 800, height: 600)
        let frame2 = WindowFrame(x: 100, y: 100, width: 800, height: 600)
        let frame3 = WindowFrame(x: 200, y: 100, width: 800, height: 600)

        XCTAssertEqual(frame1, frame2)
        XCTAssertNotEqual(frame1, frame3)
    }

    // MARK: - WindowConfig Tests

    func testWindowConfigDefaultInitialization() {
        let config = WindowConfig()

        XCTAssertNotNil(config.id)
        XCTAssertEqual(config.gridColumns, 2)
        XCTAssertEqual(config.gridRows, 1)
        XCTAssertTrue(config.paneAttachments.isEmpty)
        XCTAssertNil(config.frame)
    }

    func testWindowConfigCustomInitialization() {
        let id = UUID()
        let gridConfig = GridConfig(columns: 3, rows: 2)
        let attachments = ["1": "session-a", "2": "session-b"]
        let frame = WindowFrame(x: 0, y: 0, width: 1200, height: 800)

        let config = WindowConfig(
            id: id,
            gridConfig: gridConfig,
            paneAttachments: attachments,
            frame: frame
        )

        XCTAssertEqual(config.id, id)
        XCTAssertEqual(config.gridColumns, 3)
        XCTAssertEqual(config.gridRows, 2)
        XCTAssertEqual(config.paneAttachments["1"], "session-a")
        XCTAssertEqual(config.paneAttachments["2"], "session-b")
        XCTAssertEqual(config.frame, frame)
    }

    func testWindowConfigGridConfigProperty() {
        let config = WindowConfig(gridConfig: GridConfig(columns: 4, rows: 3))

        let gridConfig = config.gridConfig

        XCTAssertEqual(gridConfig.columns, 4)
        XCTAssertEqual(gridConfig.rows, 3)
        XCTAssertEqual(gridConfig.paneCount, 12)
    }

    func testWindowConfigEncoding() throws {
        let id = UUID()
        let config = WindowConfig(
            id: id,
            gridConfig: GridConfig(columns: 2, rows: 2),
            paneAttachments: ["1": "test-session"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains(id.uuidString))
        XCTAssertTrue(json.contains("\"gridColumns\":2"))
        XCTAssertTrue(json.contains("\"gridRows\":2"))
        XCTAssertTrue(json.contains("\"1\""))
        XCTAssertTrue(json.contains("\"test-session\""))
    }

    func testWindowConfigDecoding() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "gridColumns": 3,
            "gridRows": 1,
            "paneAttachments": {"1": "claude", "2": "reviewer"}
        }
        """

        let decoder = JSONDecoder()
        let config = try decoder.decode(WindowConfig.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(config.id.uuidString, "550E8400-E29B-41D4-A716-446655440000")
        XCTAssertEqual(config.gridColumns, 3)
        XCTAssertEqual(config.gridRows, 1)
        XCTAssertEqual(config.paneAttachments["1"], "claude")
        XCTAssertEqual(config.paneAttachments["2"], "reviewer")
    }

    // MARK: - MultiWindowState Tests

    func testMultiWindowStateInitialization() {
        let state = MultiWindowState()

        XCTAssertTrue(state.windows.isEmpty)
        XCTAssertEqual(state.version, 2)
        XCTAssertNotNil(state.savedAt)
    }

    func testMultiWindowStateWithWindows() {
        let config1 = WindowConfig(gridConfig: GridConfig(columns: 2, rows: 1))
        let config2 = WindowConfig(gridConfig: GridConfig(columns: 3, rows: 2))

        let state = MultiWindowState(windows: [config1, config2])

        XCTAssertEqual(state.windows.count, 2)
        XCTAssertEqual(state.version, 2)
    }

    func testMultiWindowStateEncoding() throws {
        let config = WindowConfig(gridConfig: GridConfig(columns: 2, rows: 1))
        let state = MultiWindowState(windows: [config])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"version\":2"))
        XCTAssertTrue(json.contains("\"windows\""))
        XCTAssertTrue(json.contains("\"savedAt\""))
    }

    func testMultiWindowStateDecoding() throws {
        let json = """
        {
            "windows": [
                {
                    "id": "550e8400-e29b-41d4-a716-446655440000",
                    "gridColumns": 2,
                    "gridRows": 2,
                    "paneAttachments": {}
                }
            ],
            "savedAt": "2024-03-28T12:00:00Z",
            "version": 2
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(MultiWindowState.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(state.windows.count, 1)
        XCTAssertEqual(state.version, 2)
        XCTAssertEqual(state.windows[0].gridColumns, 2)
        XCTAssertEqual(state.windows[0].gridRows, 2)
    }

    // MARK: - NexusState (v1) Migration Tests

    func testNexusStateLegacyDecoding() throws {
        let json = """
        {
            "gridColumns": 3,
            "gridRows": 2,
            "paneAttachments": {"1": "old-session"},
            "savedAt": "2024-03-01T10:00:00Z",
            "version": 1
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacyState = try decoder.decode(NexusState.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(legacyState.gridColumns, 3)
        XCTAssertEqual(legacyState.gridRows, 2)
        XCTAssertEqual(legacyState.paneAttachments["1"], "old-session")
        XCTAssertEqual(legacyState.version, 1)

        // Test migration to WindowConfig
        let migratedConfig = WindowConfig(
            gridConfig: legacyState.gridConfig,
            paneAttachments: legacyState.paneAttachments
        )

        XCTAssertEqual(migratedConfig.gridColumns, 3)
        XCTAssertEqual(migratedConfig.gridRows, 2)
        XCTAssertEqual(migratedConfig.paneAttachments["1"], "old-session")
    }
}
