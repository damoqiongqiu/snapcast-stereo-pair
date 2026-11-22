import Foundation
import XCTest
@testable import MacStereoPair

final class SingleInstanceLockTests: XCTestCase {
    func testSecondHolderIsRejectedUntilFirstHolderReleases() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let lockURL = directory.appendingPathComponent("gui.lock")

        let first = try XCTUnwrap(SingleInstanceLock(url: lockURL))
        XCTAssertNil(SingleInstanceLock(url: lockURL))

        first.release()
        let replacement = try XCTUnwrap(SingleInstanceLock(url: lockURL))
        replacement.release()
    }
}
