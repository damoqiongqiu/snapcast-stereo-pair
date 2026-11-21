import Foundation
import XCTest
@testable import StereoPairCore

final class HealthStabilityTests: XCTestCase {
    func testSingleControlAPIFailurePreservesTheLastHealthySnapshot() {
        var stabilizer = SnapshotStabilizer()
        let healthy = snapshot(health: .healthy, connected: true, issues: [])
        let transientFailure = snapshot(
            health: .failed,
            connected: false,
            issues: ["Snapserver control API is unavailable"]
        )

        XCTAssertEqual(stabilizer.stabilize(healthy), healthy)
        let stabilized = stabilizer.stabilize(transientFailure)

        XCTAssertEqual(stabilized.health, .healthy)
        XCTAssertEqual(stabilized.channels.count, 2)
        XCTAssertEqual(stabilized.issues, [])
    }

    func testPersistentControlAPIFailureBecomesFailedAfterThreePolls() {
        var stabilizer = SnapshotStabilizer()
        let healthy = snapshot(health: .healthy, connected: true, issues: [])
        let failure = snapshot(
            health: .failed,
            connected: false,
            issues: ["Snapserver control API is unavailable"]
        )
        _ = stabilizer.stabilize(healthy)
        _ = stabilizer.stabilize(failure)
        _ = stabilizer.stabilize(failure)

        XCTAssertEqual(stabilizer.stabilize(failure).health, .failed)
    }

    func testSuccessfulPollResetsTheFailureCounter() {
        var stabilizer = SnapshotStabilizer()
        let healthy = snapshot(health: .healthy, connected: true, issues: [])
        let failure = snapshot(
            health: .failed,
            connected: false,
            issues: ["Snapserver control API is unavailable"]
        )
        _ = stabilizer.stabilize(healthy)
        _ = stabilizer.stabilize(failure)
        _ = stabilizer.stabilize(failure)
        _ = stabilizer.stabilize(healthy)
        _ = stabilizer.stabilize(failure)
        _ = stabilizer.stabilize(failure)

        XCTAssertEqual(stabilizer.stabilize(failure).health, .failed)
    }

    private func snapshot(
        health: HealthLevel,
        connected: Bool,
        issues: [String]
    ) -> RuntimeSnapshot {
        RuntimeSnapshot(
            protocolVersion: controlProtocolVersion,
            mode: connected ? .snapcast : .snapcast,
            health: health,
            services: [
                ServiceStatus(
                    id: "com.snapcast.server",
                    displayName: "Snapserver",
                    state: .running,
                    pid: 42,
                    runs: 1,
                    lastExitCode: nil,
                    lastSuccessAgeSeconds: nil,
                    message: nil
                )
            ],
            channels: connected ? [
                ChannelStatus(
                    side: "left",
                    clientId: "left",
                    streamId: "LeftAudio",
                    connected: true,
                    deviceName: "Speakers",
                    volume: 50,
                    muted: false,
                    latencyMs: 0,
                    peakDb: nil,
                    rmsDb: nil,
                    clipped: false
                ),
                ChannelStatus(
                    side: "right",
                    clientId: "right",
                    streamId: "RightAudio",
                    connected: true,
                    deviceName: "Speakers",
                    volume: 50,
                    muted: false,
                    latencyMs: 0,
                    peakDb: nil,
                    rmsDb: nil,
                    clipped: false
                )
            ] : [],
            streams: [],
            issues: issues,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
