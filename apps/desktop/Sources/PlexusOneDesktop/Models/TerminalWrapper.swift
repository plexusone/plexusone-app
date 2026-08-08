import Foundation

/// A `figterm`-style pseudo-terminal wrapper that some shell-autocomplete tools
/// inject in front of your shell.
///
/// These tools re-exec the shell inside a PTY shim so they can watch keystrokes
/// for inline completions. The shim relays I/O between the terminal and the
/// shell — and when it deadlocks (a well-known failure mode of this design) the
/// program running inside, e.g. an agent CLI, blocks on I/O and the pane freezes
/// for *every* attached client. The shim renames its process to the shell's name
/// with a suffix, e.g. `zsh (kiro-cli-term)`, which is how it is detected.
enum TerminalWrapper: String, Codable, Hashable, CaseIterable, Sendable {
    /// Kiro CLI (`kiro-cli-term`).
    case kiroCli = "kiro-cli-term"
    /// Fig (`figterm`).
    case fig = "figterm"
    /// Amazon Q (`qterm`).
    case amazonQ = "qterm"

    /// Human-readable product name.
    var displayName: String {
        switch self {
        case .kiroCli: return "Kiro CLI"
        case .fig: return "Fig"
        case .amazonQ: return "Amazon Q"
        }
    }

    /// The marker this wrapper leaves in a shell's `ps` command,
    /// e.g. `zsh (kiro-cli-term)`.
    var processMarker: String { rawValue }

    /// Shell command that removes the wrapper's dotfiles integration, so new
    /// shells launch unwrapped.
    var remediation: String {
        switch self {
        case .kiroCli: return "kiro-cli integration uninstall dotfiles"
        case .fig: return "fig integrations uninstall dotfiles"
        case .amazonQ: return "q integrations uninstall dotfiles"
        }
    }

    /// One-line warning suitable for a tooltip or banner.
    var warning: String {
        "Shell wrapped by \(displayName)'s autocomplete PTY shim (\(processMarker)) — a known cause of frozen terminals. Fix: \(remediation)"
    }

    /// Detect a wrapper from a process command string such as
    /// `"zsh (kiro-cli-term)"`, returning the first family whose marker appears.
    static func detect(inCommand command: String) -> TerminalWrapper? {
        allCases.first { command.contains($0.processMarker) }
    }
}
