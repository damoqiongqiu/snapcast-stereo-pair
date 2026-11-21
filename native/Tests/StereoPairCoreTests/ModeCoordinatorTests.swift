import XCTest
@testable import StereoPairCore

private actor RecordingRunner: CommandRunning {
    struct Invocation: Equatable, Sendable {
        let executable: String
        let arguments: [String]
    }

    private(set) var invocations: [Invocation] = []
    var remoteStatus: Int32 = 1

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async throws -> CommandResult {
        invocations.append(Invocation(executable: executable, arguments: arguments))
        let status: Int32 = executable == "/usr/bin/ssh" ? remoteStatus : 0
        return CommandResult(status: status, stdout: "", stderr: status == 0 ? "" : "offline")
    }
}

final class ModeCoordinatorTests: XCTestCase {
    func testSystemModeSwitchesLocalAndReportsRemoteFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("state"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let remote = """
        {"user":"tester","host":"remote.local","helperPath":"/Users/tester/remote-mode.sh"}
        """
        try Data(remote.utf8).write(to: directory.appendingPathComponent("state/remote-control.json"))

        let runner = RecordingRunner()
        let coordinator = ModeCoordinator(runner: runner, supportDirectory: directory)
        let result = try await coordinator.setMode(.system)

        XCTAssertEqual(result.mode, .system)
        XCTAssertEqual(result.remoteWarning, "Remote mode change failed: SSH exit 1")
        let calls = await runner.invocations
        XCTAssertEqual(calls[0].executable, "/bin/zsh")
        XCTAssertEqual(calls[0].arguments, [directory.appendingPathComponent("set-mode.sh").path, "native"])
        XCTAssertEqual(calls[1].executable, "/usr/bin/ssh")
        XCTAssertTrue(calls[1].arguments.contains("tester@remote.local"))

        let marker = try JSONDecoder().decode(
            [String: String].self,
            from: Data(contentsOf: directory.appendingPathComponent("state/audio-mode.json"))
        )
        XCTAssertEqual(marker["mode"], "system")
    }
}
