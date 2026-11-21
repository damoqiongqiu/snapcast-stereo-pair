import Foundation
import XCTest
@testable import StereoPairCore

final class ModeSnapshotNormalizationTests: XCTestCase {
    func testPersistedSystemModeMarksExpectedStopsAsDisabled() {
        let snapshot = RuntimeSnapshot(
            protocolVersion: controlProtocolVersion,
            mode: .system,
            health: .disabled,
            services: [
                service(id: "com.snapcast.server", state: .failed),
                service(id: "com.snapcast.splitter", state: .failed)
            ],
            channels: [],
            streams: [],
            issues: ["Snapserver control API is unavailable"],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let normalized = SystemModeSnapshotNormalizer.normalize(
            snapshot,
            persistedMode: .system
        )

        XCTAssertEqual(normalized.mode, .system)
        XCTAssertEqual(normalized.health, .disabled)
        XCTAssertEqual(normalized.services.map(\.state), [.disabled, .disabled])
        XCTAssertEqual(normalized.issues, [])
    }

    func testSystemModeReportsUnexpectedRunningRuntimeAsDegraded() {
        let snapshot = RuntimeSnapshot(
            protocolVersion: controlProtocolVersion,
            mode: .system,
            health: .disabled,
            services: [service(id: "com.snapcast.server", state: .running)],
            channels: [],
            streams: [],
            issues: [],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let normalized = SystemModeSnapshotNormalizer.normalize(
            snapshot,
            persistedMode: .system
        )

        XCTAssertEqual(normalized.health, .degraded)
        XCTAssertEqual(normalized.services.first?.state, .running)
        XCTAssertEqual(
            normalized.issues,
            ["Runtime services are unexpectedly running in system mode"]
        )
    }

    private func service(id: String, state: ServiceState) -> ServiceStatus {
        ServiceStatus(
            id: id,
            displayName: id,
            state: state,
            pid: state == .running ? 42 : nil,
            runs: 1,
            lastExitCode: state == .failed ? 1 : nil,
            lastSuccessAgeSeconds: nil,
            message: nil
        )
    }
}
