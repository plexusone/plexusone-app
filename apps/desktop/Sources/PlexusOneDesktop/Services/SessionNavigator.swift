import AppKit

/// Finds and focuses terminal panes across all windows.
@MainActor
enum SessionNavigator {
    /// Focus the pane showing tmux session `name` in any window, bringing
    /// its window forward. Returns false when no pane shows it.
    @discardableResult
    static func focusPane(showingTmuxSession name: String) -> Bool {
        let sessionId = UUID.forTmuxSession(named: name)
        for window in NSApp.windows where window.isVisible {
            guard let contentView = window.contentView else { continue }
            if let terminal = terminalViews(in: contentView).first(where: { $0.attachedSessionId() == sessionId }) {
                NSApp.activate()
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(terminal)
                return true
            }
        }
        return false
    }

    /// Every terminal view under `view`.
    static func terminalViews(in view: NSView) -> [AppTerminalView] {
        if let terminal = view as? AppTerminalView {
            return [terminal]
        }
        return view.subviews.flatMap { terminalViews(in: $0) }
    }
}
