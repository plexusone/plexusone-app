import Foundation
@testable import PlexusOneDesktop

/// In-memory mock implementation of FileSystemAccessing for testing
final class MockFileSystem: FileSystemAccessing, @unchecked Sendable {
    /// In-memory file storage
    private var files: [String: Data] = [:]

    /// Track which directories have been "created"
    private var directories: Set<String> = []

    /// Track removed files/directories
    private(set) var removedItems: [URL] = []

    /// Track created directories
    private(set) var createdDirectories: [URL] = []

    /// Error to throw on next operation (if set)
    var errorToThrow: Error?

    /// Mock home directory
    var mockHomeDirectory: URL = URL(fileURLWithPath: "/tmp/mock-home")

    // MARK: - FileSystemAccessing

    var homeDirectoryForCurrentUser: URL {
        mockHomeDirectory
    }

    func fileExists(atPath path: String) -> Bool {
        files[path] != nil || directories.contains(path)
    }

    func contents(at url: URL) throws -> Data {
        if let error = errorToThrow {
            throw error
        }
        guard let data = files[url.path] else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        }
        return data
    }

    func write(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        if let error = errorToThrow {
            throw error
        }
        files[url.path] = data
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        if let error = errorToThrow {
            throw error
        }
        directories.insert(url.path)
        createdDirectories.append(url)
    }

    func removeItem(at url: URL) throws {
        if let error = errorToThrow {
            throw error
        }
        files.removeValue(forKey: url.path)
        directories.remove(url.path)
        removedItems.append(url)
    }

    // MARK: - Test Helpers

    /// Set file content for a given path
    func setFile(at path: String, content: Data) {
        files[path] = content
    }

    /// Set file content with a string
    func setFile(at path: String, content: String) {
        files[path] = content.data(using: .utf8)
    }

    /// Set file content at a URL
    func setFile(at url: URL, content: Data) {
        files[url.path] = content
    }

    /// Get file content at a path
    func getFile(at path: String) -> Data? {
        files[path]
    }

    /// Get file content at a URL
    func getFile(at url: URL) -> Data? {
        files[url.path]
    }

    /// Reset all state
    func reset() {
        files = [:]
        directories = []
        removedItems = []
        createdDirectories = []
        errorToThrow = nil
    }

    /// Check if directory was created
    func wasDirectoryCreated(at url: URL) -> Bool {
        createdDirectories.contains(url)
    }

    /// Check if item was removed
    func wasRemoved(at url: URL) -> Bool {
        removedItems.contains(url)
    }
}

// MARK: - Test Data Builders

extension MockFileSystem {
    /// Create valid v2 multi-window state JSON
    static func makeV2StateJSON(configs: [WindowConfig] = []) -> Data {
        let state = MultiWindowState(windows: configs)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(state)) ?? Data()
    }

    /// Create valid v1 legacy state JSON
    static func makeV1StateJSON(
        gridColumns: Int = 2,
        gridRows: Int = 1,
        paneAttachments: [String: String] = [:]
    ) -> Data {
        let json = """
        {
            "gridColumns": \(gridColumns),
            "gridRows": \(gridRows),
            "paneAttachments": \(paneAttachmentsJSON(paneAttachments)),
            "savedAt": "2024-01-01T00:00:00Z",
            "version": 1
        }
        """
        return json.data(using: .utf8) ?? Data()
    }

    private static func paneAttachmentsJSON(_ attachments: [String: String]) -> String {
        if attachments.isEmpty {
            return "{}"
        }
        let pairs = attachments.map { "\"\($0.key)\": \"\($0.value)\"" }
        return "{\(pairs.joined(separator: ", "))}"
    }
}
