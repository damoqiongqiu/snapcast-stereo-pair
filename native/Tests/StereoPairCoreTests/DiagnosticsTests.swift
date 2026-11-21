import Foundation
import XCTest
@testable import StereoPairCore

final class DiagnosticsTests: XCTestCase {
    func testRedactedDiagnosticsRemovePrivatePathsAndNetworkAddresses() throws {
        let snapshot = RuntimeSnapshot(
            protocolVersion: controlProtocolVersion,
            mode: .snapcast,
            health: .degraded,
            services: [
                ServiceStatus(
                    id: "com.snapcast.server",
                    displayName: "Snapserver",
                    state: .failed,
                    pid: 42,
                    runs: 3,
                    lastExitCode: 1,
                    lastSuccessAgeSeconds: 2,
                    message: "failed /Users/tester/Library/Application Support/Snapcast and user@198.51.100.20"
                )
            ],
            channels: [],
            streams: [],
            issues: ["Cannot reach tester@198.51.100.20 through /Users/tester/.ssh/id_ed25519"],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let report = DiagnosticsBuilder.make(
            snapshot: snapshot,
            runtimeVersion: "0.2.0",
            redacted: true,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)

        XCTAssertEqual(report.protocolVersion, controlProtocolVersion)
        XCTAssertEqual(report.runtimeVersion, "0.2.0")
        XCTAssertFalse(json.contains("/Users/tester"))
        XCTAssertFalse(json.contains("198.51.100.20"))
        XCTAssertFalse(json.contains("tester"))
        XCTAssertTrue(json.contains("<redacted>"))
    }

    func testServiceMaintenanceOnlyAcceptsKnownRuntimeServices() {
        XCTAssertEqual(
            ServiceMaintenance.restartArguments(serviceId: "com.snapcast.server"),
            ["kickstart", "-k", "gui/\(getuid())/com.snapcast.server"]
        )
        XCTAssertNil(ServiceMaintenance.restartArguments(serviceId: "com.example.arbitrary"))
        XCTAssertNil(ServiceMaintenance.restartArguments(serviceId: "../../bin/sh"))
    }
}
