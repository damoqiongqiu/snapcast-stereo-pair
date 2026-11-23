import Foundation

public enum ChannelMetricsApplication {
    public static func apply(
        _ metrics: AudioMetricsSnapshot?,
        to channels: [ChannelStatus]
    ) -> [ChannelStatus] {
        channels.map { channel in
            var channel = channel
            guard channel.connected, let metrics else {
                channel.peakDb = nil
                channel.rmsDb = nil
                channel.clipped = false
                return channel
            }
            channel.peakDb = channel.side == "left" ? metrics.leftPeakDb : metrics.rightPeakDb
            channel.rmsDb = channel.side == "left" ? metrics.leftRmsDb : metrics.rightRmsDb
            channel.clipped = channel.side == "left" ? metrics.leftClipped : metrics.rightClipped
            return channel
        }
    }
}
