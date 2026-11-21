import XCTest
@testable import StereoPairCore

final class ControlProtocolTests: XCTestCase {
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
