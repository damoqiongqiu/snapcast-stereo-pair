import Darwin
import XCTest
@testable import StereoPairCore

final class UnixSocketRecoveryTests: XCTestCase {
    func testTransientAcceptInterruptionsAreRetriedImmediately() {
        XCTAssertEqual(UnixAcceptRecovery.action(for: EINTR), .retryImmediately)
        XCTAssertEqual(UnixAcceptRecovery.action(for: ECONNABORTED), .retryImmediately)
    }

    func testFileDescriptorExhaustionPausesBeforeRetrying() {
        XCTAssertEqual(UnixAcceptRecovery.action(for: EMFILE), .pauseAndRetry)
        XCTAssertEqual(UnixAcceptRecovery.action(for: ENFILE), .pauseAndRetry)
    }

    func testInvalidListenerStopsTheAcceptLoop() {
        XCTAssertEqual(UnixAcceptRecovery.action(for: EBADF), .stop)
        XCTAssertEqual(UnixAcceptRecovery.action(for: ENOTSOCK), .stop)
    }
}
