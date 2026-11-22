import XCTest
@testable import MacStereoPair

final class StatusBusLayoutTests: XCTestCase {
    func testTrailingDividerIsOmittedAfterTheLastZone() {
        XCTAssertTrue(StatusBusLayout.showsTrailingDivider(after: 0, zoneCount: 4))
        XCTAssertTrue(StatusBusLayout.showsTrailingDivider(after: 1, zoneCount: 4))
        XCTAssertTrue(StatusBusLayout.showsTrailingDivider(after: 2, zoneCount: 4))
        XCTAssertFalse(StatusBusLayout.showsTrailingDivider(after: 3, zoneCount: 4))
    }
}
