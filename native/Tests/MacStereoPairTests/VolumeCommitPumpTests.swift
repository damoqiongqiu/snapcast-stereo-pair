import Foundation
import XCTest
@testable import MacStereoPair

@MainActor
final class VolumeCommitPumpTests: XCTestCase {
    func testQuickClickCommitsOnlyItsFinalTarget() async {
        let recorder = VolumeCommitRecorder()
        let pump = makePump()
        pump.begin(
            commit: { recorder.record($0) },
            onFinalCommit: { recorder.finished = true }
        )

        pump.preview(42)
        pump.finish(42)

        await waitUntil { recorder.finished }
        XCTAssertEqual(recorder.commits, [42])
    }

    func testDragCoalescesPreviewUpdatesAndCommitsFinalTargetLast() async {
        let recorder = VolumeCommitRecorder()
        let pump = makePump()
        pump.begin(
            commit: { recorder.record($0) },
            onFinalCommit: { recorder.finished = true }
        )

        pump.preview(10)
        try? await Task.sleep(for: .milliseconds(35))
        pump.preview(20)
        pump.preview(30)
        try? await Task.sleep(for: .milliseconds(70))
        pump.finish(40)

        await waitUntil { recorder.finished }
        XCTAssertEqual(recorder.commits.first, 10)
        XCTAssertEqual(recorder.commits.last, 40)
        XCTAssertTrue(recorder.commits.contains(30))
        XCTAssertLessThanOrEqual(recorder.commits.count, 3)
    }

    func testFinalTargetWaitsForAnInFlightPreviewCommit() async {
        let recorder = VolumeCommitRecorder()
        let pump = makePump()
        pump.begin(
            commit: {
                recorder.beginCommit($0)
                if $0 == 10 {
                    try? await Task.sleep(for: .milliseconds(40))
                }
                recorder.endCommit($0)
            },
            onFinalCommit: { recorder.finished = true }
        )

        pump.preview(10)
        await waitUntil { recorder.commits == [10] }
        pump.finish(20)

        await waitUntil { recorder.finished }
        XCTAssertEqual(recorder.commits, [10, 20])
        XCTAssertEqual(recorder.maximumConcurrentCommits, 1)
    }

    func testRapidFinalTargetsAreCoalesced() async {
        let recorder = VolumeCommitRecorder()
        let pump = makePump()
        pump.begin(
            commit: { recorder.record($0) },
            onFinalCommit: { recorder.finished = true }
        )

        pump.finish(20)
        pump.finish(30)

        await waitUntil { recorder.finished }
        XCTAssertEqual(recorder.commits, [30])
    }

    private func makePump() -> VolumeCommitPump {
        VolumeCommitPump(
            initialPreviewDelay: .milliseconds(20),
            previewInterval: .milliseconds(35),
            defaultFinalDelay: .milliseconds(15)
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !condition() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(condition(), "Timed out waiting for condition")
    }
}

@MainActor
private final class VolumeCommitRecorder {
    private(set) var commits: [Int] = []
    private(set) var activeCommits = 0
    private(set) var maximumConcurrentCommits = 0
    var finished = false

    func beginCommit(_ target: Int) {
        activeCommits += 1
        maximumConcurrentCommits = max(maximumConcurrentCommits, activeCommits)
        commits.append(target)
    }

    func endCommit(_ target: Int) {
        activeCommits -= 1
    }

    func record(_ target: Int) {
        beginCommit(target)
        endCommit(target)
    }
}
