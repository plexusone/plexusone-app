import SwiftUI

/// Main content view for a PlexusOne Desktop window
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var paneManager = PaneManager()
    @State private var gridConfig = GridConfig(columns: 2, rows: 1)
    @State private var windowId: UUID?
    @State private var showNewSessionSheet = false
    @State private var showRestorePrompt = false
    @State private var isReady = false

    private var sessionManager: SessionManager {
        appState.sessionManager
    }

    private var windowStateManager: WindowStateManager {
        appState.windowStateManager
    }

    var body: some View {
        VStack(spacing: 0) {
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

                    // Refresh button
                    Button(action: { Task { await sessionManager.refresh() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh Sessions")
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

    private func registerWindow(config: WindowConfig? = nil) {
        let windowConfig = windowStateManager.registerWindow(config: config)
        windowId = windowConfig.id
        gridConfig = windowConfig.gridConfig

        // Restore pane attachments
        for (paneIdStr, tmuxSessionName) in windowConfig.paneAttachments {
            guard let paneId = Int(paneIdStr) else { continue }
            if let session = sessionManager.sessions.first(where: { $0.tmuxSession == tmuxSessionName }) {
                paneManager.attach(session: session, to: paneId)
            }
        }
    }

    private func restoreWindowState() {
        // Pop the first pending config for this window
        if let config = windowStateManager.popNextPendingConfig() {
            registerWindow(config: config)
        } else {
            registerWindow()
        }

        // Notify AppDelegate to open additional windows for remaining pending configs
        if windowStateManager.hasPendingConfigs {
            NotificationCenter.default.post(
                name: .restoreComplete,
                object: nil,
                userInfo: ["windowStateManager": windowStateManager]
            )
        }
    }

    private func saveState() {
        guard isReady, let id = windowId else { return }
        windowStateManager.updateWindow(id: id, gridConfig: gridConfig, paneManager: paneManager)
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

    var body: some View {
        HStack(spacing: 0) {
            // Pane indicators
            HStack(spacing: 8) {
                ForEach(1...gridConfig.paneCount, id: \.self) { paneId in
                    if let session = paneManager.session(for: paneId) {
                        HStack(spacing: 4) {
                            Text("#\(paneId)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            StatusIndicatorView(status: session.status)
                            Text(session.name)
                                .font(.system(size: 10))
                                .lineLimit(1)
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
