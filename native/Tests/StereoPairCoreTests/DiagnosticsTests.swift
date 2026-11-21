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
                    message: "failed /Users/felix/Library/Application Support/Snapcast and user@192.168.0.120"
                )
            ],
            channels: [],
            streams: [],
            issues: ["Cannot reach bot01@192.168.0.120 through /Users/felix/.ssh/id_ed25519"],
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
        XCTAssertFalse(json.contains("/Users/felix"))
        XCTAssertFalse(json.contains("192.168.0.120"))
        XCTAssertFalse(json.contains("bot01"))
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
