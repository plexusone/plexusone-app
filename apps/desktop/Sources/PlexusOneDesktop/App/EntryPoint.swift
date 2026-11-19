import SwiftUI

/// Starts the app, or runs a Claude Code hook when invoked as
/// `PlexusOneDesktop claude-hook` (see `ClaudeHookRecorder`) or
/// `PlexusOneDesktop context-hook` (see `ContextHook`).
@main
enum EntryPoint {
    @MainActor
    static func main() {
        switch CommandLine.arguments.dropFirst().first {
        case ClaudeHookRecorder.command:
            ClaudeHookRecorder.run()
            exit(0)
        case ContextHook.command:
            ContextHook.run()
            exit(0)
        default:
            break
        }
        PlexusOneDesktopApp.main()
    }
}
