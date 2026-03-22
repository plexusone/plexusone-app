import SwiftUI

/// A single pane with a compact session dropdown header and terminal view
struct PaneView: View {
    let paneId: Int
    let sessions: [NexusSession]
    let sessionManager: SessionManager
    @Binding var attachedSession: NexusSession?
    let onRequestNewSession: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            // Compact header with session dropdown
            PaneHeaderView(
                paneId: paneId,
                sessions: sessions,
                currentSession: attachedSession,
                onSelectSession: { session in
                    attachedSession = session
                },
                onDetach: {
                    attachedSession = nil
                },
                onNewSession: onRequestNewSession
            )

            // Terminal or detached placeholder
            if attachedSession != nil {
                TerminalViewRepresentable(
                    attachedSession: $attachedSession,
                    sessionManager: sessionManager,
                    onSessionEnded: {
                        attachedSession = nil
                    }
                )
            } else {
                // Compact detached state
                CompactDetachedView(
                    sessions: sessions,
                    onSelectSession: { session in
                        attachedSession = session
                    },
                    onNewSession: onRequestNewSession
                )
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

/// Compact header bar for each pane
struct PaneHeaderView: View {
    let paneId: Int
    let sessions: [NexusSession]
    let currentSession: NexusSession?
    let onSelectSession: (NexusSession) -> Void
    let onDetach: () -> Void
    let onNewSession: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            // Session dropdown
            Menu {
                if sessions.isEmpty {
                    Text("No sessions")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(sessions) { session in
                        Button(action: { onSelectSession(session) }) {
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

                Button(action: onNewSession) {
                    Label("New Session...", systemImage: "plus")
                }
            } label: {
                HStack(spacing: 4) {
                    if let session = currentSession {
                        StatusIndicatorView(status: session.status)
                        Text(session.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    } else {
                        Image(systemName: "terminal")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("Select...")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            // Pane number indicator
            Text("#\(paneId)")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .padding(.horizontal, 4)

            // Detach button (only show if attached)
            if currentSession != nil {
                Button(action: onDetach) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Detach")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(nsColor: .separatorColor)),
            alignment: .bottom
        )
    }
}

/// Compact placeholder when pane has no session attached
struct CompactDetachedView: View {
    let sessions: [NexusSession]
    let onSelectSession: (NexusSession) -> Void
    let onNewSession: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 24))
                .foregroundColor(.secondary)

            Text("No Session")
                .font(.caption)
                .foregroundColor(.secondary)

            if !sessions.isEmpty {
                // Scrollable session list
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(sessions) { session in
                            Button(action: { onSelectSession(session) }) {
                                HStack {
                                    StatusIndicatorView(status: session.status)
                                    Text(session.name)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(session.lastActivity.timeAgoString())
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(4)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxWidth: 200, maxHeight: 150)
            }

            Button(action: onNewSession) {
                Label("New", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
    }
}

#Preview {
    PaneView(
        paneId: 1,
        sessions: [
            NexusSession(name: "coder-1", status: .running),
            NexusSession(name: "reviewer", status: .idle)
        ],
        sessionManager: SessionManager(),
        attachedSession: .constant(nil),
        onRequestNewSession: {}
    )
    .frame(width: 400, height: 300)
}
