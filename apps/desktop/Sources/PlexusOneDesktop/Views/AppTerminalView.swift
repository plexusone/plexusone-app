import AppKit
import SwiftTerm

/// Custom LocalProcessTerminalView subclass for SwiftUI integration
/// Handles explicit size tracking and layout updates following SwiftTerm's iOS pattern
class AppTerminalView: LocalProcessTerminalView {
    private var lastAppliedSize: CGSize = .zero
    private var currentSessionId: UUID?

    override func layout() {
        super.layout()
        updateSizeIfNeeded()
    }

    func updateSizeIfNeeded() {
        let newSize = bounds.size
        guard newSize.width > 0, newSize.height > 0 else { return }
        guard newSize != lastAppliedSize else { return }

        lastAppliedSize = newSize
        // SwiftTerm recalculates terminal dimensions on layout
        // The parent class layout() handles this
    }

    // MARK: - Scrolling

    /// Scroll the terminal view to show the latest output (bottom of buffer)
    /// Call this when the user sends input to ensure they see the response
    func scrollToBottom() {
        // Only scroll if we're not already at the bottom
        // scrollPosition 1.0 = bottom, 0.0 = top
        if scrollPosition < 1.0 {
            scroll(toPosition: 1.0)
        }
    }


    // MARK: - Session Management

    var isSessionAttached: Bool {
        currentSessionId != nil
    }

    func attachedSessionId() -> UUID? {
        currentSessionId
    }

    func attach(to session: Session) {
        // Terminate any existing process before attaching to a new session
        // This prevents the old tmux attach from continuing to run
        if isSessionAttached {
            terminate()
        }

        currentSessionId = session.id

        let (tmuxPath, baseArgs) = TmuxEnvironment.findExecutable()
        let args = baseArgs + ["attach", "-t", session.tmuxSession]
        let envArray = TmuxEnvironment.terminalEnvironmentArray()

        startProcess(
            executable: tmuxPath,
            args: args,
            environment: envArray,
            execName: "tmux"
        )
    }

    func detach() {
        // Terminate the tmux attach process
        // The tmux session itself continues running in background
        terminate()
        currentSessionId = nil
    }
}
