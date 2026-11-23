import XCTest
@testable import StereoPairCore

final class ChannelMetricsApplicationTests: XCTestCase {
    func testDisconnectedChannelCannotDisplayLiveSourceMetrics() {
        let metrics = AudioMetricsSnapshot(
            leftPeakDb: -3,
            leftRmsDb: -9,
            rightPeakDb: -6,
            rightRmsDb: -12,
            leftClipped: false,
            rightClipped: false,
            sampleRate: 48_000
        )
        let channels = [
            channel(side: "left", streamId: "LeftAudio", connected: false),
            channel(side: "right", streamId: "RightAudio", connected: true)
        ]

        let result = ChannelMetricsApplication.apply(metrics, to: channels)

        XCTAssertNil(result[0].peakDb)
        XCTAssertNil(result[0].rmsDb)
        XCTAssertEqual(result[1].peakDb, -6)
        XCTAssertEqual(result[1].rmsDb, -12)
    }

    func testMissingMetricsClearsPreviouslyRenderedLevels() {
        var channel = channel(side: "left", streamId: "LeftAudio", connected: true)
        channel.peakDb = -3
        channel.rmsDb = -9

        let result = ChannelMetricsApplication.apply(nil, to: [channel])

        XCTAssertNil(result[0].peakDb)
        XCTAssertNil(result[0].rmsDb)
        XCTAssertFalse(result[0].clipped)
    }

    private func channel(
        side: String,
        streamId: String,
        connected: Bool
    ) -> ChannelStatus {
        ChannelStatus(
            side: side,
            clientId: "\(side)-client",
            streamId: streamId,
            connected: connected,
            deviceName: "Speakers",
            volume: 100,
            muted: false,
            latencyMs: 0,
            peakDb: nil,
            rmsDb: nil,
            clipped: false
        )
    }
}
