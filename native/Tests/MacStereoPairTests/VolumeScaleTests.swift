import XCTest
@testable import MacStereoPair

final class VolumeScaleTests: XCTestCase {
    func testTicksProvideFivePercentControlReference() {
        XCTAssertEqual(VolumeScale.tickValues.count, 21)
        XCTAssertEqual(VolumeScale.tickValues.first, 0)
        XCTAssertEqual(VolumeScale.tickValues.last, 100)
        XCTAssertEqual(
            VolumeScale.tickValues,
            [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100]
        )
    }

    func testOnlyQuarterPointsReceiveLabels() {
        XCTAssertEqual(VolumeScale.labeledValues, [0, 25, 50, 75, 100])
    }

    func testTickFractionMapsAndClampsToSliderRange() {
        XCTAssertEqual(VolumeScale.fraction(for: 0), 0)
        XCTAssertEqual(VolumeScale.fraction(for: 5), 0.05)
        XCTAssertEqual(VolumeScale.fraction(for: 50), 0.5)
        XCTAssertEqual(VolumeScale.fraction(for: 100), 1)
        XCTAssertEqual(VolumeScale.fraction(for: -5), 0)
        XCTAssertEqual(VolumeScale.fraction(for: 105), 1)
    }
}
