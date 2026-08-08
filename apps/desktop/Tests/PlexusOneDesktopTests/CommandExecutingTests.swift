import XCTest
@testable import PlexusOneDesktop

final class CommandExecutingTests: XCTestCase {

    /// `ps -Ao pid=,command=` on a typical dev machine easily exceeds the ~64KB
    /// pipe buffer. Reading stdout only after waitUntilExit() deadlocks in that
    /// case: the child blocks on write() with nothing draining the pipe, so it
    /// never exits and the continuation never resumes.
    func testExecuteHandlesOutputLargerThanPipeBuffer() async throws {
        let executor = ProcessCommandExecutor()

        // Print well over 64KB to stdout, interleaved with some stderr output,
        // to exercise both pipes concurrently.
        let script = """
        for i in $(seq 1 20000); do echo "line $i of padding output to exceed the pipe buffer"; done
        echo "some stderr output" >&2
        """

        let result = try await withTimeout(seconds: 10) {
            try await executor.execute("/bin/sh", arguments: ["-c", script])
        }

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertGreaterThan(result.stdout.utf8.count, 64 * 1024)
        XCTAssertTrue(result.stdout.contains("line 20000 of padding"))
        XCTAssertTrue(result.stderr.contains("some stderr output"))
    }

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private struct TimeoutError: Error {}
}
