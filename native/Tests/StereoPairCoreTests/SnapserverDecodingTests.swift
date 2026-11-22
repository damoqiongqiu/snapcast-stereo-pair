import XCTest
@testable import StereoPairCore

final class SnapserverDecodingTests: XCTestCase {
    private let response = """
    {
      "jsonrpc": "2.0",
      "id": 1,
      "result": {
        "server": {
          "groups": [
            {
              "id": "left-group",
              "stream_id": "LeftAudio",
              "clients": [
                {
                  "id": "left-test-client",
                  "connected": true,
                  "config": {
                    "volume": {"percent": 58, "muted": false},
                    "latency": 0
                  }
                }
              ]
            },
            {
              "id": "right-group",
              "stream_id": "RightAudio",
              "clients": [
                {
                  "id": "right-test-client",
                  "connected": true,
                  "config": {
                    "volume": {"percent": 52, "muted": true},
                    "latency": 12
                  }
                }
              ]
            }
          ],
          "streams": [
            {
              "id": "LeftAudio",
              "status": "playing",
              "uri": {"query": {"sampleformat": "48000:24:1"}}
            },
            {
              "id": "RightAudio",
              "status": "playing",
              "uri": {"query": {"sampleformat": "48000:24:1"}}
            }
          ]
        }
      }
    }
    """.data(using: .utf8)!

    func testNormalizesConnectedClientsAndStreams() throws {
        let status = try SnapserverStatus.decode(responseData: response)

        XCTAssertEqual(status.healthIssues, [])
        XCTAssertEqual(status.channels.count, 2)
        XCTAssertEqual(status.channels[0].clientId, "left-test-client")
        XCTAssertEqual(status.channels[0].streamId, "LeftAudio")
        XCTAssertEqual(status.channels[0].volume, 58)
        XCTAssertEqual(status.channels[1].clientId, "right-test-client")
        XCTAssertEqual(status.channels[1].volume, 52)
        XCTAssertTrue(status.channels[1].muted)
        XCTAssertEqual(status.channels[1].latencyMs, 12)
        XCTAssertEqual(status.streams.map(\.id), ["LeftAudio", "RightAudio"])
    }

    func testMissingRightStreamProducesHealthIssue() throws {
        let broken = String(data: response, encoding: .utf8)!
            .replacingOccurrences(of: "\"id\": \"RightAudio\"", with: "\"id\": \"OtherAudio\"")
            .replacingOccurrences(of: "\"stream_id\": \"RightAudio\"", with: "\"stream_id\": \"OtherAudio\"")
            .data(using: .utf8)!

        let status = try SnapserverStatus.decode(responseData: broken)
        XCTAssertTrue(status.healthIssues.contains("RightAudio has no connected client"))
    }

    func testRPCRequestsDisableSnapserverConnectionReuse() throws {
        let request = try SnapserverClient.makeRPCRequest(
            endpoint: URL(string: "http://127.0.0.1:1780/jsonrpc")!,
            id: "volume-test",
            method: "Client.SetVolume",
            params: .object([:])
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Connection"), "close")
    }
}
