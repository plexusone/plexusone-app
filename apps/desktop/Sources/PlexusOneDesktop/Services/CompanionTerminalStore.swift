import AppKit
import Foundation
import Observation
import SwiftTerm

/// Identifies a companion shell: the pane it sits in and the tmux session
/// above it. A pane that switches sessions gets a different shell, and gets
/// the old one back when it switches back.
struct CompanionKey: Hashable {
    let paneId: Int
    let tmuxSession: String
}

/// The plain shells (no tmux) shown below coding sessions, one per pane and
/// session, for one window.
///
/// Shells start in the coding session's working directory. Hiding one keeps
/// it running; it ends when the user exits it, when its tmux session goes
/// away, or when the window closes.
@MainActor
@Observable
final class CompanionTerminalStore {
    /// UserDefaults key: the shell's default height, as a percent of the pane.
    nonisolated static let defaultHeightPercentKey = "paneTerminalHeightPercent"
    /// The shell's default height when the user has not chosen one.
    nonisolated static let standardHeightPercent: Double = 35
    /// Heights the shell can take, as a share of the pane, so neither
    /// terminal shrinks to nothing.
    nonisolated static let fractionRange: ClosedRange<CGFloat> = 0.15...0.85
    /// `fractionRange` as percents, for the setting.
    nonisolated static let heightPercentRange: ClosedRange<Double> = 15...85

    /// Companions currently shown.
    private(set) var visible: Set<CompanionKey> = []

    /// The shell's share of the pane height, for panes the user resized.
    /// Other panes follow the default height setting.
    private var fractions: [Int: CGFloat] = [:]

    /// Directory each shell started in, shown above it.
    private(set) var directories: [CompanionKey: String] = [:]

    @ObservationIgnored private var shells: [CompanionKey: Shell] = [:]
    @ObservationIgnored private let launch: @MainActor (AppTerminalView, String) -> Void

    private struct Shell {
        let terminal: AppTerminalView
        /// SwiftTerm holds its process delegate weakly.
        let observer: ExitObserver
    }

    /// - Parameter launch: Starts the shell process in a directory; nil
    ///   starts the user's login shell. Tests pass a stub so no process starts.
    init(launch: (@MainActor (AppTerminalView, String) -> Void)? = nil) {
        self.launch = launch ?? { Self.launchLoginShell($0, directory: $1) }
    }

    // MARK: - Queries

    func isVisible(_ key: CompanionKey) -> Bool {
        visible.contains(key)
    }

    /// Whether a shell is running for `key`, shown or not.
    func hasShell(_ key: CompanionKey) -> Bool {
        shells[key] != nil
    }

    /// The shell's view, if one is running for `key`.
    func terminal(for key: CompanionKey) -> AppTerminalView? {
        shells[key]?.terminal
    }

    /// The height the user dragged this pane's shell to, if any.
    func customFraction(forPane paneId: Int) -> CGFloat? {
        fractions[paneId]
    }

    /// The shell's share of the pane height: the user's size for this pane,
    /// else the default.
    func fraction(forPane paneId: Int, defaultPercent: Double) -> CGFloat {
        fractions[paneId] ?? Self.fraction(percent: defaultPercent)
    }

    func setFraction(_ fraction: CGFloat, forPane paneId: Int) {
        fractions[paneId] = Self.clamped(fraction)
    }

    /// Go back to the default height for this pane.
    func resetFraction(forPane paneId: Int) {
        fractions.removeValue(forKey: paneId)
    }

    /// A height percent as a share of the pane, kept within `fractionRange`.
    nonisolated static func fraction(percent: Double) -> CGFloat {
        clamped(CGFloat(percent) / 100)
    }

    private nonisolated static func clamped(_ fraction: CGFloat) -> CGFloat {
        min(max(fraction, fractionRange.lowerBound), fractionRange.upperBound)
    }

    // MARK: - Showing and hiding

