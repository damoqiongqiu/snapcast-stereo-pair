import Foundation
import StereoPairCore
import XCTest
@testable import MacStereoPair

final class HardwareVolumeIndicatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testFullVolumeIsHealthy() {
        let state = HardwareVolumeIndicatorState.make(
            status: status(100, checkedAt: now),
            now: now
        )

        XCTAssertEqual(state.tone, .healthy)
        XCTAssertEqual(state.valueText, "100%")
        XCTAssertEqual(state.labelKey, "systemVolume.normal")
    }

    func testLowVolumeRequiresAttention() {
        let state = HardwareVolumeIndicatorState.make(
            status: status(72.5, checkedAt: now),
            now: now
        )

        XCTAssertEqual(state.tone, .warning)
        XCTAssertEqual(state.valueText, "73%")
        XCTAssertEqual(state.labelKey, "systemVolume.low")
    }

    func testMissingMeasurementIsUnavailable() {
        let state = HardwareVolumeIndicatorState.make(
            status: HardwareVolumeStatus(
                side: "left",
                volumePercent: nil,
                checkedAt: nil,
                error: "unavailable"
            ),
            now: now
        )

        XCTAssertEqual(state.tone, .unavailable)
        XCTAssertEqual(state.valueText, "—")
        XCTAssertEqual(state.labelKey, "systemVolume.unavailable")
    }

    func testOldMeasurementIsMarkedStaleEvenWhenVolumeWasFull() {
        let state = HardwareVolumeIndicatorState.make(
            status: status(100, checkedAt: now.addingTimeInterval(-90)),
            now: now
        )

        XCTAssertEqual(state.tone, .stale)
        XCTAssertEqual(state.valueText, "100%")
        XCTAssertEqual(state.labelKey, "systemVolume.stale")
    }

    private func status(_ volume: Double, checkedAt: Date) -> HardwareVolumeStatus {
        HardwareVolumeStatus(
            side: "left",
            volumePercent: volume,
            checkedAt: checkedAt,
            error: nil
        )
    }
}
