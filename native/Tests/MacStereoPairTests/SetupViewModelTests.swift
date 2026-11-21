import StereoPairCore
import XCTest
@testable import MacStereoPair

final class SetupViewModelTests: XCTestCase {
    func testFreshInstallStartsAtWelcomeWithConsoleDisabled() {
        let flow = SetupFlowState()

        XCTAssertEqual(flow.currentStep, .welcome)
        XCTAssertFalse(flow.isConsoleEnabled)
    }

    func testCompletedChecksResumeAtTheNextIncompleteStep() {
        let flow = SetupFlowState(completed: [.welcome, .dependencies])

        XCTAssertEqual(flow.currentStep, .localRuntime)
        XCTAssertTrue(flow.completed.contains(.dependencies))
    }

    func testTerminalHandoffStaysPendingUntilPollingObservesReadiness() {
        var flow = SetupFlowState(completed: [.welcome, .dependencies])
        flow.beginLocalInstall()

        XCTAssertEqual(flow.pendingAction, .installLocalRuntime)
        flow.applyChecks([check(.runtime, .missing)])
        XCTAssertEqual(flow.pendingAction, .installLocalRuntime)

        flow.applyChecks([check(.runtime, .ready)])
        XCTAssertNil(flow.pendingAction)
        XCTAssertTrue(flow.completed.contains(.localRuntime))
        XCTAssertEqual(flow.currentStep, .remoteMac)
    }

    func testDependencyStepDoesNotRequireTheRuntimeThatItWillInstall() {
        var flow = SetupFlowState(completed: [.welcome])
        flow.show(.dependencies)
        let checks = [
            check(.xcodeCommandLineTools, .ready),
            check(.homebrew, .ready),
            check(.blackHole, .ready),
            check(.portAudio, .ready),
            check(.ssh, .ready),
            check(.runtime, .missing)
        ]

        flow.applyChecks(checks)

        XCTAssertTrue(flow.completed.contains(.dependencies))
        XCTAssertEqual(flow.currentStep, .localRuntime)
    }

    func testRemoteFailureKeepsCompletedLocalStateAndAllowsRetry() throws {
        var flow = SetupFlowState(completed: [.welcome, .dependencies, .localRuntime])
        try flow.beginRemoteSetup(user: "tester", host: "198.51.100.20")
        flow.recordFailure("SSH key was not accepted")

        XCTAssertTrue(flow.completed.contains(.localRuntime))
        XCTAssertEqual(flow.lastError, "SSH key was not accepted")
        XCTAssertEqual(flow.currentStep, .remoteMac)

        try flow.beginRemoteSetup(user: "tester", host: "198.51.100.20")
        XCTAssertNil(flow.lastError)
    }

    func testRemoteSetupMarkerMatchesOnlyTheConfiguredTarget() {
        let marker = Data(
            #"{"user":"tester","host":"198.51.100.20","helperPath":"/tmp/remote-mode.sh"}"#.utf8
        )

        XCTAssertTrue(
            SetupRemoteMarker.matches(marker, user: "tester", host: "198.51.100.20")
        )
        XCTAssertFalse(
            SetupRemoteMarker.matches(marker, user: "tester", host: "198.51.100.21")
        )
        XCTAssertFalse(
            SetupRemoteMarker.matches(Data("{broken".utf8), user: "tester", host: "198.51.100.20")
        )
    }

    func testVerificationEnablesConsoleOnlyWhenCoreChecksPass() {
        var flow = SetupFlowState(
            completed: [.welcome, .dependencies, .localRuntime, .remoteMac]
        )

        flow.finishVerification(allChecksReady: false)
        XCTAssertFalse(flow.isConsoleEnabled)
        XCTAssertEqual(flow.currentStep, .verification)

        flow.finishVerification(allChecksReady: true)
        XCTAssertTrue(flow.isConsoleEnabled)
    }

    private func check(
        _ dependency: SetupDependency,
        _ status: SetupCheckStatus
    ) -> SetupCheck {
        SetupCheck(dependency: dependency, status: status)
    }
}
