import XCTest
@testable import StereoPairCore

final class WaveformHistoryTests: XCTestCase {
    func testWaveformHistoryKeepsLatestSamplesAtFixedCapacity() {
        var history = WaveformHistory(capacity: 3)
        history.append(peakDb: -60, rmsDb: -60)
        history.append(peakDb: -6, rmsDb: -12)
        history.append(peakDb: -3, rmsDb: -9)
        history.append(peakDb: -12, rmsDb: -18)

        XCTAssertEqual(history.samples.count, 3)
        XCTAssertEqual(history.samples[0], 0.9, accuracy: 0.0001)
        XCTAssertEqual(history.samples[1], 0.95, accuracy: 0.0001)
        XCTAssertEqual(history.samples[2], 0.8, accuracy: 0.0001)
    }

    func testWaveformHistoryClampsSilenceAndOverload() {
        var history = WaveformHistory(capacity: 2)
        history.append(peakDb: -120, rmsDb: -120)
        history.append(peakDb: 3, rmsDb: 3)

        XCTAssertEqual(history.samples, [0, 1])
    }

    func testPrefilledHistoryDrawsAcrossFullWidthBeforeAudioArrives() {
        let history = WaveformHistory(capacity: 4, prefill: true)
        XCTAssertEqual(history.samples, [0, 0, 0, 0])
    }
}
