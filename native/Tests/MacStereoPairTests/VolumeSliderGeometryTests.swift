import XCTest
@testable import MacStereoPair

final class VolumeSliderGeometryTests: XCTestCase {
    func testKnobCenterAlignsWithScaleEndpointsAndMidpoint() {
        let width: CGFloat = 462

        XCTAssertEqual(
            VolumeSliderGeometry.x(for: 0, in: width),
            VolumeSliderGeometry.trackInset,
            accuracy: 0.001
        )
        XCTAssertEqual(
            VolumeSliderGeometry.x(for: 50, in: width),
            width / 2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            VolumeSliderGeometry.x(for: 100, in: width),
            width - VolumeSliderGeometry.trackInset,
            accuracy: 0.001
        )
    }

    func testPositionRoundTripsThroughEveryFivePercentScaleMark() {
        let width: CGFloat = 462

        for value in VolumeScale.tickValues {
            let position = VolumeSliderGeometry.x(for: Double(value), in: width)
            XCTAssertEqual(
                VolumeSliderGeometry.value(at: position, in: width),
                Double(value),
                accuracy: 0.001
            )
        }
    }

    func testValuesClampToSliderBounds() {
        let width: CGFloat = 462

        XCTAssertEqual(
            VolumeSliderGeometry.value(at: -100, in: width),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            VolumeSliderGeometry.value(at: width + 100, in: width),
            100,
            accuracy: 0.001
        )
    }
}
