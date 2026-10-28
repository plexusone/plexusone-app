import SwiftUI
import AppKit

/// Main content view for a PlexusOne Desktop window
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @State private var paneManager = PaneManager()
    @State private var gridConfig = GridConfig(columns: 2, rows: 1)
    @State private var windowId: UUID?
    @State private var showNewSessionSheet = false
    @State private var showAttachSheet = false
    @State private var showRestorePrompt = false
    @State private var showErrorAlert = false
    @State private var isReady = false
    @State private var wrapperBannerDismissed = false
    @AppStorage("suppressWrapperWarning") private var suppressWrapperWarning = false

    private var sessionManager: SessionManager {
        appState.sessionManager
    }

    /// Distinct PTY autocomplete wrappers detected across current sessions,
    /// in a stable order, for the warning banner.
    private var detectedWrappers: [TerminalWrapper] {
        var seen: [TerminalWrapper] = []
        for session in sessionManager.sessions {
            if let wrapper = session.wrapper, !seen.contains(wrapper) {
                seen.append(wrapper)
            }
        }
        return seen
    }

    private var showWrapperBanner: Bool {
        isReady && !suppressWrapperWarning && !wrapperBannerDismissed && !detectedWrappers.isEmpty
    }

    private var windowStateManager: WindowStateManager {
        appState.windowStateManager
    }

    private var inputMonitor: InputMonitor {
        appState.inputMonitor
    }

    var body: some View {
        VStack(spacing: 0) {
            if showWrapperBanner {
                WrapperWarningBanner(
                    wrappers: detectedWrappers,
                    onDismiss: { wrapperBannerDismissed = true },
                    onSuppress: { suppressWrapperWarning = true }
                )
            }

            if !isReady {
                // Loading state
                VStack {
                    ProgressView()
                    Text("Loading...")
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Grid layout with panes
                GridLayoutView(
                    config: gridConfig,
                    sessions: sessionManager.sessions,
                    sessionManager: sessionManager,
                    inputMonitor: inputMonitor,
                    paneManager: paneManager,
                    onRequestNewSession: {
                        showNewSessionSheet = true
                    }
                )
            }

            // Status bar
            if isReady {
                GridStatusBarView(
                    sessions: sessionManager.sessions,
                    paneManager: paneManager,
                    gridConfig: gridConfig,
                    onCreateNew: {
                        showNewSessionSheet = true
                    }
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                // Layout picker
                if isReady {
                    LayoutPickerView(config: $gridConfig)
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if isReady {
                    // New session button
                    Button(action: { showNewSessionSheet = true }) {
                        Image(systemName: "plus")
                    }
                    .help("New Session (⌘N)")

                    Button(action: { openWindow(id: ClaudeSessionsView.windowId) }) {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .help("Claude Sessions (⇧⌘S)")

                    // Refresh button
                    Button(action: { Task { await sessionManager.refresh() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh Sessions")
                }
            }
        }
        .focusedSceneValue(\.windowActions, windowActions)
        .sheet(isPresented: $showAttachSheet) {
            AttachSessionSheet(sessions: sessionManager.sessions) { session in
                if let paneId = focusedPaneId() {
                    paneManager.attach(session: session, to: paneId)
                } else {
                    attachToFirstEmptyPane(session)
                }
            }
        }
        .sheet(isPresented: $showNewSessionSheet) {
            NewSessionSheet(
                onSessionCreated: { session in
                    // Attach to first empty pane
                    attachToFirstEmptyPane(session)
                }
            )
            .environment(appState)
        }
        .alert("Restore Previous Session?", isPresented: $showRestorePrompt) {
            Button("Restore") {
                restoreWindowState()
            }
            Button("Start Fresh", role: .destructive) {
                windowStateManager.clearState()
                registerWindow()
            }
        } message: {
            let configs = windowStateManager.configsToRestore()
            if let config = configs.first {
                let attachmentCount = config.paneAttachments.count
                Text("Found \(configs.count) saved window(s). First window: \(config.gridColumns)×\(config.gridRows) layout with \(attachmentCount) attached pane(s).")
            } else {
                Text("Would you like to restore your previous session?")
            }
        }
        .alert("Session Error", isPresented: $showErrorAlert) {
            Button("OK") {
                sessionManager.clearError()
            }
        } message: {
            if let error = sessionManager.error {
                Text(error.localizedDescription)
            }
        }
        .onChange(of: sessionManager.error) { _, newError in
            showErrorAlert = newError != nil
        }
        .task {
            await initialize()
        }
        .onDisappear {
            // Unregister window when it closes
            if let id = windowId {
                windowStateManager.unregisterWindow(id: id)
            }
        }
        .onChange(of: gridConfig) { _, _ in
            saveState()
        }
        .onChange(of: paneManager.attachedSessions) { _, _ in
            saveState()
        }
    }

    private func initialize() async {
        // Small delay to let the window appear
        try? await Task.sleep(for: .milliseconds(100))

        // Start the shared app state monitoring (idempotent - only runs once)
        await appState.startMonitoring()

        // Mark as ready
        isReady = true

        guard windowId == nil else { return }

        // Sessions restored from the Claude Sessions window
        if !appState.pendingRestoreSessions.isEmpty {
            let restored = appState.pendingRestoreSessions
            appState.pendingRestoreSessions = []
            setupAsRestoreWindow(with: restored)
            return
        }

        // Check for pending pop-out session first
        if let popOutSession = appState.pendingPopOutSession {
            appState.pendingPopOutSession = nil
            setupAsPopOutWindow(with: popOutSession)
            return
        }

        // Check if there are pending configs to restore
        if windowStateManager.hasPendingConfigs {
            // If this is an additional window (not the first), pop and use the next config directly
            // The first window shows the restore prompt, additional windows auto-restore
            if windowStateManager.windowConfigs.isEmpty {
                // First window - show restore prompt
                showRestorePrompt = true
            } else {
                // Additional window - pop the next pending config
                if let config = windowStateManager.popNextPendingConfig() {
                    registerWindow(config: config)
                } else {
                    registerWindow()
                }
            }
        } else if windowStateManager.hasRestoredState && windowStateManager.windowConfigs.isEmpty {
            // First launch with saved state - show restore prompt
            showRestorePrompt = true
        } else {
            // No saved state or already restored - register new window
            registerWindow()
        }
    }

    private func setupAsPopOutWindow(with session: Session) {
        // Create a 1×1 window config with the session attached
        let popOutConfig = WindowConfig(
            gridConfig: GridConfig(columns: 1, rows: 1),
            paneAttachments: ["1": session.tmuxSession]
        )
        registerWindow(config: popOutConfig)
    }

    private func setupAsRestoreWindow(with sessions: [Session]) {
        let grid = GridConfig.fitting(sessions.count)
        var attachments: [String: String] = [:]
        for (index, session) in sessions.prefix(grid.paneCount).enumerated() {
            attachments[String(index + 1)] = session.tmuxSession
        }
        registerWindow(config: WindowConfig(gridConfig: grid, paneAttachments: attachments))
    }

    private func registerWindow(config: WindowConfig? = nil) {
        let windowConfig = windowStateManager.registerWindow(config: config)
        windowId = windowConfig.id
        gridConfig = windowConfig.gridConfig

        // Restore pane attachments
        NSLog("PlexusOne: Restoring %d pane attachments, available sessions: %@",
              windowConfig.paneAttachments.count,
              sessionManager.sessions.map { $0.tmuxSession }.joined(separator: ", "))

        for (paneIdStr, tmuxSessionName) in windowConfig.paneAttachments {
            guard let paneId = Int(paneIdStr) else { continue }
            if let session = sessionManager.sessions.first(where: { $0.tmuxSession == tmuxSessionName }) {
                paneManager.attach(session: session, to: paneId)
                NSLog("PlexusOne: Restored pane %d with session: %@", paneId, session.name)
            } else {
                NSLog("PlexusOne: Could not find session '%@' for pane %d", tmuxSessionName, paneId)
            }
        }
    }

    private func restoreWindowState() {
        // Ensure sessions are loaded before restoring
        Task {
            // Force a refresh to ensure we have the latest sessions
            await sessionManager.refresh()

            await MainActor.run {
                // Pop the first pending config for this window
                if let config = windowStateManager.popNextPendingConfig() {
                    NSLog("PlexusOne: Restoring window with config: %@", config.paneAttachments.description)
                    registerWindow(config: config)
                } else {
                    NSLog("PlexusOne: No pending config, registering new window")
                    registerWindow()
                }

                // Open one more window per remaining config; each new
                // window's initialize() pops its own config.
                for _ in windowStateManager.configsToRestore() {
                    openWindow(id: "main")
                }
            }
        }
    }

    private func saveState() {
        guard isReady, let id = windowId else { return }
        windowStateManager.updateWindow(id: id, gridConfig: gridConfig, paneManager: paneManager)
    }

    // MARK: - Menu Commands

    /// Actions the app menu runs against this window while it is key.
    private var windowActions: WindowActions? {
        guard isReady else { return nil }
        return WindowActions(
            newSession: { showNewSessionSheet = true },
            attachSession: { showAttachSheet = true },
            detachFocusedPane: {
                if let paneId = focusedPaneId() {
                    paneManager.detach(paneId: paneId)
                }
            },
            focusNextPane: { cycleFocus(by: 1) },
            focusPreviousPane: { cycleFocus(by: -1) }
        )
    }

    /// The pane whose terminal has keyboard focus in the key window.
    /// Menu commands only reach the key window, so that is this window.
    private func focusedPaneId() -> Int? {
        (NSApp.keyWindow?.firstResponder as? AppTerminalView)?.paneId
    }

    /// Move keyboard focus to the next/previous pane that has a terminal.
    private func cycleFocus(by step: Int) {
        guard let window = NSApp.keyWindow, let contentView = window.contentView else { return }
        let terminals = Self.terminalViews(in: contentView)
            .filter { $0.isSessionAttached && $0.paneId != nil }
            .sorted { ($0.paneId ?? 0) < ($1.paneId ?? 0) }
        guard !terminals.isEmpty else { return }

        let next: Int
        if let current = terminals.firstIndex(where: { $0 === window.firstResponder }) {
            next = (current + step + terminals.count) % terminals.count
        } else {
            next = step > 0 ? 0 : terminals.count - 1
        }
        // The pane's container observes firstResponder and updates the
        // focus highlight.
        window.makeFirstResponder(terminals[next])
    }

    private static func terminalViews(in view: NSView) -> [AppTerminalView] {
        if let terminal = view as? AppTerminalView {
            return [terminal]
        }
        return view.subviews.flatMap { terminalViews(in: $0) }
    }

    private func attachToFirstEmptyPane(_ session: Session) {
        // Find first empty pane and attach
        for paneId in 1...gridConfig.paneCount {
            if paneManager.session(for: paneId) == nil {
                paneManager.attach(session: session, to: paneId)
                return
            }
        }
        // If all panes are full, attach to pane 1
        paneManager.attach(session: session, to: 1)
    }
}

/// Status bar adapted for grid layout
struct GridStatusBarView: View {
    let sessions: [Session]
    let paneManager: PaneManager
    let gridConfig: GridConfig
    let onCreateNew: () -> Void

    /// The pane's session as of the latest refresh, so status stays current.
    private func liveSession(for paneId: Int) -> Session? {
        guard let attached = paneManager.session(for: paneId) else { return nil }
        return sessions.first { $0.id == attached.id } ?? attached
    }

    var body: some View {
        HStack(spacing: 0) {
            // Pane indicators
            HStack(spacing: 8) {
                ForEach(1...gridConfig.paneCount, id: \.self) { paneId in
                    if let session = liveSession(for: paneId) {
                        HStack(spacing: 4) {
                            Text("#\(paneId)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            StatusIndicatorView(status: session.status)
                            Text(session.name)
                                .font(.system(size: 10))
                                .lineLimit(1)
                            if let wrapper = session.wrapper {
                                WrapperWarningBadge(wrapper: wrapper)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(4)
                    } else {
                        HStack(spacing: 4) {
                            Text("#\(paneId)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text("empty")
                                .font(.system(size: 10))
                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            // Session count
            Text("\(sessions.count) sessions")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(.trailing, 8)

            // New session button
            Button(action: onCreateNew) {
                Image(systemName: "plus")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .frame(height: 24)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(nsColor: .separatorColor)),
            alignment: .top
        )
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .frame(width: 1000, height: 600)
}
