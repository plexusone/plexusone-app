import Foundation
import Observation
import AppKit
import AssistantKit
import UserNotifications

/// Monitors terminal content for input prompts from AI assistants.
/// Uses AssistantKit's pattern detectors to identify when the user needs to respond.
///
/// Thread Safety: This class is `@MainActor` isolated since it:
/// - Updates UI-observable state (`activeAlerts`, `activeSuggestedActions`)
/// - Posts NotificationCenter notifications
/// - Interacts with AppKit (NSSound) and UserNotifications
@MainActor
@Observable
final class InputMonitor {
    /// Active alerts by session ID
    private(set) var activeAlerts: [UUID: DetectionResult] = [:]

    /// Suggested actions for active alerts
    private(set) var activeSuggestedActions: [UUID: [SuggestedAction]] = [:]

    /// Detectors to use for scanning terminal content
    private nonisolated let detectors: [any InputDetector]

    /// Whether to show macOS notifications
    var enableNotifications: Bool = false

    /// Whether to play sound on input detection
    var enableSound: Bool = false

    /// Minimum confidence threshold for alerts
    var confidenceThreshold: Double = 0.7

    /// Initialize InputMonitor.
    /// - Parameter requestNotifications: Whether to request notification permissions (set to false in tests)
    nonisolated init(requestNotifications: Bool = true) {
        self.detectors = [
            ClaudeDetector(),
            KiroDetector(),
            UniversalDetector()
        ]

        // Request notification permission if needed (skip in test environments)
        if requestNotifications {
            Task { @MainActor in
                self.requestNotificationPermission()
            }
        }
    }

    // MARK: - Terminal Content Processing

    /// Process terminal update from SwiftTerm's rangeChanged delegate.
    /// - Parameters:
    ///   - sessionId: The session UUID this content belongs to.
    ///   - content: Terminal content to scan (typically last N lines).
    ///   - cursorPosition: Optional cursor position (row, col) for context.
    func processTerminalUpdate(
        sessionId: UUID,
        content: String,
        cursorPosition: (row: Int, col: Int)?
    ) {
        // Scan content using all detectors
        for detector in detectors {
            if let result = detector.detect(in: content, cursorPosition: cursorPosition) {
                // Check confidence threshold
                guard result.confidence >= confidenceThreshold else { continue }

                // Update state
                activeAlerts[sessionId] = result
                activeSuggestedActions[sessionId] = result.suggestedActions

                // Notify
                notifyInputDetected(sessionId: sessionId, result: result)
                return
            }
        }

        // No match - clear any existing alert for this session
        clearAlert(for: sessionId)
    }

    /// Clear alert for a specific session.
    func clearAlert(for sessionId: UUID) {
        activeAlerts.removeValue(forKey: sessionId)
        activeSuggestedActions.removeValue(forKey: sessionId)
    }

    /// Clear all alerts.
    func clearAllAlerts() {
        activeAlerts.removeAll()
        activeSuggestedActions.removeAll()
    }

    /// Check if a session has an active input alert.
    func hasAlert(for sessionId: UUID) -> Bool {
        activeAlerts[sessionId] != nil
    }

    /// Get the detection result for a session.
    func alert(for sessionId: UUID) -> DetectionResult? {
        activeAlerts[sessionId]
    }

    /// Get suggested actions for a session.
    func suggestedActions(for sessionId: UUID) -> [SuggestedAction] {
        activeSuggestedActions[sessionId] ?? []
    }

    // MARK: - Agent Detection

    /// Detect which agent type is running in the terminal content.
    func detectAgentType(in content: String) -> AgentType? {
        for detector in detectors {
            if detector.detectAgent(in: content) {
                // Convert AssistantKit.AgentType to our AgentType
                return convertAgentType(detector.agentType)
            }
        }
        return nil
    }

    // MARK: - Private Methods

    private func notifyInputDetected(sessionId: UUID, result: DetectionResult) {
        // Post notification for UI updates
        NotificationCenter.default.post(
            name: .inputDetected,
            object: nil,
            userInfo: [
                "sessionId": sessionId,
                "patternType": result.pattern.type.rawValue,
                "matchedText": result.matchedText,
                "confidence": result.confidence
            ]
        )

        // macOS notification if enabled
        if enableNotifications {
            sendSystemNotification(result: result)
        }

        // Sound if enabled
        if enableSound {
            NSSound.beep()
        }
    }

    private func requestNotificationPermission() {
        // Guard against test environments where UNUserNotificationCenter might crash
        guard NSApp != nil else { return }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            // Permission result handled silently
        }
    }

    private func sendSystemNotification(result: DetectionResult) {
        // Guard against test environments
        guard NSApp != nil else { return }

        let content = UNMutableNotificationContent()
        content.title = "Input Required"
        content.body = formatNotificationBody(result: result)

        if enableSound {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Immediate delivery
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func formatNotificationBody(result: DetectionResult) -> String {
        let maxLength = 100
        let text = result.matchedText.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.count > maxLength {
            return String(text.prefix(maxLength)) + "..."
        }
        return text
    }

    /// Convert AssistantKit's AgentType to PlexusOne's AgentType
    private func convertAgentType(_ kitType: AssistantKit.AgentType) -> AgentType? {
        switch kitType {
        case .claude: return .claude
        case .kiro: return .kiro
        case .codex: return .codex
        case .gemini: return .gemini
        case .unknown: return nil
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when an input prompt is detected in a terminal session.
    static let inputDetected = Notification.Name("com.plexusone.desktop.inputDetected")

    /// Posted when an input alert is cleared for a session.
    static let inputCleared = Notification.Name("com.plexusone.desktop.inputCleared")

    /// Posted when a pane gains or loses keyboard focus.
    /// UserInfo: ["sessionId": UUID, "focused": Bool]
    static let paneFocusChanged = Notification.Name("com.plexusone.desktop.paneFocusChanged")
}

// MARK: - InputStatus Conversion

extension InputStatus {
    /// Create InputStatus from a DetectionResult
    init(from result: DetectionResult) {
        self.detectedAt = Date()
        self.patternType = result.pattern.type.rawValue
        self.matchedText = result.matchedText
        self.confidence = result.confidence
    }
}
