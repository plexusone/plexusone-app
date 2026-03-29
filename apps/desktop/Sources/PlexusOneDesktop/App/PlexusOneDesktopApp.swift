import SwiftUI

@main
struct PlexusOneDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    private let appState = AppState()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(appState)
                .frame(minWidth: 600, minHeight: 400)
                .onReceive(NotificationCenter.default.publisher(for: .newWindow)) { _ in
                    openWindow(id: "main")
                }
                .onReceive(NotificationCenter.default.publisher(for: .popOutSession)) { notification in
                    if let session = notification.userInfo?["session"] as? Session {
                        appState.pendingPopOutSession = session
                        openWindow(id: "main")
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session") {
                    NotificationCenter.default.post(name: .newSession, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Window") {
                    NotificationCenter.default.post(name: .newWindow, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Attach to Session...") {
                    NotificationCenter.default.post(name: .attachSession, object: nil)
                }
                .keyboardShortcut("a", modifiers: .command)

                Button("Detach") {
                    NotificationCenter.default.post(name: .detachSession, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }

            CommandGroup(after: .windowList) {
                Divider()

                Button("Next Pane") {
                    NotificationCenter.default.post(name: .nextPane, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)

                Button("Previous Pane") {
                    NotificationCenter.default.post(name: .previousPane, object: nil)
                }
                .keyboardShortcut("[", modifiers: .command)
            }

            // Remove default "New Window" since we have our own
            CommandGroup(replacing: .singleWindowList) { }
        }

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newSession = Notification.Name("com.plexusone.desktop.newSession")
    static let newWindow = Notification.Name("com.plexusone.desktop.newWindow")
    static let popOutSession = Notification.Name("com.plexusone.desktop.popOutSession")
    static let attachSession = Notification.Name("com.plexusone.desktop.attachSession")
    static let detachSession = Notification.Name("com.plexusone.desktop.detachSession")
    static let nextPane = Notification.Name("com.plexusone.desktop.nextPane")
    static let previousPane = Notification.Name("com.plexusone.desktop.previousPane")
    static let restoreComplete = Notification.Name("com.plexusone.desktop.restoreComplete")
}
