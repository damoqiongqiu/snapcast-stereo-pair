import XCTest
@testable import StereoPairCore

final class ModelTests: XCTestCase {
    func testSnapshotRoundTripPreservesModeAndServiceState() throws {
        let service = ServiceStatus(
            id: "com.snapcast.server",
            displayName: "Snapserver",
            state: .running,
            pid: 42,
            runs: 1,
            lastExitCode: nil,
            lastSuccessAgeSeconds: nil,
            message: nil
        )
        let snapshot = RuntimeSnapshot(
            protocolVersion: 1,
            mode: .snapcast,
            health: .healthy,
            services: [service],
            channels: [],
            streams: [],
            issues: [],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(RuntimeSnapshot.self, from: data)

        XCTAssertEqual(decoded.mode, .snapcast)
        XCTAssertEqual(decoded.services.first?.state, .running)
        XCTAssertEqual(decoded.protocolVersion, 1)
    }

    func testSnapshotFromOlderAgentDefaultsHardwareVolumesToEmpty() throws {
        let data = Data(
            """
            {
              "protocolVersion": 1,
              "mode": "snapcast",
              "health": "healthy",
              "services": [],
              "channels": [],
              "streams": [],
              "issues": [],
              "updatedAt": 816968000
            }
            """.utf8
        )

        let snapshot = try JSONDecoder().decode(RuntimeSnapshot.self, from: data)

        XCTAssertEqual(snapshot.hardwareVolumes, [])
    }
}
