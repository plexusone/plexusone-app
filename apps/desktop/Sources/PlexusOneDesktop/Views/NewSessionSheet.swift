import SwiftUI

/// Sheet for creating a new tmux session
struct NewSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var sessionName: String = ""
    @State private var selectedAgentType: AgentType?
    @State private var customCommand: String = ""
    @State private var useCustomCommand: Bool = false
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?

    let onSessionCreated: (Session) -> Void

    private var sessionManager: SessionManager {
        appState.sessionManager
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Session")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Form
            Form {
                // Session name
                TextField("Session Name", text: $sessionName)
                    .textFieldStyle(.roundedBorder)

                // Agent type (optional)
                Picker("Agent Type", selection: $selectedAgentType) {
                    Text("None").tag(nil as AgentType?)
                    ForEach(AgentType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type as AgentType?)
                    }
                }

                // Custom command toggle
                Toggle("Use custom command", isOn: $useCustomCommand)

                if useCustomCommand {
                    TextField("Command", text: $customCommand)
                        .textFieldStyle(.roundedBorder)
                        .help("Command to run in the session (default: your shell)")
                }

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .padding()

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Create") {
                    createSession()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(sessionName.isEmpty || isCreating)
            }
            .padding()
        }
        .frame(width: 400)
        .onAppear {
            // Generate a default name
            sessionName = generateDefaultName()
        }
    }

    private func generateDefaultName() -> String {
        let existingNames = Set(sessionManager.sessions.map { $0.name })
        var index = 1
        var name = "session-\(index)"

        while existingNames.contains(name) {
            index += 1
            name = "session-\(index)"
        }

        return name
    }

    private func createSession() {
        guard !sessionName.isEmpty else { return }

        isCreating = true
        errorMessage = nil

        let command = useCustomCommand && !customCommand.isEmpty ? customCommand : nil

        Task {
            do {
                var session = try await sessionManager.createSession(name: sessionName, command: command)
                session.agentType = selectedAgentType
                let createdSession = session  // Immutable copy for concurrent access

                await MainActor.run {
                    onSessionCreated(createdSession)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
}

#Preview {
    NewSessionSheet(
        onSessionCreated: { _ in }
    )
    .environment(AppState())
}
