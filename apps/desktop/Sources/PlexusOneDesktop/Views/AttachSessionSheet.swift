import SwiftUI

/// Sheet for picking a tmux session to attach, opened from the app menu.
struct AttachSessionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let sessions: [Session]
    let onSelect: (Session) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Attach to Session")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if sessions.isEmpty {
                Text("No sessions available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                List(sessions) { session in
                    Button {
                        onSelect(session)
                        dismiss()
                    } label: {
                        HStack {
                            StatusIndicatorView(status: session.status)
                            Text(session.name)
                            Spacer()
                            Text(session.lastActivity.timeAgoString())
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 160, maxHeight: 320)
            }
        }
        .frame(width: 360)
    }
}

#Preview {
    AttachSessionSheet(
        sessions: [
            Session(name: "coder-1", status: .running),
            Session(name: "reviewer", status: .idle)
        ],
        onSelect: { _ in }
    )
}
