import SwiftUI

/// Bottom status bar showing all sessions with quick-attach functionality
struct StatusBarView: View {
    let sessions: [Session]
    let currentSession: Session?
    let onSelectSession: (Session) -> Void
    let onCreateNew: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Session pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sessions) { session in
                        SessionPillView(
                            session: session,
                            isSelected: session.id == currentSession?.id,
                            onTap: { onSelectSession(session) }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 4) {
                // New session button
                Button(action: onCreateNew) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("New Session (⌘N)")
            }
            .padding(.trailing, 8)
        }
        .frame(height: 28)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(nsColor: .separatorColor)),
            alignment: .top
        )
    }
}

/// Individual session pill in the status bar
struct SessionPillView: View {
    let session: Session
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                StatusIndicatorView(status: session.status)
                Text(session.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                if let wrapper = session.wrapper {
                    WrapperWarningBadge(wrapper: wrapper)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tooltipText)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.2)
        } else if isHovered {
            return Color(nsColor: .controlBackgroundColor)
        } else {
            return Color.clear
        }
    }

    private var tooltipText: String {
        let status = session.status.displayName
        let ago = session.lastActivity.timeAgoString()
        var text = "\(session.name) - \(status) (\(ago))"
        if let wrapper = session.wrapper {
            text += "\n⚠︎ \(wrapper.warning)"
        }
        return text
    }
}

// MARK: - Date Extension

extension Date {
    func timeAgoString() -> String {
        let interval = Date().timeIntervalSince(self)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

#Preview {
    VStack {
        Spacer()
        StatusBarView(
            sessions: [
                Session(name: "coder-1", status: .running),
                Session(name: "coder-2", status: .idle),
                Session(name: "reviewer", status: .stuck),
                Session(name: "planner", status: .running)
            ],
            currentSession: Session(name: "coder-1", status: .running),
            onSelectSession: { _ in },
            onCreateNew: { }
        )
    }
    .frame(width: 600, height: 100)
}
