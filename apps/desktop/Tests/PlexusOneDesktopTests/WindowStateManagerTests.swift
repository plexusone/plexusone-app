import XCTest
@testable import PlexusOneDesktop

final class WindowStateManagerTests: XCTestCase {

    var tempDirectory: URL!
    var stateFileURL: URL!

    override func setUp() {
        super.setUp()
        // Create a temporary directory for each test
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        stateFileURL = tempDirectory.appendingPathComponent("state.json")
    }

    override func tearDown() {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - Helper

    private func writeStateFile(_ content: String) {
        try? content.data(using: .utf8)?.write(to: stateFileURL)
    }

    // MARK: - Registration Tests

    func testRegisterWindowReturnsConfig() {
        let manager = WindowStateManager()

        let config = manager.registerWindow()

        XCTAssertNotNil(config.id)
        XCTAssertEqual(config.gridColumns, 2)
        XCTAssertEqual(config.gridRows, 1)
    }

    func testRegisterWindowWithCustomConfig() {
        let manager = WindowStateManager()
        let customConfig = WindowConfig(gridConfig: GridConfig(columns: 3, rows: 2))

        let config = manager.registerWindow(config: customConfig)

        XCTAssertEqual(config.id, customConfig.id)
        XCTAssertEqual(config.gridColumns, 3)
        XCTAssertEqual(config.gridRows, 2)
    }

    func testRegisterMultipleWindows() {
        let manager = WindowStateManager()

        let config1 = manager.registerWindow()
        let config2 = manager.registerWindow()

        XCTAssertNotEqual(config1.id, config2.id)
        XCTAssertEqual(manager.windowConfigs.count, 2)
    }

    func testUnregisterWindow() {
        let manager = WindowStateManager()
        let config = manager.registerWindow()

        XCTAssertEqual(manager.windowConfigs.count, 1)

        manager.unregisterWindow(id: config.id)

        XCTAssertEqual(manager.windowConfigs.count, 0)
    }

    func testUnregisterNonexistentWindow() {
        let manager = WindowStateManager()
        let config = manager.registerWindow()

        manager.unregisterWindow(id: UUID()) // Different UUID

        XCTAssertEqual(manager.windowConfigs.count, 1)
        XCTAssertNotNil(manager.config(for: config.id))
    }

    // MARK: - Config Retrieval Tests

    func testConfigForId() {
        let manager = WindowStateManager()
        let registered = manager.registerWindow(
            config: WindowConfig(gridConfig: GridConfig(columns: 4, rows: 2))
        )

        let retrieved = manager.config(for: registered.id)

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.gridColumns, 4)
        XCTAssertEqual(retrieved?.gridRows, 2)
    }

    func testConfigForNonexistentId() {
        let manager = WindowStateManager()
        _ = manager.registerWindow()

        let config = manager.config(for: UUID())

        XCTAssertNil(config)
    }

    // MARK: - Pending Configs Tests

    func testPopNextPendingConfigReturnsNilAfterClearing() {
        let manager = WindowStateManager()

        // Clear any pending configs from disk state
        manager.clearPendingRestore()

        let config = manager.popNextPendingConfig()

        XCTAssertNil(config)
    }

    func testHasPendingConfigsAfterClearing() {
        let manager = WindowStateManager()

        // Clear any pending configs from disk state
        manager.clearPendingRestore()

        XCTAssertFalse(manager.hasPendingConfigs)
    }

    func testClearPendingRestore() {
        let manager = WindowStateManager()

        manager.clearPendingRestore()

        XCTAssertFalse(manager.hasPendingConfigs)
        XCTAssertTrue(manager.configsToRestore().isEmpty)
    }

    // MARK: - Clear State Tests

    func testClearState() {
        let manager = WindowStateManager()
        _ = manager.registerWindow()
        _ = manager.registerWindow()

        XCTAssertEqual(manager.windowConfigs.count, 2)

        manager.clearState()

        XCTAssertEqual(manager.windowConfigs.count, 0)
        XCTAssertFalse(manager.hasRestoredState)
    }
}
