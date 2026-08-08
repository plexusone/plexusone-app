import Foundation
import CryptoKit
import AssistantKit

extension UUID {
    /// Fixed namespace for PlexusOne tmux-session identities (RFC 4122).
    private static let tmuxSessionNamespace = UUID(uuidString: "b3f0e6a2-1c4d-5e6f-8a9b-0c1d2e3f4a5b")!

    /// Derive a stable, deterministic UUID (version 5, RFC 4122) from a tmux
    /// session name. The same name always yields the same UUID, so a session
    /// keeps one identity across periodic refreshes instead of getting a fresh
    /// random UUID each cycle (which would churn SwiftUI identity).
    static func forTmuxSession(named name: String) -> UUID {
        var hasher = Insecure.SHA1()
        withUnsafeBytes(of: tmuxSessionNamespace.uuid) { hasher.update(bufferPointer: $0) }
        hasher.update(data: Data(name.utf8))
        var digest = Array(hasher.finalize()) // 20 bytes; use the first 16

        // Set the version (5) and variant (RFC 4122) bits.
        digest[6] = (digest[6] & 0x0F) | 0x50
        digest[8] = (digest[8] & 0x3F) | 0x80

        let bytes = (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        )
        return UUID(uuid: bytes)
    }
}

/// Represents a tmux session that can be attached to a pane
struct Session: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let tmuxSession: String
    var agentType: AgentType?
    var status: SessionStatus
    var lastActivity: Date
    var metadata: [String: String]
    var inputStatus: InputStatus?

    init(
        id: UUID = UUID(),
        name: String,
        tmuxSession: String? = nil,
        agentType: AgentType? = nil,
        status: SessionStatus = .detached,
        lastActivity: Date = Date(),
        metadata: [String: String] = [:],
        inputStatus: InputStatus? = nil
    ) {
        self.id = id
        self.name = name
        self.tmuxSession = tmuxSession ?? name
        self.agentType = agentType
        self.status = status
        self.lastActivity = lastActivity
        self.metadata = metadata
        self.inputStatus = inputStatus
    }
}

/// Status of detected input prompt
struct InputStatus: Codable, Hashable {
    let detectedAt: Date
    let patternType: String  // PatternType.rawValue
    let matchedText: String
    let confidence: Double

    // For Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(detectedAt)
        hasher.combine(patternType)
        hasher.combine(matchedText)
    }

    static func == (lhs: InputStatus, rhs: InputStatus) -> Bool {
        lhs.detectedAt == rhs.detectedAt &&
        lhs.patternType == rhs.patternType &&
        lhs.matchedText == rhs.matchedText
    }
}

/// Status of a tmux session based on activity
enum SessionStatus: String, Codable, Hashable {
    case running    // Active output within threshold
    case idle       // No recent output
    case stuck      // No output for extended period
    case detached   // No pane attached (still running in tmux)

    var displayName: String {
        switch self {
        case .running: return "Running"
        case .idle: return "Idle"
        case .stuck: return "Stuck"
        case .detached: return "Detached"
        }
    }

    var statusColor: String {
        switch self {
        case .running: return "green"
        case .idle: return "yellow"
        case .stuck: return "red"
        case .detached: return "gray"
        }
    }
}

/// Type of AI agent running in the session
enum AgentType: String, Codable, Hashable, CaseIterable {
    case claude
    case codex
    case gemini
    case kiro
    case custom

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .kiro: return "Kiro"
        case .custom: return "Custom"
        }
    }
}
