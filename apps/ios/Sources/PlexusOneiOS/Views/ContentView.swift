import SwiftUI

/// Main content view with iMessage-style sessions list
public struct ContentView: View {
    @StateObject private var webSocket = WebSocketService()
    @State private var showSettings = false
    @State private var serverAddress = "ws://127.0.0.1:9600/ws"
    @State private var serverToken = ""
    @State private var navigationPath = NavigationPath()
    @State private var showNewSessionSheet = false

    public init() {}

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            SessionsListView(
                sessions: webSocket.sessions,
                connectionState: webSocket.connectionState,
                onSelectSession: { session in
                    webSocket.subscribe(to: session.id)
                    navigationPath.append(session)
                },
                onRefresh: {
                    webSocket.refreshSessions()
                }
            )
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    connectionStatusButton
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        webSocket.refreshSessions()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // Floating compose button like iMessage
                Button {
                    showNewSessionSheet = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
            .navigationDestination(for: Session.self) { session in
                SessionTerminalView(
                    session: session,
                    output: webSocket.currentOutput,
                    onClear: {
                        webSocket.clearOutput()
                    }
                )
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    serverAddress: $serverAddress,
                    serverToken: $serverToken,
                    connectionState: webSocket.connectionState,
                    onConnect: {
                        UserDefaults.standard.set(serverAddress, forKey: "serverAddress")
                        UserDefaults.standard.set(serverToken, forKey: "serverToken")
                        webSocket.setServerAddress(serverAddress)
                        webSocket.setToken(serverToken)
                        webSocket.connect()
                    },
                    onDisconnect: {
                        webSocket.disconnect()
                    }
                )
            }
            .sheet(isPresented: $showNewSessionSheet) {
                NewSessionView(
                    onCreate: { sessionName in
                        webSocket.createSession(name: sessionName)
                        showNewSessionSheet = false
                    }
                )
            }
            .onAppear {
                if let saved = UserDefaults.standard.string(forKey: "serverAddress") {
                    serverAddress = saved
                }
                serverToken = UserDefaults.standard.string(forKey: "serverToken") ?? ""
                webSocket.setServerAddress(serverAddress)
                webSocket.setToken(serverToken)
                webSocket.connect()
            }
        }
    }

    private var connectionStatusButton: some View {
        Button {
            switch webSocket.connectionState {
            case .disconnected, .error:
                webSocket.connect()
            default:
                break
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 8, height: 8)
                Text("\(connectionText) (\(webSocket.sessions.count))")
                    .font(.caption)
            }
        }
    }

    private var connectionColor: Color {
        switch webSocket.connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    private var connectionText: String {
        switch webSocket.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .disconnected: return "Disconnected"
        case .error: return "Error"
        }
    }
}

// MARK: - Sessions List View (iMessage-style)

struct SessionsListView: View {
    let sessions: [Session]
    let connectionState: ConnectionState
    let onSelectSession: (Session) -> Void
    let onRefresh: () -> Void

    var body: some View {
        Group {
            if case .disconnected = connectionState {
                disconnectedView
            } else if case .connecting = connectionState {
                connectingView
            } else if sessions.isEmpty {
                emptyView
            } else {
                sessionsList
            }
        }
    }

    private var sessionsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sessions) { session in
                    Button {
                        onSelectSession(session)
                    } label: {
                        HStack {
                            Circle()
                                .fill(session.status == .running ? Color.green : Color.blue)
                                .frame(width: 10, height: 10)
                            Text(session.name)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                    }
                    Divider()
                }
            }
        }
        .refreshable {
            onRefresh()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Sessions")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Sessions count: \(sessions.count)")
                .font(.caption)
                .foregroundColor(.orange)
            Button("Refresh") {
                onRefresh()
            }
            .buttonStyle(.bordered)
        }
    }

    private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Connecting...")
                .foregroundColor(.secondary)
        }
    }

    private var disconnectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("Disconnected")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Check your connection settings")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Session Row (like iMessage conversation row)

struct SessionRowView: View {
    let session: Session

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator circle
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 50, height: 50)
                Image(systemName: "terminal")
                    .font(.system(size: 20))
                    .foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(session.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        switch session.status {
        case .running: return .green
        case .idle: return .blue
        case .stuck: return .orange
        case .error: return .red
        case .unknown: return .gray
        }
    }

    private var statusText: String {
        switch session.status {
        case .running: return "Running"
        case .idle: return "Idle"
        case .stuck: return "Waiting for input"
        case .error: return "Error"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Session Terminal View

struct SessionTerminalView: View {
    let session: Session
    let output: String
    let onClear: () -> Void
    @State private var terminalSize: (cols: Int, rows: Int) = (80, 24)

    var body: some View {
        VStack(spacing: 0) {
            // Terminal view
            if output.isEmpty {
                emptyTerminalView
            } else {
                TerminalViewWrapper(
                    output: output,
                    terminalSize: $terminalSize
                )
            }

            // Bottom toolbar
            bottomToolbar
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyTerminalView: some View {
        VStack {
            Spacer()
            Text("No output yet")
                .foregroundColor(.secondary)
            Text("Waiting for terminal output...")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
    }

    private var bottomToolbar: some View {
        HStack {
            Text("\(terminalSize.cols)×\(terminalSize.rows)")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button {
                onClear()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Binding var serverAddress: String
    @Binding var serverToken: String
    let connectionState: ConnectionState
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("WebSocket URL", text: $serverAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    SecureField("Token (optional)", text: $serverToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack {
                        Text("Status")
                        Spacer()
                        Text(statusText)
                            .foregroundColor(statusColor)
                    }
                }

                Section {
                    Button("Connect") {
                        onConnect()
                        dismiss()
                    }

                    Button("Disconnect", role: .destructive) {
                        onDisconnect()
                    }
                }

                Section("Help") {
                    Text("Enter the WebSocket URL of your tuiparser server, for example ws://192.168.1.100:9600/ws, and the token it was started with. A server reachable from the network requires a token; use wss:// behind a TLS proxy.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var statusText: String {
        switch connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .disconnected: return "Disconnected"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private var statusColor: Color {
        switch connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }
}

// MARK: - New Session View

struct NewSessionView: View {
    let onCreate: (String) -> Void
    @State private var sessionName = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("New Session") {
                    TextField("Session Name", text: $sessionName)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Button("Create Session") {
                        guard !sessionName.isEmpty else { return }
                        onCreate(sessionName)
                    }
                    .disabled(sessionName.isEmpty)
                }

                Section("Info") {
                    Text("Create a new tmux session on the server. The session will appear in your sessions list.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
