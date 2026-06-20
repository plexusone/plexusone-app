import SwiftUI
import AppKit
import SwiftTerm
import AssistantKit

/// Container view that hosts AppTerminalView and forwards scroll events
class TerminalContainerView: NSView {
    let terminalView: AppTerminalView
    private var lastFocusState = false
    private var windowObservation: NSKeyValueObservation?

    init(terminalView: AppTerminalView) {
        self.terminalView = terminalView
        super.init(frame: .zero)

        addSubview(terminalView)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        windowObservation?.invalidate()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Observe window's firstResponder changes
        windowObservation?.invalidate()
        windowObservation = window?.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
            self?.updateFocusState()
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        // Forward scroll events to SwiftTerm's handler
        terminalView.scrollWheel(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        // Forward first responder to terminal and notify focus change
        let result = terminalView.becomeFirstResponder()
        if result {
            postFocusChange(focused: true)
        }
        return result
    }

    override func mouseDown(with event: NSEvent) {
        // Ensure we become first responder on click
        window?.makeFirstResponder(terminalView)
        postFocusChange(focused: true)
        // Forward to terminal for text selection
        terminalView.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // When user types, ensure we're showing the latest output
        // This prevents "stuck in scrollback" issues where old content is visible
        terminalView.scrollToBottom()
        // Forward to terminal for processing
        terminalView.keyDown(with: event)
    }

    /// Check if this terminal has focus and notify if changed
    func updateFocusState() {
        let isFocused = window?.firstResponder === terminalView
        if isFocused != lastFocusState {
            lastFocusState = isFocused
            postFocusChange(focused: isFocused)
        }
    }

    private func postFocusChange(focused: Bool) {
        guard let sessionId = terminalView.attachedSessionId() else { return }
        lastFocusState = focused

        NotificationCenter.default.post(
            name: .paneFocusChanged,
            object: nil,
            userInfo: [
                "sessionId": sessionId,
                "focused": focused
            ]
        )
    }
}

/// SwiftUI wrapper for AppTerminalView using NSViewRepresentable
/// This approach follows SwiftTerm's own iOS SwiftUI implementation pattern
struct AppTerminalViewRepresentable: NSViewRepresentable {
    typealias NSViewType = TerminalContainerView

    @Binding var attachedSession: Session?
    let sessionManager: SessionManager
    let inputMonitor: InputMonitor
    var onSessionEnded: (() -> Void)?
    var onInputDetected: ((DetectionResult) -> Void)?

    func makeNSView(context: Context) -> TerminalContainerView {
        let terminalView = AppTerminalView(frame: .zero)
        terminalView.processDelegate = context.coordinator
        context.coordinator.terminalView = terminalView

        // Configure appearance
        configureAppearance(terminalView)

        // Add local event monitor for scroll wheel events (trackpad two-finger scroll)
        context.coordinator.scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            context.coordinator.handleScrollEvent(event)
            return event
        }

        let container = TerminalContainerView(terminalView: terminalView)
        context.coordinator.containerView = container

        // Start input detection and focus polling
        context.coordinator.startInputDetection()

        return container
    }

    func updateNSView(_ container: TerminalContainerView, context: Context) {
        let view = container.terminalView

        // Ensure layout is current
        view.updateSizeIfNeeded()

        // Handle session attachment changes
        if let session = attachedSession {
            // Attach if not already attached to this session
            if view.attachedSessionId() != session.id {
                view.attach(to: session)
            }
        } else if view.isSessionAttached {
            view.detach()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func configureAppearance(_ view: AppTerminalView) {
        // Use system monospace font
        let fontSize: CGFloat = 13
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.font = font

        // Configure colors
        view.nativeBackgroundColor = NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        view.nativeForegroundColor = NSColor(calibratedRed: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)

        // Cursor style
        view.caretColor = NSColor.white

        // Configure scrollback buffer (default is only 500 lines)
        // AI agent output can be lengthy, so use 10,000 lines
        view.changeScrollback(10000)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var parent: AppTerminalViewRepresentable
        weak var terminalView: AppTerminalView?
        weak var containerView: TerminalContainerView?
        var scrollMonitor: Any?
        var inputDetectionTimer: Timer?

        /// Cache last content hash to skip redundant input detection
        private var lastContentHash: Int = 0

        init(_ parent: AppTerminalViewRepresentable) {
            self.parent = parent
        }

        deinit {
            inputDetectionTimer?.invalidate()
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        /// Start periodic input detection and focus checking
        func startInputDetection() {
            // Poll for input prompts and focus state every 500ms
            // Timer fires on main thread, checkForInputPrompts is @MainActor
            inputDetectionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    self.checkForInputPrompts()
                }
                self.containerView?.updateFocusState()
            }
        }

        @MainActor
        private func checkForInputPrompts() {
            guard let terminalView = terminalView,
                  let sessionId = terminalView.attachedSessionId() else {
                return
            }

            // Extract recent terminal content for input detection
            let content = extractRecentContent(from: terminalView, lineCount: 15)
            guard !content.isEmpty else { return }

            // Skip processing if content hasn't changed (performance optimization)
            let contentHash = content.hashValue
            guard contentHash != lastContentHash else { return }
            lastContentHash = contentHash

            // Get cursor position
            guard let terminal = terminalView.terminal else { return }
            let cursor = terminal.getCursorLocation()
            let cursorPosition = (row: cursor.y, col: cursor.x)

            // Process through InputMonitor
            parent.inputMonitor.processTerminalUpdate(
                sessionId: sessionId,
                content: content,
                cursorPosition: cursorPosition
            )

            // Notify parent if input detected
            if let result = parent.inputMonitor.alert(for: sessionId) {
                parent.onInputDetected?(result)
            }
        }

        func handleScrollEvent(_ event: NSEvent) {
            guard let terminalView = terminalView else { return }

            // Check if the event is within the terminal view's bounds
            guard terminalView.window != nil else { return }
            let locationInWindow = event.locationInWindow
            let locationInView = terminalView.convert(locationInWindow, from: nil)

            guard terminalView.bounds.contains(locationInView) else { return }

            // First try to send mouse wheel events to the terminal app (e.g., tmux)
            // If mouse reporting is not enabled, fall back to native scrollback
            if !terminalView.handleMouseWheelEvent(event) {
                terminalView.scrollWheel(with: event)
            }
        }

        // MARK: - LocalProcessTerminalViewDelegate

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            inputDetectionTimer?.invalidate()
            DispatchQueue.main.async { [weak self] in
                self?.parent.onSessionEnded?()
            }
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            // Terminal size changed - tmux handles via SIGWINCH
        }

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            // Could propagate title changes if needed
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            // Could be used to update UI with current directory
        }

        func requestOpenLink(source: LocalProcessTerminalView, link: String, params: [String: String]) {
            // Handle link clicks (e.g., URLs in terminal output)
            if let url = URL(string: link) {
                NSWorkspace.shared.open(url)
            }
        }

        // MARK: - Input Detection Helpers

        /// Extract the last N lines of terminal content for pattern matching
        private func extractRecentContent(from terminalView: AppTerminalView, lineCount: Int) -> String {
            guard let terminal = terminalView.terminal else { return "" }

            let dims = terminal.getDims()
            let topVisible = terminal.getTopVisibleRow()
            let totalRows = topVisible + dims.rows

            // Get the last N visible lines
            let startRow = max(0, totalRows - lineCount)
            var lines: [String] = []

            for row in startRow..<totalRows {
                if let line = terminal.getLine(row: row) {
                    lines.append(line.translateToString(trimRight: true))
                }
            }

            return lines.joined(separator: "\n")
        }
    }
}
