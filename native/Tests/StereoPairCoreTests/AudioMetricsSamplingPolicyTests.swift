import StereoPairCore
import XCTest

final class AudioMetricsSamplingPolicyTests: XCTestCase {
    func testAudioMetricsAreSampledTenTimesPerSecond() {
        XCTAssertEqual(AudioMetricsSamplingPolicy.interval, .milliseconds(100))
    }
}
