import SwiftUI

/// Starts the app, or runs the Claude Code hook recorder when invoked as
/// `PlexusOneDesktop claude-hook` (see `ClaudeHookRecorder`).
@main
enum EntryPoint {
    @MainActor
    static func main() {
        if CommandLine.arguments.dropFirst().first == ClaudeHookRecorder.command {
            ClaudeHookRecorder.run()
            exit(0)
        }
        PlexusOneDesktopApp.main()
    }
}
