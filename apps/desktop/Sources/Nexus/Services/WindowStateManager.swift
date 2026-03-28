import Foundation
import Observation

/// Manages multi-window state persistence
@Observable
final class WindowStateManager {
    private let stateDirectory: URL
    private let stateFileURL: URL

    /// All registered windows
    private(set) var windowConfigs: [UUID: WindowConfig] = [:]

    /// Whether state was loaded from disk (for restore prompts)
    private(set) var hasRestoredState: Bool = false

    /// Loaded window configs (before restoration)
    private(set) var pendingRestoreConfigs: [WindowConfig] = []

    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        self.stateDirectory = homeDir.appendingPathComponent(".plexusone")
        self.stateFileURL = stateDirectory.appendingPathComponent("nexus_state.json")

        loadState()
    }

    // MARK: - Window Registration

    /// Register a new window and return its UUID
    func registerWindow(config: WindowConfig? = nil) -> WindowConfig {
        let windowConfig = config ?? WindowConfig()
        windowConfigs[windowConfig.id] = windowConfig
        saveState()
        return windowConfig
    }

    /// Update a window's configuration
    func updateWindow(id: UUID, gridConfig: GridConfig, paneManager: PaneManager) {
        guard var config = windowConfigs[id] else { return }
        config.update(gridConfig: gridConfig, paneManager: paneManager)
        windowConfigs[id] = config
        saveState()
    }

    /// Update window frame
    func updateWindowFrame(id: UUID, frame: WindowFrame) {
        guard var config = windowConfigs[id] else { return }
        config.frame = frame
        windowConfigs[id] = config
        saveState()
    }

    /// Unregister a window when it closes
    func unregisterWindow(id: UUID) {
        windowConfigs.removeValue(forKey: id)
        saveState()
    }

    /// Get config for a specific window
    func config(for id: UUID) -> WindowConfig? {
        windowConfigs[id]
    }

    /// Get configs to restore on app launch
    func configsToRestore() -> [WindowConfig] {
        pendingRestoreConfigs
    }

    /// Clear pending restore configs after restoration
    func clearPendingRestore() {
        pendingRestoreConfigs = []
    }

    /// Pop the next pending config for a new window
    func popNextPendingConfig() -> WindowConfig? {
        guard !pendingRestoreConfigs.isEmpty else { return nil }
        return pendingRestoreConfigs.removeFirst()
    }

    /// Check if there are pending configs to restore
    var hasPendingConfigs: Bool {
        !pendingRestoreConfigs.isEmpty
    }

    // MARK: - Persistence

    private func loadState() {
        guard FileManager.default.fileExists(atPath: stateFileURL.path) else {
            hasRestoredState = false
            return
        }

        do {
            let data = try Data(contentsOf: stateFileURL)

            // Try to decode as v2 (multi-window) format first
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            if let multiState = try? decoder.decode(MultiWindowState.self, from: data), multiState.version >= 2 {
                pendingRestoreConfigs = multiState.windows
                hasRestoredState = !multiState.windows.isEmpty
                return
            }

            // Fall back to v1 (single-window NexusState) format and migrate
            if let singleState = try? decoder.decode(NexusState.self, from: data) {
                let migratedConfig = WindowConfig(
                    gridConfig: singleState.gridConfig,
                    paneAttachments: singleState.paneAttachments
                )
                pendingRestoreConfigs = [migratedConfig]
                hasRestoredState = true
                print("Migrated v1 state to v2 multi-window format")
                return
            }

            hasRestoredState = false
        } catch {
            print("Failed to load window state: \(error)")
            hasRestoredState = false
        }
    }

    private func saveState() {
        let state = MultiWindowState(windows: Array(windowConfigs.values))

        do {
            // Ensure directory exists
            try FileManager.default.createDirectory(
                at: stateDirectory,
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let data = try encoder.encode(state)
            try data.write(to: stateFileURL, options: .atomic)
        } catch {
            print("Failed to save window state: \(error)")
        }
    }

    /// Clear all saved state
    func clearState() {
        do {
            if FileManager.default.fileExists(atPath: stateFileURL.path) {
                try FileManager.default.removeItem(at: stateFileURL)
            }
            windowConfigs = [:]
            pendingRestoreConfigs = []
            hasRestoredState = false
        } catch {
            print("Failed to clear state: \(error)")
        }
    }
}
