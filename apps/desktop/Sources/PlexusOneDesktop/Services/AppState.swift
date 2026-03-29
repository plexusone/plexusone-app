import Foundation
import Observation

/// Shared application state for multi-window support
@Observable
final class AppState {
    /// Session manager shared across all windows
    let sessionManager: SessionManager

    /// Window state manager for persistence
    let windowStateManager: WindowStateManager

    /// Whether the app has completed initial setup
    private(set) var isInitialized = false

    /// Pending session to attach in a new pop-out window
    var pendingPopOutSession: Session?

    /// Create AppState with injectable dependencies
    /// - Parameters:
    ///   - sessionManager: Session manager instance (defaults to new instance)
    ///   - windowStateManager: Window state manager instance (defaults to new instance)
    init(
        sessionManager: SessionManager = SessionManager(),
        windowStateManager: WindowStateManager = WindowStateManager()
    ) {
        self.sessionManager = sessionManager
        self.windowStateManager = windowStateManager
    }

    /// Start monitoring sessions (call once at app launch)
    func startMonitoring() async {
        guard !isInitialized else { return }

        // Check tmux availability
        let tmuxAvailable = await sessionManager.checkTmuxAvailable()
        if !tmuxAvailable {
            print("Warning: tmux is not installed")
        }

        // Initial refresh
        await sessionManager.refresh()

        // Start periodic monitoring
        sessionManager.startMonitoring()

        isInitialized = true
    }
}
