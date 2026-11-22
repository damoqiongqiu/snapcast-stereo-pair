import Foundation

public struct WaveformHistory: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public let peak: Double
        public let rms: Double
        public let clipped: Bool

        public init(peak: Double, rms: Double, clipped: Bool) {
            self.peak = peak
            self.rms = rms
            self.clipped = clipped
        }
    }

    public let capacity: Int
    public private(set) var points: [Point]

    public init(capacity: Int, prefill: Bool = false) {
        self.capacity = max(1, capacity)
        self.points = prefill
            ? Array(
                repeating: Point(peak: 0, rms: 0, clipped: false),
                count: self.capacity
            )
            : []
    }

    public mutating func append(
        peakDb: Double,
        rmsDb: Double,
        clipped: Bool = false
    ) {
        let peak = normalized(peakDb)
        let rms = min(peak, normalized(rmsDb))
        if points.count == capacity {
            points.removeFirst()
        }
        points.append(Point(peak: peak, rms: rms, clipped: clipped))
    }

    private func normalized(_ db: Double) -> Double {
        min(1, max(0, (db + 60) / 60))
    }
}
