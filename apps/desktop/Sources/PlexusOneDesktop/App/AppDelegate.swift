import AppKit
import SwiftUI
import UserNotifications

/// AppDelegate for handling application-level events
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Two copies would both write ~/.plexusone state and fight over it.
        if let other = Self.otherRunningInstance() {
            other.activate()
            NSApp.terminate(nil)
        }
    }

    /// Another running copy of this app (same bundle identifier), if any.
    /// A bare executable has no bundle identifier and is never matched.
    static func otherRunningInstance() -> NSRunningApplication? {
        guard let bundleId = Bundle.main.bundleIdentifier else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .first { $0.processIdentifier != me && !$0.isTerminated }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the app runs as a regular foreground app (shows in Dock and Cmd+Tab)
        // This is needed when running the executable directly instead of from an app bundle
        NSApp.setActivationPolicy(.regular)

        // Activate the app to ensure window appears
        NSApp.activate(ignoringOtherApps: true)

        // Configure app appearance
        configureAppearance()

        // Check for tmux installation
        checkTmuxInstallation()

        // Route clicks on notifications back to the app. The notification
        // center needs an app bundle.
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup if needed
        // Note: tmux sessions will continue running
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running even if all windows closed
        // User might want to reattach to sessions
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Notifications

    /// A click on a "Claude needs you" notification shows that session.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let tmuxSession = response.notification.request.content.userInfo["tmuxSession"] as? String
        Task { @MainActor in
            if let tmuxSession {
                await AppState.shared?.showSession(tmuxName: tmuxSession)
            }
            completionHandler()
        }
    }

    /// Show notifications even while the app is in front.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Private Methods

    private func configureAppearance() {
        // Use default macOS appearance
        // Could be customized for terminal-specific styling
    }

    private func checkTmuxInstallation() {
        // Use TmuxEnvironment to check known installation paths directly,
        // rather than relying on PATH which may not include Homebrew directories
        if !TmuxEnvironment.isInstalled() {
            Task { @MainActor in
                showTmuxNotInstalledAlert()
            }
        }
    }

    @MainActor
    private func showTmuxNotInstalledAlert() {
        let alert = NSAlert()
        alert.messageText = "tmux Not Found"
        alert.informativeText = """
            PlexusOne Desktop requires tmux to manage terminal sessions.

            Install tmux using Homebrew:
            brew install tmux

            Or visit: https://github.com/tmux/tmux
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Homebrew")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            if let url = URL(string: "https://brew.sh") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
