import Foundation
import Combine

/// Connection state for WebSocket
enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case error(String)
}

/// WebSocket service for communicating with tuiparser
@MainActor
class WebSocketService: ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var sessions: [Session] = []
    @Published var currentSessionId: String?
    @Published var currentOutput: String = ""
    @Published var debugLog: String = ""  // Debug: shows last messages

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var serverAddress: String = "ws://127.0.0.1:9600/ws"
    private var token: String = ""

    /// Output buffer per session
    private var outputBuffers: [String: String] = [:]

    init() {}

    /// Connect to the WebSocket server
    func connect(to address: String? = nil) {
        if let address = address {
            serverAddress = address
        }

        print("[WebSocket] Connecting to: \(serverAddress)")
        disconnect()
        connectionState = .connecting

        guard let url = Self.makeURL(address: serverAddress, token: token) else {
            connectionState = .error("Invalid URL: \(serverAddress)")
            return
        }

        urlSession = URLSession(configuration: .default)
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()

        connectionState = .connected
        debugLog = "Connected to \(serverAddress)\n" + debugLog
        print("[WebSocket] Connected, starting receive loop")
        receiveMessage()

        // Request session list
        debugLog = "Sending list request\n" + debugLog
        print("[WebSocket] Sending list request")
        sendMessage(["type": "list"])
    }

    /// Disconnect from the server
    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession = nil
        connectionState = .disconnected
    }

    /// Subscribe to a session's output
    func subscribe(to sessionId: String) {
        currentSessionId = sessionId
        currentOutput = outputBuffers[sessionId] ?? ""
        sendMessage([
            "type": "subscribe",
            "sessionIds": [sessionId]  // Server expects array
        ])
    }

    /// Send an action (for prompts)
    func sendAction(_ action: String) {
        guard let sessionId = currentSessionId else { return }
        sendMessage([
            "type": "action",
            "sessionId": sessionId,
            "action": action
        ])
    }

    /// Send text input
    func sendInput(_ text: String) {
        guard let sessionId = currentSessionId else { return }
        sendMessage([
            "type": "input",
            "sessionId": sessionId,
            "text": text
        ])
    }

    /// Send a key press
    func sendKey(_ key: String) {
        guard let sessionId = currentSessionId else { return }
        sendMessage([
            "type": "key",
            "sessionId": sessionId,
            "key": key
        ])
    }

    /// Update server address
    func setServerAddress(_ address: String) {
        serverAddress = address
    }

    /// Update the token sent to the server; empty sends none
    func setToken(_ token: String) {
        self.token = token
    }

    /// Build the connection URL, adding a non-empty token as the
    /// percent-encoded `token` query parameter (a WebSocket client cannot
    /// always set an Authorization header).
    static func makeURL(address: String, token: String) -> URL? {
        guard var components = URLComponents(string: address) else { return nil }
        guard !token.isEmpty else { return components.url }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = token.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        var items = (components.percentEncodedQueryItems ?? []).filter { $0.name != "token" }
        items.append(URLQueryItem(name: "token", value: encoded))
        components.percentEncodedQueryItems = items
        return components.url
    }

    /// Get current server address
    var currentServerAddress: String {
        serverAddress
    }

    // MARK: - Private Methods

    private func sendMessage(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else {
            return
        }

        webSocketTask?.send(.string(string)) { [weak self] error in
            if let error = error {
                Task { @MainActor in
                    self?.connectionState = .error(error.localizedDescription)
                }
            }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self?.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self?.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                    // Continue receiving
                    self?.receiveMessage()

                case .failure(let error):
                    self?.debugLog = "RECV ERROR: \(error.localizedDescription)\n" + (self?.debugLog ?? "")
                    self?.connectionState = .error(error.localizedDescription)
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        let preview = String(text.prefix(100))
        debugLog = "Recv: \(preview)...\n" + debugLog.prefix(500)
        print("[WebSocket] Received message: \(text.prefix(200))...")

        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let typeString = json["type"] as? String else {
            debugLog = "PARSE FAIL\n" + debugLog
            print("[WebSocket] Failed to parse message as JSON")
            return
        }

        debugLog = "Type: \(typeString)\n" + debugLog
        print("[WebSocket] Message type: \(typeString)")

        switch typeString {
        case "sessions":
            handleSessionsMessage(json)
        case "output":
            handleOutputMessage(json)
        case "status":
            handleStatusMessage(json)
        case "error":
            handleErrorMessage(json)
        default:
            print("[WebSocket] Unknown message type: \(typeString)")
            break
        }
    }

    private func handleSessionsMessage(_ json: [String: Any]) {
        debugLog = "handleSessions called\n" + debugLog
        print("[WebSocket] Handling sessions message")
        guard let sessionsData = json["sessions"] as? [[String: Any]] else {
            debugLog = "SESSIONS PARSE FAIL - keys: \(Array(json.keys))\n" + debugLog
            print("[WebSocket] Failed to parse 'sessions' array from message")
            print("[WebSocket] JSON keys: \(json.keys)")
            return
        }

        debugLog = "Found \(sessionsData.count) raw sessions\n" + debugLog
        print("[WebSocket] Found \(sessionsData.count) sessions in response")

        sessions = sessionsData.compactMap { dict in
            guard let id = dict["id"] as? String,
                  let name = dict["name"] as? String else {
                debugLog = "Session parse fail: \(dict.keys)\n" + debugLog
                print("[WebSocket] Failed to parse session: \(dict)")
                return nil
            }
            let statusString = dict["status"] as? String ?? "unknown"
            let status = Session.SessionStatus(rawValue: statusString) ?? .unknown
            return Session(id: id, name: name, status: status)
        }

        debugLog = "Parsed \(sessions.count) sessions\n" + debugLog
        print("[WebSocket] Parsed \(sessions.count) sessions")

        // Auto-select first session if none selected
        if currentSessionId == nil, let first = sessions.first {
            subscribe(to: first.id)
        }
    }

    private func handleOutputMessage(_ json: [String: Any]) {
        guard let sessionId = json["sessionId"] as? String,
              let output = json["text"] as? String else {  // Server sends "text", not "output"
            return
        }

        // Append to buffer
        var buffer = outputBuffers[sessionId] ?? ""
        buffer += output
        outputBuffers[sessionId] = buffer

        // Update current output if this is the active session
        if sessionId == currentSessionId {
            currentOutput = buffer
        }
    }

    private func handleStatusMessage(_ json: [String: Any]) {
        guard let sessionId = json["sessionId"] as? String,
              let statusString = json["status"] as? String,
              let status = Session.SessionStatus(rawValue: statusString) else {
            return
        }

        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            let session = sessions[index]
            sessions[index] = Session(id: session.id, name: session.name, status: status)
        }
    }

    private func handleErrorMessage(_ json: [String: Any]) {
        if let message = json["message"] as? String {
            connectionState = .error(message)
        }
    }

    /// Clear output buffer for a session
    func clearOutput(for sessionId: String? = nil) {
        let id = sessionId ?? currentSessionId
        guard let id = id else { return }
        outputBuffers[id] = ""
        if id == currentSessionId {
            currentOutput = ""
        }
    }

    /// Refresh session list
    func refreshSessions() {
        sendMessage(["type": "list"])
    }

    /// Create a new tmux session
    func createSession(name: String) {
        sendMessage([
            "type": "create",
            "name": name
        ])
        // Refresh session list after creation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.refreshSessions()
        }
    }
}
