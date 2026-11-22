import Darwin
import XCTest
@testable import StereoPairCore

final class CommandRunnerTests: XCTestCase {
    func testRepeatedCommandsReleaseTheirFileDescriptors() async throws {
        let runner = SystemCommandRunner()
        for _ in 0..<10 {
            _ = try await runner.run(
                executable: "/bin/echo",
                arguments: ["warmup"],
                environment: [:],
                timeout: 1
            )
        }
        let before = openFileDescriptorCount()

        for index in 0..<100 {
            let result = try await runner.run(
                executable: "/bin/echo",
                arguments: ["command-\(index)"],
                environment: [:],
                timeout: 1
            )
            XCTAssertEqual(result.status, 0)
            XCTAssertEqual(result.stdout, "command-\(index)\n")
        }

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertLessThanOrEqual(openFileDescriptorCount(), before + 2)
    }

    private func openFileDescriptorCount() -> Int {
        (0..<4096).reduce(into: 0) { count, descriptor in
            if fcntl(Int32(descriptor), F_GETFD) != -1 {
                count += 1
            }
        }
    }
}
