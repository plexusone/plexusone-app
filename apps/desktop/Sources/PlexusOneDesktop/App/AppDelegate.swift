import AppKit
import SwiftUI

/// AppDelegate for handling application-level events
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Activate the app to ensure window appears
        NSApp.activate(ignoringOtherApps: true)

        // Configure app appearance
        configureAppearance()

        // Check for tmux installation
        checkTmuxInstallation()

        // Listen for restore completion to open additional windows
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRestoreComplete),
            name: .restoreComplete,
            object: nil
        )

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

    // MARK: - Multi-Window Restoration

    @objc private func handleRestoreComplete(_ notification: Notification) {
        guard let windowStateManager = notification.userInfo?["windowStateManager"] as? WindowStateManager else {
            return
        }
        restoreAdditionalWindows(windowStateManager: windowStateManager)
    }

    private func restoreAdditionalWindows(windowStateManager: WindowStateManager) {
        // Open additional windows for remaining pending configs
        while windowStateManager.hasPendingConfigs {
            // Post notification to open new window
            // Each new ContentView will pop the next pending config
            NotificationCenter.default.post(name: .newWindow, object: nil)

            // Small delay to allow window creation
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    // MARK: - Private Methods

    private func configureAppearance() {
        // Use default macOS appearance
        // Could be customized for terminal-specific styling
    }

    private func checkTmuxInstallation() {
        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = ["tmux"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus != 0 {
                    await showTmuxNotInstalledAlert()
                }
            } catch {
                await showTmuxNotInstalledAlert()
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
