import AppKit
import SwiftUI

/// Lists Claude Code sessions with their tmux session, repositories, subject,
/// last activity, and how they ended, and re-establishes the ones you pick.
struct ClaudeSessionsView: View {
    static let windowId = "claude-sessions"

    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    @State private var timeWindow: TimeWindow = .week
    @State private var endingFilter: EndingFilter = .all
    @State private var searchText = ""
    @State private var selection = Set<String>()
    @State private var isRestoring = false
    @State private var restoreMessage: String?
    /// Sessions waiting for the user to confirm tmux names
    @State private var pendingRestore: [ClaudeSessionInfo] = []

    private var catalog: ClaudeSessionCatalog { appState.claudeSessions }

    private var filtered: [ClaudeSessionInfo] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return catalog.sessions.filter { info in
            guard endingFilter.includes(info) else { return false }
            guard !query.isEmpty else { return true }
            let haystack = [
                info.subject, info.lastPrompt ?? "", info.tmux?.sessionName ?? "", info.claudeName ?? "",
                info.cwd ?? "", info.sessionId, info.gitBranch ?? "",
            ] + info.repos.map(\.displayName)
            return haystack.contains { $0.lowercased().contains(query) }
        }
    }

    private var selected: [ClaudeSessionInfo] {
        catalog.sessions.filter { selection.contains($0.id) }
    }

    /// Sessions that ended abnormally in the last two days: the ones to
    /// recover after a crash.
    private var recentAbnormal: [ClaudeSessionInfo] {
        let cutoff = Date().addingTimeInterval(-48 * 3600)
        return catalog.sessions.filter {
            $0.endState.isNormalEnding == false && ($0.lastActivityAt ?? .distantPast) > cutoff
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            if !recentAbnormal.isEmpty {
                recoveryBanner
                Divider()
            }
            VSplitView {
                sessionTable
                    .frame(minHeight: 180)
                detailPane
                    .frame(minHeight: 160, idealHeight: 240)
            }
        }
        .task(id: timeWindow) {
            // Refresh while the window is open; .task stops when it closes.
            while !Task.isCancelled {
                await catalog.reload(window: timeWindow.interval)
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .sheet(isPresented: Binding(
            get: { !pendingRestore.isEmpty },
            set: { if !$0 { pendingRestore = [] } }
        )) {
            RestoreNamesSheet(
                infos: pendingRestore,
                existingTmuxNames: Set(appState.sessionManager.sessions.map(\.tmuxSession)),
                onCancel: { pendingRestore = [] },
                onRestore: { names in
                    let infos = pendingRestore
                    pendingRestore = []
                    performRestore(infos, names: names)
                }
            )
        }
        .alert("Restore Sessions", isPresented: Binding(
            get: { restoreMessage != nil },
            set: { if !$0 { restoreMessage = nil } }
        )) {
            Button("OK") { restoreMessage = nil }
        } message: {
            Text(restoreMessage ?? "")
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("Active within", selection: $timeWindow) {
                ForEach(TimeWindow.allCases) { Text($0.label).tag($0) }
            }
            .frame(width: 190)

            Picker("Show", selection: $endingFilter) {
                ForEach(EndingFilter.allCases) { Text($0.label).tag($0) }
            }
            .frame(width: 210)

            TextField("Search subject, repo, tmux, ID", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if catalog.isLoading {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await catalog.reload(window: timeWindow.interval) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
        }
        .padding(8)
    }

    private var recoveryBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("\(recentAbnormal.count) session(s) ended abnormally in the last 48 hours.")
                .font(.callout)
            Spacer()
            Button("Select Them") {
                selection = Set(recentAbnormal.map(\.id))
                endingFilter = .all
            }
            Button("Restore All") {
                restore(recentAbnormal)
            }
            .disabled(isRestoring)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: - Table

    private var sessionTable: some View {
        Table(filtered, selection: $selection) {
            TableColumn("State") { info in
                EndStateBadge(state: info.endState, liveStatus: info.liveStatusText)
            }
            .width(min: 130, ideal: 190)

            TableColumn("tmux") { info in
                Text(info.tmux?.sessionName ?? "—")
                    .foregroundColor(info.tmux == nil ? .secondary : .primary)
            }
            .width(min: 70, ideal: 110)

            TableColumn("Claude Name") { info in
                Text(info.claudeName ?? "—")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(info.claudeName == nil ? .secondary : .primary)
                    .lineLimit(1)
            }
            .width(min: 90, ideal: 150)

            TableColumn("Subject") { info in
                Text(info.subject)
                    .lineLimit(1)
                    .help(info.lastPrompt.map { "Last prompt: \($0)" } ?? info.subject)
            }
            .width(min: 180, ideal: 320)

            TableColumn("Repository") { info in
                Text(info.repos.first?.displayName ?? info.cwd ?? "—")
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(info.repos.map(\.displayName).joined(separator: "\n"))
            }
            .width(min: 120, ideal: 220)

            TableColumn("Last Active") { info in
                Text(info.lastActivityAt?.timeAgoString() ?? "—")
                    .help(info.lastActivityAt.map(Self.absolute) ?? "")
            }
            .width(min: 70, ideal: 90)

            TableColumn("Session") { info in
                Text(info.shortId)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(min: 70, ideal: 80)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            let infos = catalog.sessions.filter { ids.contains($0.id) }
            Button(restoreLabel(for: infos)) { restore(infos) }
                .disabled(infos.isEmpty || isRestoring)
            if infos.count == 1, let info = infos.first {
                Divider()
                Button("Copy Session ID") { copy(info.sessionId) }
                Button("Copy Resume Command") { copy(info.resumeCommand) }
            }
        } primaryAction: { ids in
            // Double-click
            restore(catalog.sessions.filter { ids.contains($0.id) })
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        if selected.count == 1, let info = selected.first {
            SessionDetailView(
                info: info,
                isRestoring: isRestoring,
                onRestore: { restore([info]) },
                onCopy: copy
            )
        } else if selected.count > 1 {
            VStack(spacing: 12) {
                Text("\(selected.count) sessions selected")
                    .font(.headline)
                Button(restoreLabel(for: selected)) { restore(selected) }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRestoring)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text(catalog.lastError ?? "Select a session to see its details. Double-click to resume it.")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Actions

    private func restoreLabel(for infos: [ClaudeSessionInfo]) -> String {
        if infos.count == 1, infos.first?.endState == .running {
            return "Attach in New Window"
        }
        return infos.count > 1 ? "Restore \(infos.count) Sessions in New Window" : "Resume in New Window"
    }

    /// Ask for tmux names, unless every session is running and just attaches.
    private func restore(_ infos: [ClaudeSessionInfo]) {
        guard !infos.isEmpty, !isRestoring else { return }
        if infos.allSatisfy({ $0.endState == .running }) {
            performRestore(infos, names: [:])
        } else {
            pendingRestore = Array(infos.prefix(9))
        }
    }

    /// Re-establish each session in tmux, then open one window with a pane per session.
    /// - Parameter names: tmux name chosen per session ID.
    private func performRestore(_ infos: [ClaudeSessionInfo], names chosen: [String: String]) {
        guard !infos.isEmpty, !isRestoring else { return }
        isRestoring = true
        Task {
            defer { isRestoring = false }
            let restorer = ClaudeSessionRestorer()
            var names: [String] = []
            var failures: [String] = []
            for info in infos.prefix(9) {
                do {
                    let name = try await restorer.restore(info, tmuxName: chosen[info.id])
                    if !names.contains(name) { names.append(name) }
                } catch {
                    failures.append("\(info.shortId): \(error.localizedDescription)")
                }
            }
            if infos.count > 9 {
                failures.append("Only the first 9 sessions were restored; a window holds at most 9 panes.")
            }

            await appState.sessionManager.refresh()
            let sessions = names.compactMap { name in
                appState.sessionManager.sessions.first { $0.tmuxSession == name }
            }
            if !sessions.isEmpty {
                appState.pendingRestoreSessions = sessions
                openWindow(id: "main")
            }
            await catalog.observeOnce()
            await catalog.reload(window: timeWindow.interval)

            if !failures.isEmpty {
                restoreMessage = failures.joined(separator: "\n")
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func absolute(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Restore names

/// Lets the user name the tmux session for each session being resumed.
private struct RestoreNamesSheet: View {
    let infos: [ClaudeSessionInfo]
    let existingTmuxNames: Set<String>
    let onCancel: () -> Void
    let onRestore: ([String: String]) -> Void

    @State private var names: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(infos.count == 1 ? "Resume Session" : "Resume \(infos.count) Sessions")
                .font(.headline)
                .padding()
            Text("Choose the tmux session each one runs in. A name that already exists gets a new window in that session.")
                .font(.callout)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)
            Divider()

            ScrollView {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                    ForEach(infos) { info in
                        GridRow {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(info.subject).lineLimit(1)
                                Text("\(info.shortId) · \(info.repos.first?.displayName ?? info.cwd ?? "")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 300, alignment: .leading)

                            if info.endState == .running {
                                Text(info.tmux?.sessionName ?? "—")
                                    .foregroundColor(.secondary)
                                    .frame(width: 200, alignment: .leading)
                                Text("Running: attaches")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                TextField("tmux session", text: binding(for: info))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 200)
                                Text(note(for: info))
                                    .font(.caption)
                                    .foregroundColor(isDuplicate(info) ? .orange : .secondary)
                            }
                        }
                    }
                }
                .padding()
            }
            .frame(maxHeight: 360)

            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(infos.count == 1 ? "Resume" : "Resume All") {
                    onRestore(resolvedNames())
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(hasEmptyName)
            }
            .padding()
        }
        .frame(width: 700)
        .onAppear {
            for info in infos where names[info.id] == nil {
                names[info.id] = ClaudeSessionRestorer.tmuxName(for: info)
            }
        }
    }

    private func binding(for info: ClaudeSessionInfo) -> Binding<String> {
        Binding(
            get: { names[info.id] ?? "" },
            set: { names[info.id] = $0 }
        )
    }

    private func name(for info: ClaudeSessionInfo) -> String {
        ClaudeSessionRestorer.sanitizeName(names[info.id] ?? "")
    }

    private var hasEmptyName: Bool {
        infos.contains { $0.endState != .running && name(for: $0).isEmpty }
    }

    private func isDuplicate(_ info: ClaudeSessionInfo) -> Bool {
        let n = name(for: info)
        return infos.filter { $0.endState != .running && name(for: $0) == n }.count > 1
    }

    private func note(for info: ClaudeSessionInfo) -> String {
        let n = name(for: info)
        if n.isEmpty { return "Enter a name" }
        if isDuplicate(info) { return "Shared: each gets its own window" }
        if existingTmuxNames.contains(n) { return "Exists: adds a window" }
        if n != (names[info.id] ?? "") { return "Will be \"\(n)\"" }
        return "New tmux session"
    }

    private func resolvedNames() -> [String: String] {
        var result: [String: String] = [:]
        for info in infos where info.endState != .running {
            result[info.id] = name(for: info)
        }
        return result
    }
}

// MARK: - Filters

enum TimeWindow: String, CaseIterable, Identifiable {
    case day, week, month, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: return "Last 24 hours"
        case .week: return "Last 7 days"
        case .month: return "Last 30 days"
        case .all: return "All time"
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .day: return 24 * 3600
        case .week: return 7 * 24 * 3600
        case .month: return 30 * 24 * 3600
        case .all: return nil
        }
    }
}

enum EndingFilter: String, CaseIterable, Identifiable {
    case all, running, abnormal, inTmux

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All sessions"
        case .running: return "Running"
        case .abnormal: return "Ended abnormally"
        case .inTmux: return "With a tmux session"
        }
    }

    func includes(_ info: ClaudeSessionInfo) -> Bool {
        switch self {
        case .all: return true
        case .running: return info.endState == .running
        case .abnormal: return info.endState.isNormalEnding == false
        case .inTmux: return info.tmux != nil
        }
    }
}

// MARK: - Subviews

struct EndStateBadge: View {
    let state: SessionEndState
    /// Live status of a running session, e.g. "waiting: permission prompt".
    var liveStatus: String? = nil

    private var isWaiting: Bool {
        state == .running && (liveStatus?.hasPrefix("waiting") ?? false)
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(state.displayName)
                .lineLimit(1)
            if state == .running, let liveStatus {
                Text(liveStatus)
                    .foregroundColor(isWaiting ? .orange : .secondary)
                    .fontWeight(isWaiting ? .semibold : .regular)
                    .lineLimit(1)
            }
        }
        .help(state.explanation)
    }

    private var color: Color {
        if isWaiting { return .orange }
        switch state {
        case .running: return .green
        case .exited, .endedCleanly: return .gray
        case .tmuxClosed: return .orange
        case .systemShutdown, .crashed, .endedAbnormally: return .red
        case .unknown: return Color(nsColor: .tertiaryLabelColor)
        }
    }
}

private struct SessionDetailView: View {
    let info: ClaudeSessionInfo
    let isRestoring: Bool
    let onRestore: () -> Void
    let onCopy: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(info.subject)
                        .font(.headline)
                        .textSelection(.enabled)
                    Spacer()
                    Button(info.endState == .running ? "Attach in New Window" : "Resume in New Window", action: onRestore)
                        .buttonStyle(.borderedProminent)
                        .disabled(isRestoring || (info.endState == .running && info.tmux == nil))
                }

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                    row("State") {
                        VStack(alignment: .leading, spacing: 2) {
                            EndStateBadge(state: info.endState, liveStatus: info.liveStatusText)
                            Text(info.endState.explanation)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    row("Session ID") {
                        HStack {
                            Text(info.sessionId).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                            Button("Copy") { onCopy(info.sessionId) }.controlSize(.small)
                        }
                    }
                    row("Claude name") {
                        Text(info.claudeName ?? "—")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    row("tmux") {
                        Text(info.tmux.map { "\($0.sessionName)  (window \($0.windowId), pane \($0.paneId))" } ?? "Not seen in tmux")
                            .textSelection(.enabled)
                    }
                    row("Directory") { Text(info.cwd ?? "—").textSelection(.enabled) }
                    if let branch = info.gitBranch {
                        row("Branch") { Text(branch).textSelection(.enabled) }
                    }
                    row("Repositories") {
                        VStack(alignment: .leading, spacing: 2) {
                            if info.repos.isEmpty { Text("—") }
                            ForEach(info.repos) { repo in
                                Text(repo.remoteId.map { "\($0)  —  \(repo.path)" } ?? repo.path)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    if let first = info.firstPrompt {
                        row("First prompt") { Text(first).textSelection(.enabled) }
                    }
                    if let last = info.lastPrompt, last != info.firstPrompt {
                        row("Last prompt") { Text(last).textSelection(.enabled) }
                    }
                    row("Started") { Text(info.createdAt.map(ClaudeSessionsView.absolute) ?? "—") }
                    row("Last active") {
                        Text(info.lastActivityAt.map { "\(ClaudeSessionsView.absolute($0))  (\($0.timeAgoString()))" } ?? "—")
                    }
                    if let ended = info.endedAt {
                        row("Ended") { Text(ClaudeSessionsView.absolute(ended)) }
                    }
                    row("Resume command") {
                        HStack {
                            Text(info.resumeCommand)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            Button("Copy") { onCopy(info.resumeCommand) }.controlSize(.small)
                        }
                    }
                    if let version = info.version {
                        row("Claude Code") { Text(version).foregroundColor(.secondary) }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(label)
                .foregroundColor(.secondary)
                .gridColumnAlignment(.trailing)
            content()
        }
    }
}
