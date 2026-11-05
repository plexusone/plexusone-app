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
    @AppStorage(CompanionTerminalStore.defaultHeightPercentKey)
    private var terminalPercent = CompanionTerminalStore.standardHeightPercent

    var body: some View {
        Form {
            HStack {
                Text("Pane terminal height:")
                Slider(
                    value: $terminalPercent,
                    in: CompanionTerminalStore.heightPercentRange,
                    step: 5
                )
                Text("\(Int(terminalPercent))%")
                    .monospacedDigit()
                    .frame(width: 40)
            }
            Text("How much of the pane the terminal below a session takes. Panes follow this as they resize. Drag the bar above a terminal to size that pane yourself; double-click the bar to return to this default.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct AppearanceSettingsView: View {
    @AppStorage(AppTerminalView.fontSizeKey) private var fontSize = AppTerminalView.defaultFontSize

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
            Text("Applies to every terminal, including open ones.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct SessionSettingsView: View {
    @AppStorage(SessionManager.idleThresholdKey) private var idleThreshold = SessionManager.defaultIdleThreshold
    @AppStorage(SessionManager.stuckThresholdKey) private var stuckThreshold = SessionManager.defaultStuckThreshold
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

            Text("A session with no output for these times shows as idle, then stuck. Applies at the next refresh.")
                .font(.caption)
                .foregroundColor(.secondary)

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
