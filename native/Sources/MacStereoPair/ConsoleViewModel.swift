import Foundation
import StereoPairCore

@MainActor
final class ConsoleViewModel: ObservableObject {
    @Published var snapshot: RuntimeSnapshot?
    @Published var isWorking = false
    @Published var message: String?

    private let socketURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Snapcast/run/control.sock")
    private var pollingTask: Task<Void, Never>?

    var left: ChannelStatus? { snapshot?.channels.first { $0.streamId == "LeftAudio" } }
    var right: ChannelStatus? { snapshot?.channels.first { $0.streamId == "RightAudio" } }
    var masterVolume: Int {
        guard left != nil || right != nil else { return 0 }
        return Int((((left?.volume ?? 0) + (right?.volume ?? 0))) / 2)
    }
    var isSnapcast: Bool { snapshot?.mode == .snapcast }
    var healthy: Bool { snapshot?.health == .healthy }

    func start() async {
        guard pollingTask == nil else { return }
        pollingTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func refresh() async {
        do {
            let event = try await Task.detached {
                try UnixControlClient(socketURL: self.socketURL)
                    .send(.snapshot(requestId: UUID().uuidString))
            }.value
            if case .snapshot(let value) = event {
                snapshot = value
                message = nil
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func setMode(_ mode: AudioMode) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let event = try await Task.detached {
                try UnixControlClient(socketURL: self.socketURL)
                    .send(.setAudioMode(requestId: UUID().uuidString, audioMode: mode))
            }.value
            if case .error(_, let error) = event {
                message = error
            } else if case .modeChanged(_, let result) = event {
                message = result.remoteWarning
            }
            await refresh()
        } catch {
            message = error.localizedDescription
        }
    }

    func setVolume(_ side: ChannelStatus, percent: Int) async {
        do {
            _ = try await Task.detached {
                try UnixControlClient(socketURL: self.socketURL)
                    .send(.setClientVolume(
                        requestId: UUID().uuidString,
                        clientId: side.clientId,
                        percent: percent
                    ))
            }.value
            await refresh()
        } catch {
            message = error.localizedDescription
        }
    }

    func setMaster(_ percent: Int) async {
        let current = masterVolume
        let delta = percent - current
        if let left {
            await setVolume(left, percent: min(100, max(0, left.volume + delta)))
        }
        if let right {
            await setVolume(right, percent: min(100, max(0, right.volume + delta)))
        }
    }

    func setLatency(_ side: ChannelStatus, milliseconds: Int) async {
        do {
            _ = try await Task.detached {
                try UnixControlClient(socketURL: self.socketURL)
                    .send(.setClientLatency(
                        requestId: UUID().uuidString,
                        clientId: side.clientId,
                        milliseconds: milliseconds
                    ))
            }.value
            await refresh()
        } catch {
            message = error.localizedDescription
        }
    }

    func setMute(_ side: ChannelStatus, muted: Bool) async {
        do {
            _ = try await Task.detached {
                try UnixControlClient(socketURL: self.socketURL)
                    .send(.setClientMute(
                        requestId: UUID().uuidString,
                        clientId: side.clientId,
                        muted: muted
                    ))
            }.value
            await refresh()
        } catch {
            message = error.localizedDescription
        }
    }
}
