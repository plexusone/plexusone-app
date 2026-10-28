import SwiftUI

/// Settings/Preferences window
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            SessionSettingsView()
                .tabItem {
                    Label("Sessions", systemImage: "terminal")
                }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("autoAttachOnLaunch") private var autoAttachOnLaunch = true
    @AppStorage("showDetachedSessions") private var showDetachedSessions = true
    @AppStorage("restoreWindowsOnLaunch") private var restoreWindowsOnLaunch = true

    var body: some View {
        Form {
            Toggle("Auto-attach to last session on launch", isOn: $autoAttachOnLaunch)
            Toggle("Show detached sessions in status bar", isOn: $showDetachedSessions)
            Toggle("Restore windows on launch", isOn: $restoreWindowsOnLaunch)
        }
        .padding()
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("terminalFontSize") private var fontSize: Double = 13
    @AppStorage("cursorBlink") private var cursorBlink = true

    var body: some View {
        Form {
            HStack {
                Text("Font Size:")
                Slider(value: $fontSize, in: 9...24, step: 1) {
                    Text("Font Size")
                }
                Text("\(Int(fontSize))pt")
                    .monospacedDigit()
                    .frame(width: 40)
            }

            Toggle("Cursor blink", isOn: $cursorBlink)

            // Placeholder for theme selection
            Text("Theme settings coming in a future update")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding()
    }
}

struct SessionSettingsView: View {
    @AppStorage("idleThresholdSeconds") private var idleThreshold: Double = 30
    @AppStorage("stuckThresholdSeconds") private var stuckThreshold: Double = 120
    @AppStorage("defaultShell") private var defaultShell = "/bin/zsh"
    @AppStorage(TmuxEnvironment.mouseScrollingKey) private var mouseScrolling = true

    var body: some View {
        Form {
            HStack {
                Text("Idle after:")
                Slider(value: $idleThreshold, in: 10...120, step: 10)
                Text("\(Int(idleThreshold))s")
                    .monospacedDigit()
                    .frame(width: 40)
            }

            HStack {
                Text("Stuck after:")
                Slider(value: $stuckThreshold, in: 60...600, step: 30)
                Text("\(Int(stuckThreshold))s")
                    .monospacedDigit()
                    .frame(width: 40)
            }

            TextField("Default Shell:", text: $defaultShell)
                .textFieldStyle(.roundedBorder)

            Toggle("Trackpad scrolls conversation history", isOn: $mouseScrolling)
            Text("Turns on tmux mouse mode for sessions shown here. Hold Shift to drag-select text. When off, the session uses your own tmux setting. Applies the next time a session is attached.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

#Preview {
    SettingsView()
}
