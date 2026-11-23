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
        volumePercent: Int = 100,
        muted: Bool = false,
        clipped: Bool = false
    ) {
        let volume = min(100, max(0, volumePercent))
        let volumeGainDB = muted || volume == 0
            ? -120
            : 20 * log10(Double(volume) / 100)
        let peak = normalized(peakDb + volumeGainDB)
        let rms = min(peak, normalized(rmsDb + volumeGainDB))
        if points.count == capacity {
            points.removeFirst()
        }
        points.append(Point(peak: peak, rms: rms, clipped: clipped))
    }

    public mutating func update(channel: ChannelStatus?) {
        guard let channel, channel.connected else {
            points = Array(
                repeating: Point(peak: 0, rms: 0, clipped: false),
                count: capacity
            )
            return
        }
        append(
            peakDb: channel.peakDb ?? -120,
            rmsDb: channel.rmsDb ?? -120,
            volumePercent: channel.volume,
            muted: channel.muted,
            clipped: channel.clipped
        )
    }

    private func normalized(_ db: Double) -> Double {
        min(1, max(0, (db + 60) / 60))
    }
}
