import Foundation

struct VolumeSliderDraft: Equatable {
    private var draftValue: Double?
    private(set) var isDragging = false

    mutating func beginDragging(published: Double) {
        draftValue = Self.clamped(published)
        isDragging = true
    }

    mutating func update(_ value: Double) {
        draftValue = Self.clamped(value)
    }

    func displayValue(published: Double) -> Double {
        draftValue ?? published
    }

    mutating func finishDragging() -> Int? {
        isDragging = false
        return draftValue.map { Int($0.rounded()) }
    }

    mutating func completeCommit() {
        draftValue = nil
    }

    private static func clamped(_ value: Double) -> Double {
        min(100, max(0, value))
    }
}
