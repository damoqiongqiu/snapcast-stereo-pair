import XCTest
@testable import MacStereoPair

final class VolumeSliderDraftTests: XCTestCase {
    func testDragUsesLocalValueWhilePublishedSnapshotIsStale() {
        var draft = VolumeSliderDraft()
        draft.beginDragging(published: 10)
        draft.update(73)

        XCTAssertEqual(draft.displayValue(published: 10), 73)
    }

    func testFinishDraggingCommitsRoundedPercentAndWaitsForAcknowledgement() {
        var draft = VolumeSliderDraft()
        draft.beginDragging(published: 10)
        draft.update(72.6)

        XCTAssertEqual(draft.finishDragging(), 73)
        XCTAssertEqual(draft.displayValue(published: 10), 72.6)

        draft.completeCommit()
        XCTAssertEqual(draft.displayValue(published: 10), 10)
    }

    func testDraftClampsToSliderRange() {
        var draft = VolumeSliderDraft()
        draft.beginDragging(published: 10)

        draft.update(-5)
        XCTAssertEqual(draft.displayValue(published: 10), 0)

        draft.update(125)
        XCTAssertEqual(draft.displayValue(published: 10), 100)
    }

    func testKeyboardStyleChangesCanBeCommittedWithoutMouseDrag() {
        var draft = VolumeSliderDraft()

        draft.update(48)

        XCTAssertFalse(draft.isDragging)
        XCTAssertEqual(draft.displayValue(published: 10), 48)
        XCTAssertEqual(draft.finishDragging(), 48)
    }
}
