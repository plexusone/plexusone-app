import AppKit
import Foundation
import Observation
import UserNotifications

/// Shared application state for multi-window support
@MainActor
@Observable
final class AppState {
    /// Session manager shared across all windows
    let sessionManager: SessionManager

    /// Window state manager for persistence
    let windowStateManager: WindowStateManager

    /// Input monitor for detecting AI assistant input prompts
    let inputMonitor: InputMonitor

    /// Claude Code sessions: list, tmux location, and how each ended
    let claudeSessions: ClaudeSessionCatalog

    /// Whether the app has completed initial setup
    private(set) var isInitialized = false

    /// Pending session to attach in a new pop-out window
    var pendingPopOutSession: Session?

    /// Sessions to attach in a new window, laid out in a grid that fits them
    var pendingRestoreSessions: [Session] = []

    /// Opens a main window; set by the first window, since only SwiftUI
    /// views can open windows.
    @ObservationIgnored var openMainWindow: (() -> Void)?

    /// The running app's state, for handlers SwiftUI does not reach, such
    /// as a click on a notification.
    @ObservationIgnored static weak var shared: AppState?

    /// UserDefaults key: notify when a Claude session starts waiting (default on).
    static let notifyWaitingKey = "notifyClaudeWaiting"

    @ObservationIgnored private var nextWaitingIndex = 0

    /// Create AppState with injectable dependencies
    /// - Parameters:
    ///   - sessionManager: Session manager instance (defaults to new instance)
    ///   - windowStateManager: Window state manager instance (defaults to new instance)
    ///   - inputMonitor: Input monitor instance (defaults to new instance)
    init(
        sessionManager: SessionManager = SessionManager(),
        windowStateManager: WindowStateManager = WindowStateManager(),
        inputMonitor: InputMonitor = InputMonitor(),
        claudeSessions: ClaudeSessionCatalog = ClaudeSessionCatalog()
    ) {
        self.sessionManager = sessionManager
        self.windowStateManager = windowStateManager
        self.inputMonitor = inputMonitor
        self.claudeSessions = claudeSessions
        Self.shared = self
        claudeSessions.onWaitingChanged = { [weak self] all, newlyWaiting in
            self?.waitingChanged(all: all, newlyWaiting: newlyWaiting)
        }
    }

    // MARK: - Showing sessions

    /// Focus the pane showing tmux session `name`; if no pane shows it, open
    /// a window attached to it.
    func showSession(tmuxName name: String) async {
        if SessionNavigator.focusPane(showingTmuxSession: name) { return }
        if !sessionManager.sessions.contains(where: { $0.tmuxSession == name }) {
            await sessionManager.refresh()
        }
        guard let session = sessionManager.sessions.first(where: { $0.tmuxSession == name }) else { return }
        pendingRestoreSessions = [session]
        openMainWindow?()
    }

    /// Show the next Claude session waiting for the user, cycling through them.
    func showNextWaitingSession() async {
        let names = claudeSessions.waitingSessions.compactMap { $0.tmuxTarget?.sessionName }
        guard !names.isEmpty else {
            NSSound.beep()
            return
        }
        let name = names[nextWaitingIndex % names.count]
        nextWaitingIndex += 1
        await showSession(tmuxName: name)
    }

    // MARK: - Waiting alerts

    private func waitingChanged(all: [ClaudeLiveRecord], newlyWaiting: [ClaudeLiveRecord]) {
        if let app = NSApp {
            app.dockTile.badgeLabel = all.isEmpty ? nil : "\(all.count)"
        }
        let notify = UserDefaults.standard.object(forKey: Self.notifyWaitingKey) as? Bool ?? true
        guard notify, NSApp != nil, Bundle.main.bundleIdentifier != nil else { return }
        for record in newlyWaiting {
            postWaitingNotification(record)
        }
    }

    private func postWaitingNotification(_ record: ClaudeLiveRecord) {
        let content = UNMutableNotificationContent()
        content.title = "Claude needs you"
        content.body = Self.waitingNotificationBody(record)
        content.sound = .default
        if let tmux = record.tmuxTarget?.sessionName {
            content.userInfo = ["tmuxSession": tmux]
        }
        // One notification per session: a newer one replaces the older.
        let request = UNNotificationRequest(identifier: "claude-waiting-\(record.sessionId)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("PlexusOne: waiting notification failed: %@", error.localizedDescription)
            }
        }
    }

    /// "github-com-8b in tmux acad is waiting: permission prompt"
    nonisolated static func waitingNotificationBody(_ record: ClaudeLiveRecord) -> String {
        let who = record.name ?? String(record.sessionId.prefix(8))
        let whereText = record.tmuxTarget.map { " in tmux \($0.sessionName)" } ?? ""
        let what = ClaudeLiveStatus.text(status: record.status, waitingFor: record.waitingFor) ?? "waiting"
        return "\(who)\(whereText) is \(what)"
    }

    /// Start monitoring sessions (call once at app launch)
    func startMonitoring() async {
        guard !isInitialized else { return }

        // Check tmux availability
        if !sessionManager.checkTmuxAvailable() {
            print("Warning: tmux is not installed")
        }

        // Initial refresh
        await sessionManager.refresh()

        // Start periodic monitoring
        sessionManager.startMonitoring()
        claudeSessions.startMonitoring()

        isInitialized = true
    }
}
