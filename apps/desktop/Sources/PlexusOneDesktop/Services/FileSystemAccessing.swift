import Foundation

/// Protocol for file system operations, enabling dependency injection for testing
protocol FileSystemAccessing: Sendable {
    func fileExists(atPath path: String) -> Bool
    func contents(at url: URL) throws -> Data
    func write(_ data: Data, to url: URL, options: Data.WritingOptions) throws
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws
    func removeItem(at url: URL) throws
    var homeDirectoryForCurrentUser: URL { get }
}

/// Default implementation wrapping FileManager
struct DefaultFileSystemAccessing: FileSystemAccessing {
    private var fileManager: FileManager { .default }

    func fileExists(atPath path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    func contents(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func write(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        try data.write(to: url, options: options)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
    }

    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    var homeDirectoryForCurrentUser: URL {
        fileManager.homeDirectoryForCurrentUser
    }
}
