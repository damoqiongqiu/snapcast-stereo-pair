import StereoPairCore
import XCTest
@testable import MacStereoPair

final class LEDStateTests: XCTestCase {
    func testRunningServiceUsesSteadyGreenUnlessHeartbeatIsFresh() {
        XCTAssertEqual(
            ServiceLEDAppearance.resolve(state: .running, freshActivity: false),
            ServiceLEDAppearance(tone: .green, motion: .steady, labelKey: "status.healthy")
        )
        XCTAssertEqual(
            ServiceLEDAppearance.resolve(state: .running, freshActivity: true),
            ServiceLEDAppearance(tone: .green, motion: .pulse, labelKey: "status.healthy")
        )
    }

    func testDegradedFailedAndDisabledStatesRemainDistinctWithoutColor() {
        XCTAssertEqual(
            ServiceLEDAppearance.resolve(state: .inactive, freshActivity: false),
            ServiceLEDAppearance(tone: .amber, motion: .steady, labelKey: "status.warning")
        )
        XCTAssertEqual(
            ServiceLEDAppearance.resolve(state: .failed, freshActivity: false),
            ServiceLEDAppearance(tone: .red, motion: .steady, labelKey: "status.failed")
        )
        XCTAssertEqual(
            ServiceLEDAppearance.resolve(state: .disabled, freshActivity: false),
            ServiceLEDAppearance(tone: .gray, motion: .steady, labelKey: "status.disabled")
        )
    }

    func testReduceMotionSuppressesPulseWithoutChangingSemanticState() {
        XCTAssertEqual(
            ServiceLEDAppearance.resolve(
                state: .running,
                freshActivity: true,
                reduceMotion: true
            ),
            ServiceLEDAppearance(tone: .green, motion: .steady, labelKey: "status.healthy")
        )
    }
}
