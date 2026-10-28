import Foundation

/// Protocol for executing shell commands, enabling dependency injection for testing
protocol CommandExecuting: Sendable {
    func execute(_ path: String, arguments: [String]) async throws -> CommandResult
}

/// Default implementation using Process
struct ProcessCommandExecutor: CommandExecuting {
    func execute(_ path: String, arguments: [String]) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            // Run on a dispatch queue: the waits below block a thread, and
            // blocking Swift's shared async thread pool can stall other tasks.
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try Self.run(path, arguments: arguments) })
            }
        }
    }

    private static func run(_ path: String, arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw SessionManagerError.commandFailed(error.localizedDescription)
        }

        // Drain both pipes concurrently with the process running. Reading
        // only after waitUntilExit() deadlocks once combined output
        // exceeds the pipe buffer (~64KB): the child blocks on write()
        // with nothing reading, so it never exits.
        var stdoutData = Data()
        var stderrData = Data()
        let readGroup = DispatchGroup()

        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }
        readGroup.wait()
        process.waitUntilExit()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
