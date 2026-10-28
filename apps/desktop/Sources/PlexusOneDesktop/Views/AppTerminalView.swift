import AppKit
import SwiftTerm

/// Custom LocalProcessTerminalView subclass for SwiftUI integration
/// Handles explicit size tracking and layout updates following SwiftTerm's iOS pattern
class AppTerminalView: LocalProcessTerminalView {
    private var lastAppliedSize: CGSize = .zero
    private var currentSessionId: UUID?

    /// The grid pane this terminal belongs to, so window-level commands
    /// (next/previous pane, detach) can find the focused pane.
    var paneId: Int?

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

    /// Called for all user input headed to the PTY (typing, paste, and so on).
    /// Jump to the latest output so the user isn't left looking at scrollback.
    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        scrollToBottom()
        super.send(source: source, data: data)
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
            terminateClient()
        }

        currentSessionId = session.id

        let (tmuxPath, baseArgs) = TmuxEnvironment.findExecutable()
        let args = baseArgs + ["attach", "-t", session.tmuxSession]
        let envArray = TmuxEnvironment.terminalEnvironmentArray()
        applyMouseOption(session: session.tmuxSession)

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
        terminateClient()
        currentSessionId = nil
    }

    /// Set the session's tmux mouse mode per the user's setting. tmux applies
    /// it to the attached client as soon as it changes, so this need not
    /// finish before the client starts.
    private func applyMouseOption(session: String) {
        let (tmuxPath, baseArgs) = TmuxEnvironment.findExecutable()
        let args = baseArgs + TmuxEnvironment.mouseOptionArguments(
            session: session,
            enabled: TmuxEnvironment.mouseScrollingEnabled
        )
        Task.detached {
            do {
                let result = try await ProcessCommandExecutor().execute(tmuxPath, arguments: args)
                if !result.success {
                    NSLog("PlexusOne: tmux mouse option for %@ failed: %@", session, result.stderr)
                }
            } catch {
                NSLog("PlexusOne: tmux mouse option for %@ failed: %@", session, error.localizedDescription)
            }
        }
    }

    /// Stop the `tmux attach` client and reap it.
    ///
    /// SwiftTerm's `terminate()` sends SIGTERM but also stops watching the
    /// child, so nothing calls waitpid() and the client would linger as a
    /// zombie process until the app quits.
    private func terminateClient() {
        let pid = process.running ? process.shellPid : 0
        terminate()
        guard pid > 0 else { return }
        DispatchQueue.global(qos: .utility).async {
            var status: Int32 = 0
            // Retry if a signal interrupts the wait; any other failure means
            // the child is already gone and there is nothing to reap.
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        }
    }
}
