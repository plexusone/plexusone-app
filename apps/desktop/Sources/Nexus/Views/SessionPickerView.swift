import SwiftUI

/// Dropdown picker for selecting a tmux session to attach to
struct SessionPickerView: View {
    let sessions: [NexusSession]
    let currentSession: NexusSession?
    let onSelect: (NexusSession) -> Void
    let onCreateNew: () -> Void

    var body: some View {
        Menu {
            if sessions.isEmpty {
                Text("No sessions available")
                    .foregroundColor(.secondary)
            } else {
                ForEach(sessions) { session in
                    Button(action: { onSelect(session) }) {
                        HStack {
                            StatusIndicatorView(status: session.status)
                            Text(session.name)
                            if session.id == currentSession?.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button(action: onCreateNew) {
                Label("New Session...", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        } label: {
            HStack(spacing: 6) {
                if let session = currentSession {
                    StatusIndicatorView(status: session.status)
                    Text(session.name)
                        .fontWeight(.medium)
                } else {
                    Image(systemName: "terminal")
                        .foregroundColor(.secondary)
                    Text("No Session")
                        .foregroundColor(.secondary)
                }
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
    }
}

/// Small colored dot indicating session status
struct StatusIndicatorView: View {
    let status: SessionStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch status {
        case .running:
            return .green
        case .idle:
            return .yellow
        case .stuck:
            return .red
        case .detached:
            return .gray
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SessionPickerView(
            sessions: [
                NexusSession(name: "coder-1", status: .running),
                NexusSession(name: "reviewer", status: .idle),
                NexusSession(name: "planner", status: .stuck)
            ],
            currentSession: nil,
            onSelect: { _ in },
            onCreateNew: { }
        )

        SessionPickerView(
            sessions: [
                NexusSession(name: "coder-1", status: .running),
            ],
            currentSession: NexusSession(name: "coder-1", status: .running),
            onSelect: { _ in },
            onCreateNew: { }
        )
    }
    .padding()
}
