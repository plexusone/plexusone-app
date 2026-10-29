import SwiftUI

@main
struct PlexusOneDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let appState = AppState()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(appState)
                .frame(minWidth: 600, minHeight: 400)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            AppCommands(appState: appState)
        }

        Window("Claude Sessions", id: ClaudeSessionsView.windowId) {
            ClaudeSessionsView()
                .environment(appState)
                .frame(minWidth: 820, minHeight: 480)
        }

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
