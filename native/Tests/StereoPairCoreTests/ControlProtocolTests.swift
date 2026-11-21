import XCTest
@testable import StereoPairCore

final class ControlProtocolTests: XCTestCase {
    func testDiagnosticsResponseRoundTripsThroughProtocol() throws {
        let event = ControlEvent.diagnostics(
            requestId: "diagnostics-1",
            json: #"{"health":"healthy","protocolVersion":1}"#
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(ControlEvent.self, from: data)

        XCTAssertEqual(decoded, event)
    }

    func testServiceRestartRequestRoundTripsThroughProtocol() throws {
        let request = ControlRequest.restartService(
            requestId: "restart-1",
            serviceId: "com.snapcast.splitter"
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ControlRequest.self, from: data)

        XCTAssertEqual(decoded, request)
    }

    func testUnixSocketReturnsSnapshotForRequest() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let socketURL = directory.appendingPathComponent("control.sock")
        let snapshot = RuntimeSnapshot(
            protocolVersion: controlProtocolVersion,
            mode: .snapcast,
            health: .healthy,
            services: [],
            channels: [],
            streams: [],
            issues: [],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let server = UnixControlServer(socketURL: socketURL) { request in
            guard case .snapshot = request else {
                return .error(requestId: "unknown", message: "unexpected request")
            }
            return .snapshot(snapshot)
        }
        try server.start()
        defer { server.stop() }

        let event = try UnixControlClient(socketURL: socketURL)
            .send(.snapshot(requestId: "test-1"))

        guard case .snapshot(let received) = event else {
            return XCTFail("Expected snapshot event")
        }
        XCTAssertEqual(received.mode, .snapcast)
        XCTAssertEqual(received.protocolVersion, controlProtocolVersion)
    }
}
