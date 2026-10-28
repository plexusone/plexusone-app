import SwiftUI
import AssistantKit

/// A single pane with a compact session dropdown header and terminal view
struct PaneView: View {
    let paneId: Int
    let sessions: [Session]
    let sessionManager: SessionManager
    let inputMonitor: InputMonitor
    @Binding var attachedSession: Session?
    let onRequestNewSession: () -> Void

    @State private var isHovering = false
    @State private var currentInputAlert: DetectionResult?
    @State private var isFocused = false

    @Environment(\.openWindow) private var openWindow
    @Environment(AppState.self) private var appState

    /// The attached session as of the latest refresh. The binding holds a
    /// copy taken at attach time, so its status and wrapper go stale.
    private var liveSession: Session? {
        guard let attached = attachedSession else { return nil }
        return sessions.first { $0.id == attached.id } ?? attached
    }

    var body: some View {
        VStack(spacing: 0) {
            // Compact header with session dropdown
            PaneHeaderView(
                paneId: paneId,
                sessions: sessions,
                currentSession: liveSession,
                isFocused: isFocused,
                onSelectSession: { session in
                    attachedSession = session
                },
                onDetach: {
                    attachedSession = nil
                },
                onPopOut: {
                    if let session = attachedSession {
                        // The new window's ContentView picks this up on launch
                        appState.pendingPopOutSession = session
                        openWindow(id: "main")
                    }
                },
                onNewSession: onRequestNewSession
            )

            // Terminal or detached placeholder
            if attachedSession != nil {
                ZStack(alignment: .topTrailing) {
                    AppTerminalViewRepresentable(
                        paneId: paneId,
                        attachedSession: $attachedSession,
                        sessionManager: sessionManager,
                        inputMonitor: inputMonitor,
                        onSessionEnded: {
                            attachedSession = nil
                        },
                        onInputChanged: { result in
                            if result?.pattern.type != currentInputAlert?.pattern.type
                                || result?.matchedText != currentInputAlert?.matchedText {
                                currentInputAlert = result
                            }
                        }
                    )

                    // Input indicator overlay
                    if let alert = currentInputAlert {
                        InputIndicatorView(
                            result: alert,
                            onDismiss: { currentInputAlert = nil }
                        )
                        .padding(8)
                    }
                }
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
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isFocused ? Color.blue : Color(nsColor: .separatorColor),
                    lineWidth: isFocused ? 3 : 1
                )
        )
        .shadow(color: isFocused ? Color.blue.opacity(0.5) : .clear, radius: 8)
        .onReceive(NotificationCenter.default.publisher(for: .paneFocusChanged)) { notification in
            guard let userInfo = notification.userInfo,
                  let sessionId = userInfo["sessionId"] as? UUID,
                  let focused = userInfo["focused"] as? Bool else {
                return
            }

            // Update focus state if this notification is for our session
            if sessionId == attachedSession?.id {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isFocused = focused
                }
            } else if focused {
                // Another pane gained focus, so we lose it
                withAnimation(.easeInOut(duration: 0.15)) {
                    isFocused = false
                }
            }
        }
    }
}

/// Compact header bar for each pane
struct PaneHeaderView: View {
    let paneId: Int
    let sessions: [Session]
    let currentSession: Session?
    let isFocused: Bool
    let onSelectSession: (Session) -> Void
    let onDetach: () -> Void
    let onPopOut: () -> Void
    let onNewSession: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            // Focus indicator dot
            Circle()
                .fill(isFocused ? Color.blue : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)
                .padding(.leading, 2)

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

            // Pane number indicator with focus highlight
            Text("#\(paneId)")
                .font(.system(size: 10, weight: isFocused ? .bold : .medium))
                .foregroundColor(isFocused ? Color.blue : Color(nsColor: .tertiaryLabelColor))
                .padding(.horizontal, 4)

            // Pop-out and Detach buttons (only show if attached)
            if currentSession != nil {
                Button(action: onPopOut) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Pop Out to New Window")

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
        .background(isFocused ? Color.blue.opacity(0.15) : Color(nsColor: .windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 2)
                .foregroundColor(isFocused ? Color.blue : Color(nsColor: .separatorColor)),
            alignment: .bottom
        )
    }
}

/// Compact placeholder when pane has no session attached
struct CompactDetachedView: View {
    let sessions: [Session]
    let onSelectSession: (Session) -> Void
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
            Session(name: "coder-1", status: .running),
            Session(name: "reviewer", status: .idle)
        ],
        sessionManager: SessionManager(),
        inputMonitor: InputMonitor(),
        attachedSession: .constant(nil),
        onRequestNewSession: {}
    )
    .environment(AppState())
    .frame(width: 400, height: 300)
}
