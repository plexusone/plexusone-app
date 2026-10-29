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
        .frame(width: 480, height: 420)
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
    @AppStorage(AppState.notifyWaitingKey) private var notifyWaiting = true
    @State private var hookStatus: ClaudeHookInstaller.Status?
    @State private var hookError: String?

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

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Record Claude sessions while PlexusOne is closed")
                    Spacer()
                    switch hookStatus {
                    case .installed:
                        Button("Remove Hook") { changeHook(install: false) }
                    case .outdated:
                        Button("Update Hook") { changeHook(install: true) }
                    default:
                        Button("Install Hook") { changeHook(install: true) }
                    }
                }
                Text(hookDescription)
                    .font(.caption)
                    .foregroundColor(hookError == nil ? .secondary : .red)
            }

            Toggle("Notify when a Claude session needs you", isOn: $notifyWaiting)
            Text("A notification when a session starts waiting, for example at a permission prompt. The Dock badge always counts waiting sessions; Command-J jumps to the next one.")
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle("Trackpad scrolls conversation history", isOn: $mouseScrolling)
            Text("Turns on tmux mouse mode for sessions shown here. Hold Shift to drag-select text. When off, the session uses your own tmux setting. Applies the next time a session is attached.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .onAppear(perform: loadHookStatus)
    }

    private var hookDescription: String {
        if let hookError { return hookError }
        switch hookStatus {
        case .installed:
            return "Installed in ~/.claude/settings.json. Claude Code records each session and its tmux session at start and on every prompt."
        case .outdated:
            return "Installed for a different copy of PlexusOne Desktop. Update it to use this one."
        default:
            return "Adds two hooks to ~/.claude/settings.json (backed up first) so tmux names are kept even when PlexusOne is not running. Applies to Claude sessions started afterwards."
        }
    }

    private func loadHookStatus() {
        do {
            hookStatus = try ClaudeHookInstaller.currentStatus()
            hookError = nil
        } catch {
            hookError = "Could not read ~/.claude/settings.json: \(error.localizedDescription)"
        }
    }

    private func changeHook(install: Bool) {
        do {
            if install {
                try ClaudeHookInstaller.install()
            } else {
                try ClaudeHookInstaller.uninstall()
            }
            loadHookStatus()
        } catch {
            hookError = "Could not update ~/.claude/settings.json: \(error.localizedDescription)"
        }
    }
}

#Preview {
    SettingsView()
}
