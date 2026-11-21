import Foundation

public struct WaveformHistory: Equatable, Sendable {
    public let capacity: Int
    public private(set) var samples: [Double]

    public init(capacity: Int, prefill: Bool = false) {
        self.capacity = max(1, capacity)
        self.samples = prefill ? Array(repeating: 0, count: self.capacity) : []
    }

    public mutating func append(peakDb: Double, rmsDb: Double) {
        let peak = normalized(peakDb)
        let rms = normalized(rmsDb)
        if samples.count == capacity {
            samples.removeFirst()
        }
        samples.append(max(peak, rms))
    }

    private func normalized(_ db: Double) -> Double {
        min(1, max(0, (db + 60) / 60))
    }
}
