import Foundation
import XCTest
@testable import StereoPairCore

final class HardwareVolumeMonitorTests: XCTestCase {
    func testMapsLocalAndRemoteVolumesToPhysicalSides() async throws {
        let directory = try makeConfiguration(leftIsRemote: true)
        let runner = HardwareVolumeFakeRunner(localOutput: "87.50\n", remoteOutput: "42.00\n")
        let monitor = HardwareVolumeMonitor(
            supportDirectory: directory,
            runner: runner
        )

        let statuses = await monitor.refresh()

        XCTAssertEqual(statuses.first(where: { $0.side == "left" })?.volumePercent, 42)
        XCTAssertEqual(statuses.first(where: { $0.side == "right" })?.volumePercent, 87.5)
        XCTAssertNil(statuses.first?.error)
    }

    func testMappingFollowsConfiguredPhysicalPlacement() async throws {
        let directory = try makeConfiguration(leftIsRemote: false)
        let monitor = HardwareVolumeMonitor(
            supportDirectory: directory,
            runner: HardwareVolumeFakeRunner(localOutput: "87.50\n", remoteOutput: "42.00\n")
        )

        let statuses = await monitor.refresh()

        XCTAssertEqual(statuses.first(where: { $0.side == "left" })?.volumePercent, 87.5)
        XCTAssertEqual(statuses.first(where: { $0.side == "right" })?.volumePercent, 42)
    }

    func testRemoteFailureDoesNotHideLocalMeasurement() async throws {
        let directory = try makeConfiguration(leftIsRemote: true)
        let monitor = HardwareVolumeMonitor(
            supportDirectory: directory,
            runner: HardwareVolumeFakeRunner(
                localOutput: "87.50\n",
                remoteOutput: nil
            )
        )

        let statuses = await monitor.refresh()

        XCTAssertNil(statuses.first(where: { $0.side == "left" })?.volumePercent)
        XCTAssertNotNil(statuses.first(where: { $0.side == "left" })?.error)
        XCTAssertEqual(statuses.first(where: { $0.side == "right" })?.volumePercent, 87.5)
    }

    func testMeasurementsSurviveAgentRestartThroughCache() async throws {
        let directory = try makeConfiguration(leftIsRemote: true)
        let first = HardwareVolumeMonitor(
            supportDirectory: directory,
            runner: HardwareVolumeFakeRunner(localOutput: "99.00\n", remoteOutput: "98.00\n")
        )
        _ = await first.refresh()

        let second = HardwareVolumeMonitor(
            supportDirectory: directory,
            runner: HardwareVolumeFakeRunner(localOutput: nil, remoteOutput: nil)
        )
        let cached = await second.cached()

        XCTAssertEqual(cached.first(where: { $0.side == "left" })?.volumePercent, 98)
        XCTAssertEqual(cached.first(where: { $0.side == "right" })?.volumePercent, 99)
    }

    func testFailedRemoteRefreshKeepsLastMeasurementForStaleDisplay() async throws {
        let directory = try makeConfiguration(leftIsRemote: true)
        let first = HardwareVolumeMonitor(
            supportDirectory: directory,
            runner: HardwareVolumeFakeRunner(localOutput: "99.00\n", remoteOutput: "98.00\n")
        )
        _ = await first.refresh()

        let second = HardwareVolumeMonitor(
            supportDirectory: directory,
            runner: HardwareVolumeFakeRunner(localOutput: "99.00\n", remoteOutput: nil)
        )
        let statuses = await second.refresh()
        let remote = statuses.first { $0.side == "left" }

        XCTAssertEqual(remote?.volumePercent, 98)
        XCTAssertNotNil(remote?.checkedAt)
        XCTAssertNotNil(remote?.error)
    }

    func testLocalOnlyRefreshDoesNotContactRemote() async throws {
        let directory = try makeConfiguration(leftIsRemote: true)
        let counter = HardwareVolumeCommandCounter()
        let monitor = HardwareVolumeMonitor(
            supportDirectory: directory,
            runner: HardwareVolumeCountingRunner(counter: counter)
        )

        _ = await monitor.refresh(includeRemote: false)

        let sshRequests = await counter.sshRequests()
        XCTAssertEqual(sshRequests, 0)
    }

    private func makeConfiguration(leftIsRemote: Bool) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("state"),
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let devices = """
        {
          "schemaVersion": 1,
          "localOutputUID": "LocalSpeaker",
          "remoteOutputUID": "RemoteSpeaker",
          "leftIsRemote": \(leftIsRemote)
        }
        """
        let remote = """
        {
          "user": "tester",
          "host": "remote.test",
          "helperPath": "/Users/tester/.snapcast-remote-mode",
          "volumeReaderPath": "/Users/tester/.snapcast-volume"
        }
        """
        try Data(devices.utf8).write(to: directory.appendingPathComponent("state/audio-devices.json"))
        try Data(remote.utf8).write(to: directory.appendingPathComponent("state/remote-control.json"))
        return directory
    }
}

private struct HardwareVolumeFakeRunner: CommandRunning {
    let localOutput: String?
    let remoteOutput: String?

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async throws -> CommandResult {
        if executable == "/usr/bin/ssh" {
            guard let remoteOutput else { throw CommandRunnerError.timedOut }
            return CommandResult(status: 0, stdout: remoteOutput, stderr: "")
        }
        guard let localOutput else { throw CommandRunnerError.timedOut }
        return CommandResult(status: 0, stdout: localOutput, stderr: "")
    }
}

private struct HardwareVolumeCountingRunner: CommandRunning {
    let counter: HardwareVolumeCommandCounter

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async throws -> CommandResult {
        if executable == "/usr/bin/ssh" {
            await counter.incrementSSH()
            return CommandResult(status: 0, stdout: "98.00\n", stderr: "")
        }
        return CommandResult(status: 0, stdout: "99.00\n", stderr: "")
    }
}

private actor HardwareVolumeCommandCounter {
    private var sshCount = 0

    func incrementSSH() {
        sshCount += 1
    }

    func sshRequests() -> Int {
        sshCount
    }
}
