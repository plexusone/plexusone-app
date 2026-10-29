import Foundation

/// Maps a path to the git repository holding it and that repository's remote
/// ID, reading `.git` directly instead of running git. Results are cached.
final class GitRepoResolver {
    private var rootCache: [String: String?] = [:]
    private var remoteCache: [String: String?] = [:]
    private let fileManager = FileManager.default

    /// The repository holding `path`, or nil if it is not in one.
    func repo(containing path: String) -> RepoRef? {
        guard let root = root(containing: path) else { return nil }
        return RepoRef(path: root, remoteId: remoteId(forRoot: root))
    }

    /// Distinct repositories for `paths`, most-used first: ranked by how
    /// many of the paths fall in each, ties in first-seen order.
    func repos(for paths: [String]) -> [RepoRef] {
        var order: [RepoRef] = []
        var counts: [String: Int] = [:]
        for path in paths {
            guard let repo = repo(containing: path) else { continue }
            if counts[repo.path] == nil { order.append(repo) }
            counts[repo.path, default: 0] += 1
        }
        return order.enumerated()
            .sorted { a, b in
                let (ca, cb) = (counts[a.element.path] ?? 0, counts[b.element.path] ?? 0)
                return ca != cb ? ca > cb : a.offset < b.offset
            }
            .map(\.element)
    }

    private func root(containing path: String) -> String? {
        var dir = URL(fileURLWithPath: path).standardizedFileURL
        // Start from the directory itself when `path` is a directory.
        var isDir: ObjCBool = false
        if !(fileManager.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue) {
            dir = dir.deletingLastPathComponent()
        }

        var visited: [String] = []
        while dir.path != "/" && !dir.path.isEmpty {
            if let cached = rootCache[dir.path] {
                for v in visited { rootCache[v] = cached }
                return cached
            }
            visited.append(dir.path)
            if fileManager.fileExists(atPath: dir.appendingPathComponent(".git").path) {
                for v in visited { rootCache[v] = dir.path }
                return dir.path
            }
            dir = dir.deletingLastPathComponent()
        }
        for v in visited { rootCache[v] = .some(nil) }
        return nil
    }

    private func remoteId(forRoot root: String) -> String? {
        if let cached = remoteCache[root] { return cached }
        let id = Self.configURL(forRoot: root)
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            .flatMap(Self.originURL(inConfig:))
            .flatMap(Self.normalizeRemote)
        remoteCache[root] = id
        return id
    }

    /// The git config file for a repository root, following a `.git` file
    /// (linked worktree or submodule) and a worktree's `commondir`.
    static func configURL(forRoot root: String) -> URL? {
        let dotGit = URL(fileURLWithPath: root).appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDir) else { return nil }

        var gitDir = dotGit
        if !isDir.boolValue {
            guard let text = try? String(contentsOf: dotGit, encoding: .utf8),
                  let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) else {
                return nil
            }
            let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            gitDir = URL(fileURLWithPath: target, relativeTo: URL(fileURLWithPath: root, isDirectory: true))
                .standardizedFileURL
        }

        let commonDirFile = gitDir.appendingPathComponent("commondir")
        if let common = try? String(contentsOf: commonDirFile, encoding: .utf8) {
            let trimmed = common.trimmingCharacters(in: .whitespacesAndNewlines)
            gitDir = URL(fileURLWithPath: trimmed, relativeTo: URL(fileURLWithPath: gitDir.path, isDirectory: true))
                .standardizedFileURL
        }
        return gitDir.appendingPathComponent("config")
    }

    /// The `url` of `[remote "origin"]` in a git config file.
    static func originURL(inConfig config: String) -> String? {
        var inOrigin = false
        for raw in config.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inOrigin = line.replacingOccurrences(of: " ", with: "") == "[remote\"origin\"]"
                continue
            }
            guard inOrigin, line.hasPrefix("url") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "url" else { continue }
            return parts[1].trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Normalize https, ssh, and scp-style remotes to `host/owner/repo`.
    static func normalizeRemote(_ url: String) -> String? {
        var s = url.trimmingCharacters(in: .whitespaces)
        if let scheme = s.range(of: "://") {
            s = String(s[scheme.upperBound...])
            if let at = s.firstIndex(of: "@"), at < (s.firstIndex(of: "/") ?? s.endIndex) {
                s = String(s[s.index(after: at)...])
            }
            // Drop a port, e.g. host:22/owner/repo
            if let colon = s.firstIndex(of: ":"), let slash = s.firstIndex(of: "/"), colon < slash {
                s = String(s[..<colon]) + String(s[slash...])
            }
        } else if let colon = s.firstIndex(of: ":") {
            // scp-style: git@host:owner/repo
            var host = String(s[..<colon])
            if let at = host.firstIndex(of: "@") {
                host = String(host[host.index(after: at)...])
            }
            s = host + "/" + s[s.index(after: colon)...]
        } else {
            return nil
        }
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix(".git") { s.removeLast(4) }
        while s.hasSuffix("/") { s.removeLast() }
        return s.isEmpty ? nil : s
    }
}
