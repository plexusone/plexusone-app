import Foundation

/// Reads Claude Code transcripts (`~/.claude/projects/<dir>/<session>.jsonl`)
/// with bounded reads of the start and end of each file, not a full parse.
enum ClaudeTranscriptReader {
    /// Bytes read from the start for the creation time, directory, and first prompt.
    static let headBytes = 256 << 10
    /// Bytes read from the end for last activity, title, and the shutdown record.
    static let tailBytes = 512 << 10
    /// Width that prompt and title text is truncated to.
    static let textWidth = 300
    /// First Claude Code version seen writing a `cost-state` record at
    /// shutdown. Earlier transcripts never have one, so a missing record
    /// says nothing about how they ended.
    static let firstVersionWithShutdownRecord = "2.1.286"

    /// Summarize the transcript at `url`, or nil if it holds no conversation.
    static func read(url: URL) throws -> TranscriptSummary? {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            do {
                try handle.close()
            } catch {
                // Read-only handle: a close failure loses nothing.
            }
        }
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        let head = try handle.read(upToCount: headBytes) ?? Data()

        var tail = Data()
        var tailIsPartial = false
        if size > UInt64(headBytes) {
            let offset = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : UInt64(headBytes)
            try handle.seek(toOffset: offset)
            tail = try handle.readToEnd() ?? Data()
            tailIsPartial = true
        }

