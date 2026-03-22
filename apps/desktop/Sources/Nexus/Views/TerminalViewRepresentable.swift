import SwiftUI
import AppKit

/// SwiftUI wrapper for TerminalViewController
struct TerminalViewRepresentable: NSViewControllerRepresentable {
    @Binding var attachedSession: NexusSession?
    let sessionManager: SessionManager
    var onSessionEnded: (() -> Void)?

    func makeNSViewController(context: Context) -> TerminalViewController {
        let controller = TerminalViewController()

        controller.onSessionEnded = { [onSessionEnded] in
            DispatchQueue.main.async {
                onSessionEnded?()
            }
        }

        return controller
    }

    func updateNSViewController(_ controller: TerminalViewController, context: Context) {
        // Handle session changes
        if let session = attachedSession {
            if controller.attachedSession?.id != session.id {
                controller.attach(to: session)
            }
        } else if controller.isAttached {
            controller.detach()
        }
    }
}

/// Coordinator for handling terminal events
extension TerminalViewRepresentable {
    class Coordinator: NSObject {
        var parent: TerminalViewRepresentable

        init(_ parent: TerminalViewRepresentable) {
            self.parent = parent
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}
