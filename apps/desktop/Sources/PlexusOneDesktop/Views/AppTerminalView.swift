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

    /// For a pane's companion shell: the coding session it sits under. The
    /// pane's focus highlight treats both terminals as one pane.
    var ownerSessionId: UUID?

    /// Take keyboard focus the next time this view joins a window.
    var focusWhenShown = false

    /// The session this terminal counts toward for the pane focus highlight.
    var focusSessionId: UUID? {
        currentSessionId ?? ownerSessionId
    }

    /// UserDefaults key for the terminal font size, set in Settings.
    static let fontSizeKey = "terminalFontSize"
    static let defaultFontSize: Double = 13

    /// The font size chosen in Settings.
    static var fontSizeSetting: Double {
        let stored = UserDefaults.standard.double(forKey: fontSizeKey)
        return stored > 0 ? stored : defaultFontSize
    }

    /// Use `size` for the terminal font, if it is not already.
    func applyFontSize(_ size: Double) {
        guard font.pointSize != CGFloat(size) else { return }
        font = NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
    }

    /// Font, colors, and scrollback shared by every terminal in the app.
    func applyStandardAppearance() {
        font = NSFont.monospacedSystemFont(ofSize: CGFloat(Self.fontSizeSetting), weight: .regular)
        nativeBackgroundColor = NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        nativeForegroundColor = NSColor(calibratedRed: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
        caretColor = NSColor.white
        // The default is only 500 lines; agent output can be long.
        changeScrollback(10000)
    }

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
            terminateProcess()
        }

        currentSessionId = session.id

        let (tmuxPath, baseArgs) = TmuxEnvironment.findExecutable()
        let args = baseArgs + ["attach", "-t", TmuxEnvironment.exactSessionTarget(session.tmuxSession)]
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
        terminateProcess()
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

    /// Stop the child process (a `tmux attach` client or a companion shell)
    /// and reap it.
    ///
    /// SwiftTerm's `terminate()` closes the PTY, which hangs up the child,
    /// and sends SIGTERM, but it also stops watching the child, so nothing
    /// calls waitpid() and the child would linger as a zombie process until
    /// the app quits.
    func terminateProcess() {
        // Once the child has exited its PID may belong to another process,
        // so never signal it again.
        guard process.running else { return }
        let pid = process.shellPid
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
