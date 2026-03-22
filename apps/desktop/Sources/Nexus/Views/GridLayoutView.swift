import SwiftUI

/// Grid layout configuration
struct GridConfig: Equatable {
    var columns: Int
    var rows: Int

    var paneCount: Int { columns * rows }

    static let presets: [(name: String, config: GridConfig)] = [
        ("1×1", GridConfig(columns: 1, rows: 1)),
        ("2×1", GridConfig(columns: 2, rows: 1)),
        ("3×1", GridConfig(columns: 3, rows: 1)),
        ("2×2", GridConfig(columns: 2, rows: 2)),
        ("3×2", GridConfig(columns: 3, rows: 2)),
        ("4×2", GridConfig(columns: 4, rows: 2)),
        ("3×3", GridConfig(columns: 3, rows: 3)),
    ]
}

/// Manages the state of multiple panes
@Observable
class PaneManager {
    var attachedSessions: [Int: NexusSession] = [:]

    func session(for paneId: Int) -> NexusSession? {
        attachedSessions[paneId]
    }

    func attach(session: NexusSession, to paneId: Int) {
        attachedSessions[paneId] = session
    }

    func detach(paneId: Int) {
        attachedSessions.removeValue(forKey: paneId)
    }

    func binding(for paneId: Int) -> Binding<NexusSession?> {
        Binding(
            get: { self.attachedSessions[paneId] },
            set: { newValue in
                if let session = newValue {
                    self.attachedSessions[paneId] = session
                } else {
                    self.attachedSessions.removeValue(forKey: paneId)
                }
            }
        )
    }
}

/// Grid layout view that displays multiple panes
struct GridLayoutView: View {
    let config: GridConfig
    let sessions: [NexusSession]
    let sessionManager: SessionManager
    @Bindable var paneManager: PaneManager
    let onRequestNewSession: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let paneWidth = geometry.size.width / CGFloat(config.columns)
            let paneHeight = geometry.size.height / CGFloat(config.rows)

            VStack(spacing: 2) {
                ForEach(0..<config.rows, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<config.columns, id: \.self) { col in
                            let paneId = row * config.columns + col + 1

                            PaneView(
                                paneId: paneId,
                                sessions: sessions,
                                sessionManager: sessionManager,
                                attachedSession: paneManager.binding(for: paneId),
                                onRequestNewSession: onRequestNewSession
                            )
                            .frame(width: paneWidth - 2, height: paneHeight - 2)
                        }
                    }
                }
            }
        }
    }
}

/// Toolbar view for selecting grid layout
struct LayoutPickerView: View {
    @Binding var config: GridConfig

    var body: some View {
        Menu {
            ForEach(GridConfig.presets, id: \.name) { preset in
                Button(action: { config = preset.config }) {
                    HStack {
                        Text(preset.name)
                        if config == preset.config {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            // Custom size submenu
            Menu("Custom...") {
                ForEach(1...4, id: \.self) { cols in
                    Menu("\(cols) columns") {
                        ForEach(1...4, id: \.self) { rows in
                            Button("\(cols)×\(rows)") {
                                config = GridConfig(columns: cols, rows: rows)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.grid.2x2")
                Text("\(config.columns)×\(config.rows)")
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
    }
}

#Preview {
    GridLayoutView(
        config: GridConfig(columns: 2, rows: 2),
        sessions: [
            NexusSession(name: "coder-1", status: .running),
            NexusSession(name: "coder-2", status: .idle),
            NexusSession(name: "reviewer", status: .stuck)
        ],
        sessionManager: SessionManager(),
        paneManager: PaneManager(),
        onRequestNewSession: {}
    )
    .frame(width: 800, height: 600)
}
