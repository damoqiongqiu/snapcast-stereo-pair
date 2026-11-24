import Combine
import StereoPairCore

@MainActor
final class MenuBarStatus: ObservableObject {
    struct Value: Equatable {
        var mode: AudioMode?
        var health: HealthLevel?
        var masterVolume: Int
        var isWorking: Bool
        var isConnected: Bool

        static let empty = Value(
            mode: nil,
            health: nil,
            masterVolume: 0,
            isWorking: false,
            isConnected: false
        )
    }

    @Published private(set) var value = Value.empty

    func update(
        snapshot: RuntimeSnapshot?,
        isWorking: Bool,
        isConnected: Bool
    ) {
        let volumes = snapshot?.channels.map(\.volume) ?? []
        let next = Value(
            mode: snapshot?.mode,
            health: snapshot?.health,
            masterVolume: volumes.isEmpty ? 0 : volumes.reduce(0, +) / volumes.count,
            isWorking: isWorking,
            isConnected: isConnected
        )
        guard next != value else { return }
        value = next
    }
}