    /// Show the companion for `key`. The first time, start a shell in
    /// `directory` (the home directory if it is missing or not a folder).
    /// - Parameter ownerSessionId: The coding session's ID, so the pane stays
    ///   highlighted while the shell has focus.
    func show(_ key: CompanionKey, ownerSessionId: UUID, directory: String?) {
        if shells[key] == nil {
            let start = Self.usableDirectory(directory)
            let terminal = AppTerminalView(frame: .zero)
            terminal.paneId = key.paneId
            terminal.ownerSessionId = ownerSessionId
            terminal.applyStandardAppearance()
            let observer = ExitObserver { [weak self, weak terminal] in
                // Ignore a shell this key no longer holds.
                guard let self, let terminal, self.shells[key]?.terminal === terminal else { return }
                self.close(key)
            }
            terminal.processDelegate = observer
            shells[key] = Shell(terminal: terminal, observer: observer)
            directories[key] = start
            launch(terminal, start)
        }
        shells[key]?.terminal.focusWhenShown = true
        visible.insert(key)
    }

    /// Hide the companion; its shell keeps running.
    func hide(_ key: CompanionKey) {
        visible.remove(key)
    }

    /// End the shell for `key`.
    func close(_ key: CompanionKey) {
        visible.remove(key)
        directories.removeValue(forKey: key)
        guard let shell = shells.removeValue(forKey: key) else { return }
        shell.terminal.terminateProcess()
    }

    /// End the shells of tmux sessions that no longer exist.
    func prune(keepingSessions names: Set<String>) {
        for key in shells.keys where !names.contains(key.tmuxSession) {
            close(key)
        }
    }

    /// End every shell, when the window closes.
    func closeAll() {
        for key in Array(shells.keys) {
            close(key)
        }
    }

    // MARK: - Launching

    /// `directory` if it is an existing folder, otherwise the home directory.
    nonisolated static func usableDirectory(_ directory: String?, fileManager: FileManager = .default) -> String {
        var isDirectory: ObjCBool = false
        if let directory, !directory.isEmpty,
           fileManager.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue {
            return directory
        }
        return fileManager.homeDirectoryForCurrentUser.path
    }

    /// The user's shell: `$SHELL`, then the account's shell, then zsh.
    nonisolated static func loginShellPath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        accountShell: String? = accountShell(),
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String {
        for candidate in [environment["SHELL"], accountShell] {
            if let candidate, !candidate.isEmpty, isExecutable(candidate) {
                return candidate
            }
        }
        return "/bin/zsh"
    }

    /// The login shell in the user's account record.
    nonisolated static func accountShell() -> String? {
        guard let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell else { return nil }
        return String(cString: shell)
    }

    /// Environment for a companion shell. Drops tmux's variables, which are
    /// present when the app itself was started inside tmux, since this shell
    /// is not in tmux.
    nonisolated static func shellEnvironment(base: [String: String] = TmuxEnvironment.terminalEnvironment()) -> [String] {
        var env = base
        env.removeValue(forKey: "TMUX")
        env.removeValue(forKey: "TMUX_PANE")
        return env.map { "\($0.key)=\($0.value)" }
    }

    /// Start the user's shell as a login shell, like a new Terminal window,
    /// so its PATH and startup files match the user's terminal.
    static func launchLoginShell(_ terminal: AppTerminalView, directory: String) {
        let shell = loginShellPath()
        // A leading "-" in argv[0] makes the shell a login shell.
        let argv0 = "-" + (shell as NSString).lastPathComponent
        terminal.startProcess(
            executable: shell,
            args: [],
            environment: shellEnvironment(),
            execName: argv0,
            currentDirectory: directory
        )
    }
}

/// Reports when a companion shell exits, for example after `exit`.
final class ExitObserver: NSObject, LocalProcessTerminalViewDelegate {
    private let onExit: @MainActor () -> Void

    init(onExit: @escaping @MainActor () -> Void) {
        self.onExit = onExit
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in onExit() }
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func requestOpenLink(source: LocalProcessTerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }
}
