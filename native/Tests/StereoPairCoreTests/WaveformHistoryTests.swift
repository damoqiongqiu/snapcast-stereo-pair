import XCTest
@testable import StereoPairCore

final class WaveformHistoryTests: XCTestCase {
    func testWaveformHistoryKeepsLatestSamplesAtFixedCapacity() {
        var history = WaveformHistory(capacity: 3)
        history.append(peakDb: -60, rmsDb: -60)
        history.append(peakDb: -6, rmsDb: -12)
        history.append(peakDb: -3, rmsDb: -9)
        history.append(peakDb: -12, rmsDb: -18)

        XCTAssertEqual(history.points.count, 3)
        XCTAssertEqual(history.points[0].peak, 0.9, accuracy: 0.0001)
        XCTAssertEqual(history.points[0].rms, 0.8, accuracy: 0.0001)
        XCTAssertEqual(history.points[1].peak, 0.95, accuracy: 0.0001)
        XCTAssertEqual(history.points[1].rms, 0.85, accuracy: 0.0001)
        XCTAssertEqual(history.points[2].peak, 0.8, accuracy: 0.0001)
        XCTAssertEqual(history.points[2].rms, 0.7, accuracy: 0.0001)
    }

    func testWaveformHistoryClampsSilenceAndOverload() {
        var history = WaveformHistory(capacity: 2)
        history.append(peakDb: -120, rmsDb: -120)
        history.append(peakDb: 3, rmsDb: 3, clipped: true)

        XCTAssertEqual(history.points[0], .init(peak: 0, rms: 0, clipped: false))
        XCTAssertEqual(history.points[1], .init(peak: 1, rms: 1, clipped: true))
    }

    func testPrefilledHistoryDrawsAcrossFullWidthBeforeAudioArrives() {
        let history = WaveformHistory(capacity: 4, prefill: true)
        XCTAssertEqual(history.points, Array(
            repeating: .init(peak: 0, rms: 0, clipped: false),
            count: 4
        ))
    }

    func testWaveformHistoryNeverLetsRMSExceedPeak() {
        var history = WaveformHistory(capacity: 1)

        history.append(peakDb: -12, rmsDb: -3)

        XCTAssertEqual(history.points[0].peak, history.points[0].rms)
    }

    func testWaveformHistoryAppliesChannelVolumeAndMute() {
        var history = WaveformHistory(capacity: 2)

        history.append(
            peakDb: -6,
            rmsDb: -12,
            volumePercent: 50,
            muted: false
        )
        history.append(
            peakDb: -6,
            rmsDb: -12,
            volumePercent: 100,
            muted: true
        )

        XCTAssertEqual(history.points[0].peak, 0.8, accuracy: 0.002)
        XCTAssertEqual(history.points[0].rms, 0.7, accuracy: 0.002)
        XCTAssertEqual(history.points[1].peak, 0)
        XCTAssertEqual(history.points[1].rms, 0)
    }
}
