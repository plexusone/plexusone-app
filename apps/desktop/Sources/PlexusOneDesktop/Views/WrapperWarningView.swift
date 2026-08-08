import AppKit
import SwiftUI

/// Small amber warning triangle shown next to a session that is running behind a
/// `figterm`-style PTY autocomplete wrapper (a known cause of frozen terminals).
/// Hovering reveals the wrapper and the fix.
struct WrapperWarningBadge: View {
    let wrapper: TerminalWrapper

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 9))
            .foregroundColor(.orange)
            .help(wrapper.warning)
            .accessibilityLabel("\(wrapper.displayName) wrapper detected — hang risk")
    }
}

/// Dismissible banner shown when any visible session is wrapped. Explains the
/// hang risk once and offers to copy the fix command.
struct WrapperWarningBanner: View {
    /// Distinct wrappers detected across current sessions.
    let wrappers: [TerminalWrapper]
    let onDismiss: () -> Void
    let onSuppress: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 12))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.system(size: 11, weight: .semibold))
                ForEach(wrappers, id: \.self) { wrapper in
                    HStack(spacing: 6) {
                        Text("Fix:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(wrapper.remediation)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                        Button("Copy") { copyToClipboard(wrapper.remediation) }
                            .font(.system(size: 10))
                            .buttonStyle(.borderless)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")

                Button("Don't show again", action: onSuppress)
                    .font(.system(size: 10))
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.orange.opacity(0.4)),
            alignment: .bottom
        )
    }

    private var headline: String {
        let names = wrappers.map { $0.displayName }.joined(separator: ", ")
        return "Some sessions run behind an autocomplete PTY wrapper (\(names)) — a known cause of frozen panes."
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