        let sessionId = url.deletingPathExtension().lastPathComponent
        return summarize(
            sessionId: sessionId,
            path: url.path,
            head: head,
            tail: tail,
            tailStartsMidLine: tailIsPartial
        )
    }

    /// Pure parsing step, separated for testing.
    /// - Parameters:
    ///   - head: Bytes from the start of the file.
    ///   - tail: Bytes from the end of the file, or empty when `head` holds it all.
    ///   - tailStartsMidLine: Drop the tail's first line, which may be cut.
    static func summarize(
        sessionId: String,
        path: String,
        head: Data,
        tail: Data,
        tailStartsMidLine: Bool
    ) -> TranscriptSummary? {
        var summary = TranscriptSummary(sessionId: sessionId, path: path)

        let headRecords = records(in: head, dropFirstLine: false)
        let tailRecords = tail.isEmpty ? headRecords : records(in: tail, dropFirstLine: tailStartsMidLine)

        for record in headRecords {
            if summary.createdAt == nil, let date = record.date {
                summary.createdAt = date
            }
            if summary.cwd == nil, let cwd = record.cwd, !cwd.isEmpty {
                summary.cwd = cwd
            }
            if summary.firstPrompt == nil, let prompt = record.humanPrompt {
                summary.firstPrompt = truncate(prompt)
            }
            if summary.title == nil, let title = record.aiTitle {
                summary.title = truncate(title)
            }
            if let version = record.version {
                summary.version = version
            }
        }

        var lastConversationIndex = -1
        var touched: [String] = []
        for (index, record) in tailRecords.enumerated() {
            if let date = record.date {
                summary.lastActivityAt = date
            }
            if let cwd = record.cwd, !cwd.isEmpty {
                summary.cwd = cwd
            }
            if let branch = record.gitBranch, !branch.isEmpty {
                summary.gitBranch = branch
            }
            if let version = record.version {
                summary.version = version
            }
            if let title = record.aiTitle {
                summary.title = truncate(title)
            }
            if let prompt = record.lastPrompt {
                summary.lastPrompt = truncate(prompt)
            } else if let prompt = record.humanPrompt {
                summary.lastPrompt = truncate(prompt)
            }
            if record.isConversation {
                lastConversationIndex = index
            }
            touched.append(contentsOf: record.toolPaths)
            if record.type == "cost-state" {
                summary.costUSD = record.totalCostUSD ?? summary.costUSD
                summary.linesAdded = record.totalLinesAdded ?? summary.linesAdded
                summary.linesRemoved = record.totalLinesRemoved ?? summary.linesRemoved
            }
        }
        summary.touchedPaths = touched
        summary.hasShutdownRecord = tailRecords
            .dropFirst(lastConversationIndex + 1)
            .contains { $0.type == "cost-state" }

        guard summary.createdAt != nil || summary.lastActivityAt != nil else {
            return nil // no timestamps: not a real conversation
        }
        if summary.createdAt == nil {
            summary.createdAt = summary.lastActivityAt
        }
        return summary
    }

    /// Whether `version` writes a shutdown record, so its absence means something.
    static func writesShutdownRecord(version: String?) -> Bool {
        guard let version else { return false }
        return compareVersions(version, firstVersionWithShutdownRecord) >= 0
    }

    /// Compare dotted numeric versions; non-numeric parts count as 0.
    static func compareVersions(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    static func truncate(_ s: String) -> String {
        let flat = s.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if flat.count <= textWidth { return flat }
        return String(flat.prefix(textWidth)) + "…"
    }

    // MARK: - Records

    private static func records(in data: Data, dropFirstLine: Bool) -> [Record] {
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if dropFirstLine, !lines.isEmpty {
            lines.removeFirst()
        }
        let decoder = JSONDecoder()
        return lines.compactMap { line in
            // A line cut by the read window, or still being written, fails to
            // decode and is skipped.
            try? decoder.decode(Record.self, from: Data(line))
        }
    }

    /// The subset of a transcript line the reader uses.
    struct Record: Decodable {
        let type: String?
        let timestamp: String?
        let cwd: String?
        let gitBranch: String?
        let version: String?
        let isMeta: Bool?
        let isSidechain: Bool?
        let aiTitle: String?
        let lastPrompt: String?
        let totalCostUSD: Double?
        let totalLinesAdded: Int?
        let totalLinesRemoved: Int?
        let message: Message?

        struct Message: Decodable {
            let content: Content?
        }

        enum Content: Decodable {
            case text(String)
            case blocks([Block])

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let text = try? container.decode(String.self) {
                    self = .text(text)
                } else {
                    self = .blocks(try container.decode([Block].self))
                }
            }
        }

        struct Block: Decodable {
            let type: String?
            let text: String?
            let input: ToolInput?
        }

        struct ToolInput: Decodable {
            let file_path: String?
            let notebook_path: String?
            let path: String?
        }

        private static let isoFractional: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        private static let iso = ISO8601DateFormatter()

        var date: Date? {
            guard let timestamp else { return nil }
            return Self.isoFractional.date(from: timestamp) ?? Self.iso.date(from: timestamp)
        }

        /// A user, assistant, or system record: the conversation itself, as
        /// opposed to bookkeeping such as titles and cost totals.
        var isConversation: Bool {
            type == "user" || type == "assistant" || type == "system"
        }

        /// Text a person typed. Tool results, injected context, slash-command
        /// wrappers, and subagent traffic are recorded as user messages too,
        /// and are excluded.
        var humanPrompt: String? {
            guard type == "user", isMeta != true, isSidechain != true, let content = message?.content else {
                return nil
            }
            let text: String
            switch content {
            case .text(let s):
                text = s
            case .blocks(let blocks):
                if blocks.contains(where: { $0.type == "tool_result" }) { return nil }
                text = blocks.compactMap { $0.type == "text" ? $0.text : nil }.joined(separator: " ")
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("<") else { return nil }
            return trimmed
        }

        /// Absolute paths passed to file tools (Read, Edit, Write, Grep, ...).
        var toolPaths: [String] {
            guard type == "assistant", case .blocks(let blocks)? = message?.content else { return [] }
            return blocks.compactMap { block in
                guard block.type == "tool_use", let input = block.input else { return nil }
                let path = input.file_path ?? input.notebook_path ?? input.path
                guard let path, path.hasPrefix("/") else { return nil }
                return path
            }
        }
    }
}
