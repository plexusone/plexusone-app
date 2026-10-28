import SwiftUI

/// Per-window actions for the app menu. Each window publishes its own with
/// `focusedSceneValue`, so a menu command acts on the key window only.
struct WindowActions {
    let newSession: () -> Void
    let attachSession: () -> Void
    let detachFocusedPane: () -> Void
    let focusNextPane: () -> Void
    let focusPreviousPane: () -> Void
}

private struct WindowActionsKey: FocusedValueKey {
    typealias Value = WindowActions
}

extension FocusedValues {
    var windowActions: WindowActions? {
        get { self[WindowActionsKey.self] }
        set { self[WindowActionsKey.self] = newValue }
    }
}

/// File, Edit, and Window menu commands.
struct AppCommands: Commands {
    @FocusedValue(\.windowActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Session") { actions?.newSession() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions == nil)

            NewWindowButton()

            Divider()

            // ⌘A stays Select All; attach uses ⌥⌘A.
            Button("Attach to Session...") { actions?.attachSession() }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .disabled(actions == nil)

            Button("Detach") { actions?.detachFocusedPane() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(actions == nil)
        }

        // Edit menu - ensure copy/paste work with terminal
        CommandGroup(after: .pasteboard) {
            Divider()

            Button("Select All") {
                // Forward to first responder (terminal view handles this)
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("a", modifiers: .command)
        }

        CommandGroup(after: .windowList) {
            Divider()

            Button("Next Pane") { actions?.focusNextPane() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(actions == nil)

            Button("Previous Pane") { actions?.focusPreviousPane() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(actions == nil)
        }

        // Remove default "New Window" since we have our own
        CommandGroup(replacing: .singleWindowList) { }
    }
}

/// Opens a window directly, so it works even when no window is open.
private struct NewWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Window") { openWindow(id: "main") }
            .keyboardShortcut("n", modifiers: [.command, .shift])
    }
}

