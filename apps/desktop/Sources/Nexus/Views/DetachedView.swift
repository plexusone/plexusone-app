import SwiftUI

/// Placeholder view shown when no session is attached to the pane
struct DetachedView: View {
    let sessions: [NexusSession]
    let onSelectSession: (NexusSession) -> Void
    let onCreateNew: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            // Title
            Text("No Session Attached")
                .font(.title2)
                .fontWeight(.medium)

            // Description
            Text("Attach to an existing session or create a new one")
                .foregroundColor(.secondary)

            // Action buttons
            VStack(spacing: 12) {
                // Create new session button
                Button(action: onCreateNew) {
                    Label("New Session", systemImage: "plus")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("n", modifiers: .command)

                // Existing sessions
                if !sessions.isEmpty {
                    Text("or attach to existing:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)

                    VStack(spacing: 4) {
                        ForEach(sessions.prefix(5)) { session in
                            Button(action: { onSelectSession(session) }) {
                                HStack {
                                    StatusIndicatorView(status: session.status)
                                    Text(session.name)
                                    Spacer()
                                    Text(session.lastActivity.timeAgoString())
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(minWidth: 200)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                        }

                        if sessions.count > 5 {
                            Text("+ \(sessions.count - 5) more sessions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Keyboard shortcut hint
            Text("Press ⌘A to open session picker")
                .font(.caption)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview("With Sessions") {
    DetachedView(
        sessions: [
            NexusSession(name: "coder-1", status: .running),
            NexusSession(name: "reviewer", status: .idle),
            NexusSession(name: "planner", status: .stuck)
        ],
        onSelectSession: { _ in },
        onCreateNew: { }
    )
    .frame(width: 600, height: 400)
}

#Preview("No Sessions") {
    DetachedView(
        sessions: [],
        onSelectSession: { _ in },
        onCreateNew: { }
    )
    .frame(width: 600, height: 400)
}
