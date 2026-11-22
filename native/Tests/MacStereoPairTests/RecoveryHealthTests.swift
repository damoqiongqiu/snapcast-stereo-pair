import StereoPairCore
import XCTest
@testable import MacStereoPair

final class RecoveryHealthTests: XCTestCase {
    func testRecentSuccessfulPeriodicPairingCheckIsHealthyBetweenRuns() {
        let service = pairingService(state: .inactive, age: 12, exitCode: 0)

        XCTAssertEqual(RecoveryHealthPresentation.effectiveState(for: service), .running)
    }

    func testStaleSuccessfulPeriodicPairingCheckReturnsToWarning() {
        let service = pairingService(state: .inactive, age: 46, exitCode: 0)

        XCTAssertEqual(RecoveryHealthPresentation.effectiveState(for: service), .inactive)
    }

    func testFailedPairingCheckRemainsFailed() {
        let service = pairingService(state: .failed, age: 2, exitCode: 1)

        XCTAssertEqual(RecoveryHealthPresentation.effectiveState(for: service), .failed)
    }

    func testInactiveNonPeriodicServiceStillShowsWarning() {
        let service = ServiceStatus(
            id: "com.snapcast.wake-recovery",
            displayName: "Wake Recovery",
            state: .inactive,
            pid: nil,
            runs: 1,
            lastExitCode: 0,
            lastSuccessAgeSeconds: 1,
            message: nil
        )

        XCTAssertEqual(RecoveryHealthPresentation.effectiveState(for: service), .inactive)
    }

    private func pairingService(
        state: ServiceState,
        age: Double,
        exitCode: Int
    ) -> ServiceStatus {
        ServiceStatus(
            id: "com.snapcast.pairing",
            displayName: "Automatic Pairing",
            state: state,
            pid: nil,
            runs: 16,
            lastExitCode: exitCode,
            lastSuccessAgeSeconds: age,
            message: state == .failed ? "routes unavailable" : "stereo routes verified"
        )
    }
}
