import Foundation

public struct SnapshotStabilizer: Sendable {
    private let failureThreshold: Int
    private var lastValidSnapshot: RuntimeSnapshot?
    private var consecutiveControlFailures = 0

    public init(failureThreshold: Int = 3) {
        self.failureThreshold = max(1, failureThreshold)
    }

    public mutating func stabilize(_ candidate: RuntimeSnapshot) -> RuntimeSnapshot {
        if isTransientControlFailure(candidate) {
            consecutiveControlFailures += 1
            if consecutiveControlFailures < failureThreshold,
               let lastValidSnapshot {
                var stable = lastValidSnapshot
                stable.updatedAt = candidate.updatedAt
                return stable
            }
            return candidate
        }

        consecutiveControlFailures = 0
        if !candidate.channels.isEmpty {
            lastValidSnapshot = candidate
        }
        return candidate
    }

    private func isTransientControlFailure(_ snapshot: RuntimeSnapshot) -> Bool {
        snapshot.health == .failed &&
            snapshot.channels.isEmpty &&
            snapshot.issues == ["Snapserver control API is unavailable"]
    }
}
