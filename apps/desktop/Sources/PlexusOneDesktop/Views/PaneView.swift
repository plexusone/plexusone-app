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
    @Environment(CompanionTerminalStore.self) private var companions
    @AppStorage(CompanionTerminalStore.defaultHeightPercentKey)
    private var defaultTerminalPercent = CompanionTerminalStore.standardHeightPercent

    /// The attached session as of the latest refresh. The binding holds a
    /// copy taken at attach time, so its status and wrapper go stale.
    private var liveSession: Session? {
        guard let attached = attachedSession else { return nil }
        return sessions.first { $0.id == attached.id } ?? attached
    }

    /// The Claude Code session running in this pane's tmux session, if any.
    private var claudeRecord: ClaudeLiveRecord? {
        guard let tmux = attachedSession?.tmuxSession else { return nil }
        return appState.claudeSessions.liveByTmuxSession[tmux]
    }

    /// This pane's companion shell for the attached session.
    private var companionKey: CompanionKey? {
        attachedSession.map { CompanionKey(paneId: paneId, tmuxSession: $0.tmuxSession) }
    }

    /// The companion shell's view, while it is shown.
    private var shownCompanion: AppTerminalView? {
        guard let key = companionKey, companions.isVisible(key) else { return nil }
        return companions.terminal(for: key)
    }

    /// The shell's share of the pane height.
    private var companionFraction: CGFloat {
        companions.fraction(forPane: paneId, defaultPercent: defaultTerminalPercent)
    }

    /// The tmux session's terminal, with the input prompt badge.
    private var codingTerminal: some View {
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
    }

    /// Show or hide the shell below the coding session. The first time,
    /// start it in the coding session's working directory.
    private func toggleCompanion() {
        guard let session = attachedSession, let key = companionKey else { return }
        if companions.isVisible(key) {
            // Hand focus back to the coding terminal if the shell had it.
            if let shell = companions.terminal(for: key), let window = shell.window,
               window.firstResponder === shell, let contentView = window.contentView,
               let coding = SessionNavigator.terminalViews(in: contentView)
                   .first(where: { $0.paneId == paneId && $0.isSessionAttached }) {
                window.makeFirstResponder(coding)
            }
            companions.hide(key)
        } else if companions.hasShell(key) {
            companions.show(key, ownerSessionId: session.id, directory: nil)
        } else {
            Task {
                let directory = await appState.workingDirectory(forTmuxSession: session.tmuxSession)
                // Skip if the pane moved on while the lookup ran.
                guard attachedSession?.tmuxSession == session.tmuxSession else { return }
                companions.show(key, ownerSessionId: session.id, directory: directory)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Compact header with session dropdown
            PaneHeaderView(
                paneId: paneId,
                sessions: sessions,
                currentSession: liveSession,
                claudeName: claudeRecord?.name,
                claudeStatus: ClaudeLiveStatus.text(status: claudeRecord?.status, waitingFor: claudeRecord?.waitingFor),
                claudeWaiting: ClaudeLiveStatus.isWaiting(status: claudeRecord?.status, waitingFor: claudeRecord?.waitingFor),
                isFocused: isFocused,
                companionShown: shownCompanion != nil,
                onToggleCompanion: toggleCompanion,
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
                GeometryReader { geometry in
                    // The coding terminal stays first so showing the shell
                    // below it never recreates it.
                    VStack(spacing: 0) {
                        codingTerminal
                            .frame(maxHeight: .infinity)
                        if let terminal = shownCompanion, let key = companionKey {
                            CompanionBarView(
                                directory: companions.directories[key],
                                paneHeight: geometry.size.height,
                                fraction: companionFraction,
                                onResize: { companions.setFraction($0, forPane: paneId) },
                                onResetSize: { companions.resetFraction(forPane: paneId) },
                                onHide: toggleCompanion
                            )
                            CompanionTerminalRepresentable(terminal: terminal)
                                .id(key)
                                .frame(height: geometry.size.height * companionFraction)
                        }
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
    /// Claude Code's name for the session in this pane, e.g. "github-com-8b".
    var claudeName: String? = nil
    /// Live Claude status, e.g. "busy" or "waiting: permission prompt".
    var claudeStatus: String? = nil
    var claudeWaiting: Bool = false
    let isFocused: Bool
    /// Whether the shell below the coding session is shown.
    var companionShown: Bool = false
    var onToggleCompanion: () -> Void = {}
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

            if let claudeName {
                Text(claudeName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .help("Claude Code session name\(claudeStatus.map { " — \($0)" } ?? "")")
            }
            if claudeWaiting, let claudeStatus {
                Text(claudeStatus)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.orange)
                    .cornerRadius(3)
                    .lineLimit(1)
            }

            Spacer()

            // Pane number indicator with focus highlight
            Text("#\(paneId)")
                .font(.system(size: 10, weight: isFocused ? .bold : .medium))
                .foregroundColor(isFocused ? Color.blue : Color(nsColor: .tertiaryLabelColor))
                .padding(.horizontal, 4)

            // Terminal, Pop-out and Detach buttons (only show if attached)
            if currentSession != nil {
                Button(action: onToggleCompanion) {
                    Image(systemName: companionShown ? "terminal.fill" : "terminal")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(companionShown ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(companionShown ? "Hide Terminal" : "Show Terminal Below (opens in the session's folder)")

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

/// The bar above a companion shell: its folder, and a handle to drag to
/// resize the shell. Double-click returns it to the default height.
struct CompanionBarView: View {
    let directory: String?
    let paneHeight: CGFloat
    /// The shell's share of the pane height.
    let fraction: CGFloat
    let onResize: (CGFloat) -> Void
    let onResetSize: () -> Void
    let onHide: () -> Void

    @State private var dragStartFraction: CGFloat?
    @State private var showsResizeCursor = false

    /// The folder with the home directory shown as "~".
    private var displayDirectory: String {
        guard let directory else { return "" }
        return (directory as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text(displayDirectory)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .help(directory ?? "")
            Spacer()
            Button(action: onHide) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Hide Terminal (keeps it running)")
        }
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(nsColor: .separatorColor)),
            alignment: .top
        )
        .contentShape(Rectangle())
        .onHover { inside in
            guard inside != showsResizeCursor else { return }
            showsResizeCursor = inside
            if inside {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            // Hidden while the pointer was over it: restore the cursor.
            if showsResizeCursor {
                showsResizeCursor = false
                NSCursor.pop()
            }
        }
        .help("Drag to resize. Double-click for the default height.")
        .onTapGesture(count: 2, perform: onResetSize)
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    guard paneHeight > 0 else { return }
                    let start = dragStartFraction ?? fraction
                    dragStartFraction = start
                    // Dragging up makes the shell taller.
                    onResize(start - value.translation.height / paneHeight)
                }
                .onEnded { _ in dragStartFraction = nil }
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
    .environment(CompanionTerminalStore())
    .frame(width: 400, height: 300)
}
