import CoreGraphics
import XCTest
@testable import MacStereoPair

final class WindowPlacementPolicyTests: XCTestCase {
    func testConsoleCannotResizeBelowUnclippedViewport() {
        XCTAssertEqual(MainWindowMetrics.minimumSize.width, 1040)
        XCTAssertEqual(MainWindowMetrics.minimumSize.height, 720)
    }

    func testWindowRequiresCenteringWhenSavedFrameIsOffscreen() {
        let window = CGRect(x: 1952, y: 195, width: 1040, height: 720)
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 945)

        XCTAssertTrue(WindowPlacementPolicy.requiresRecovery(
            windowFrame: window,
            visibleFrame: visible
        ))
    }

    func testPartiallyVisibleWindowKeepsItsPosition() {
        let window = CGRect(x: 1400, y: 100, width: 1040, height: 720)
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 945)

        XCTAssertFalse(WindowPlacementPolicy.requiresRecovery(
            windowFrame: window,
            visibleFrame: visible
        ))
    }

    func testWindowSizeIsClampedToConfiguredRange() {
        let minimum = CGSize(width: 900, height: 680)
        let maximum = CGSize(width: 1240, height: 860)

        XCTAssertEqual(
            WindowSizePolicy.clamp(
                CGSize(width: 700, height: 500),
                minimum: minimum,
                maximum: maximum
            ),
            minimum
        )
        XCTAssertEqual(
            WindowSizePolicy.clamp(
                CGSize(width: 1600, height: 1000),
                minimum: minimum,
                maximum: maximum
            ),
            maximum
        )
    }
}
