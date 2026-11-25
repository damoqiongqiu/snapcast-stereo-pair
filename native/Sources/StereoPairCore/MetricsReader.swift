import Darwin
import Foundation
import StereoPairMetricsBridge

public struct AudioMetricsSnapshot: Sendable {
    public var leftPeakDb: Double
    public var leftRmsDb: Double
    public var rightPeakDb: Double
    public var rightRmsDb: Double
    public var leftClipped: Bool
    public var rightClipped: Bool
    public var sampleRate: UInt32
    public var callbackCount: UInt64 = 0
    public var generatedSilenceCycles: UInt64 = 0
    public var droppedFrames: UInt64 = 0
    public var recoveryAttempts: UInt32 = 0
    public var successfulRecoveries: UInt32 = 0
}

private struct SharedAudioMetrics {
    var sequence: UInt64 = 0
    var timestampNs: UInt64 = 0
    var leftPeakDb: Float = 0
    var leftRmsDb: Float = 0
    var rightPeakDb: Float = 0
    var rightRmsDb: Float = 0
    var leftClipped: UInt32 = 0
    var rightClipped: UInt32 = 0
    var sampleRate: UInt32 = 0
    var flags: UInt32 = 0
    var callbackCount: UInt64 = 0
    var generatedSilenceCycles: UInt64 = 0
    var droppedFrames: UInt64 = 0
    var recoveryAttempts: UInt32 = 0
    var successfulRecoveries: UInt32 = 0
}

public struct MetricsReader: Sendable {
    public init() {}

    public func read() -> AudioMetricsSnapshot? {
        let fd = snapcast_metrics_open_readonly()
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        guard let pointer = mmap(
            nil,
            MemoryLayout<SharedAudioMetrics>.stride,
            PROT_READ,
            MAP_SHARED,
            fd,
            0
        ), pointer != MAP_FAILED else {
            return nil
        }
        defer { munmap(pointer, MemoryLayout<SharedAudioMetrics>.stride) }

        let metrics = pointer.assumingMemoryBound(to: SharedAudioMetrics.self)
        for _ in 0..<4 {
            let first = metrics.pointee.sequence
            if first % 2 != 0 { continue }
            let value = metrics.pointee
            let second = metrics.pointee.sequence
            guard first == second, (value.flags & 1) == 1 else { continue }
            return AudioMetricsSnapshot(
                leftPeakDb: Double(value.leftPeakDb),
                leftRmsDb: Double(value.leftRmsDb),
                rightPeakDb: Double(value.rightPeakDb),
                rightRmsDb: Double(value.rightRmsDb),
                leftClipped: value.leftClipped != 0,
                rightClipped: value.rightClipped != 0,
                sampleRate: value.sampleRate,
                callbackCount: value.callbackCount,
                generatedSilenceCycles: value.generatedSilenceCycles,
                droppedFrames: value.droppedFrames,
                recoveryAttempts: value.recoveryAttempts,
                successfulRecoveries: value.successfulRecoveries
            )
        }
        return nil
    }
}
