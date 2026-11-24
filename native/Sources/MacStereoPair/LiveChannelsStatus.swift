import Combine
import StereoPairCore

@MainActor
final class LiveChannelsStatus: ObservableObject {
    @Published private(set) var left: ChannelStatus?
    @Published private(set) var right: ChannelStatus?

    func update(channels: [ChannelStatus]) {
        let nextLeft = channels.first { $0.streamId == "LeftAudio" }
        let nextRight = channels.first { $0.streamId == "RightAudio" }

        if left != nextLeft {
            left = nextLeft
        }
        if right != nextRight {
            right = nextRight
        }
    }
}
