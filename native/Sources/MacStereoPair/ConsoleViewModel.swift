import Foundation
import StereoPairCore

@MainActor
final class ConsoleViewModel: ObservableObject {
    @Published var snapshot: RuntimeSnapshot?
    @Published var isWorking = false
    @Published var message: String?
    @Published private(set) var isRefreshingHardwareVolume = false
    @Published private(set) var connectionState: AgentConnectionState = .failed

    private let transport: any ControlTransport
    private var pollingTask: Task<Void, Never>?
    private var refreshGeneration = 0

    init(transport: (any ControlTransport)? = nil) {
        self.transport = transport ?? UnixControlTransport(
            socketURL: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Snapcast/run/control.sock")
        )
    }

    var left: ChannelStatus? { snapshot?.channels.first { $0.streamId == "LeftAudio" } }
    var right: ChannelStatus? { snapshot?.channels.first { $0.streamId == "RightAudio" } }
    var masterVolume: Int {
        guard left != nil || right != nil else { return 0 }
        return Int((((left?.volume ?? 0) + (right?.volume ?? 0))) / 2)
    }
    var isSnapcast: Bool { snapshot?.mode == .snapcast }
    var healthy: Bool { snapshot?.health == .healthy }
    var canChangeMode: Bool { !isWorking && snapshot?.mode != .transitioning }
    var showsTransition: Bool { isWorking || snapshot?.mode == .transitioning }
    var showsWarning: Bool {
        guard let snapshot else { return true }
        return snapshot.health == .degraded ||
            snapshot.health == .failed ||
            !snapshot.issues.isEmpty
    }
    var showsChannelControls: Bool { true }

    func hardwareVolume(side: String) -> HardwareVolumeStatus? {
        snapshot?.hardwareVolumes.first { $0.side == side }
    }

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
        refreshGeneration &+= 1
        let generation = refreshGeneration
        do {
            let event = try await transport.request(.snapshot(requestId: UUID().uuidString))
            guard generation == refreshGeneration else { return }
            if case .snapshot(let value) = event {
                apply(snapshot: value)
                connectionState = .connected
                message = nil
            }
        } catch {
            guard generation == refreshGeneration else { return }
            connectionState = .failed
            message = error.localizedDescription
        }
    }

    func apply(snapshot value: RuntimeSnapshot) {
        snapshot = value
    }

    func setMode(_ mode: AudioMode) async {
        guard canChangeMode else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let event = try await transport.request(
                .setAudioMode(requestId: UUID().uuidString, audioMode: mode)
            )
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
            _ = try await transport.request(.setClientVolume(
                requestId: UUID().uuidString,
                clientId: side.clientId,
                percent: percent
            ))
            await refresh()
        } catch {
            connectionState = .failed
            message = error.localizedDescription
        }
    }

    func setMaster(_ percent: Int) async {
        let current = masterVolume
        let delta = percent - current
        let leftTarget = left.map { min(100, max(0, $0.volume + delta)) }
        let rightTarget = right.map { min(100, max(0, $0.volume + delta)) }
        do {
            if let left, let leftTarget {
                _ = try await transport.request(.setClientVolume(
                    requestId: UUID().uuidString,
                    clientId: left.clientId,
                    percent: leftTarget
                ))
            }
            if let right, let rightTarget {
                _ = try await transport.request(.setClientVolume(
                    requestId: UUID().uuidString,
                    clientId: right.clientId,
                    percent: rightTarget
                ))
            }
            await refresh()
        } catch {
            connectionState = .failed
            message = error.localizedDescription
        }
    }

    func setLatency(_ side: ChannelStatus, milliseconds: Int) async {
        do {
            _ = try await transport.request(.setClientLatency(
                requestId: UUID().uuidString,
                clientId: side.clientId,
                milliseconds: min(500, max(0, milliseconds))
            ))
            await refresh()
        } catch {
            connectionState = .failed
            message = error.localizedDescription
        }
    }

    func setMute(_ side: ChannelStatus, muted: Bool) async {
        do {
            _ = try await transport.request(.setClientMute(
                requestId: UUID().uuidString,
                clientId: side.clientId,
                muted: muted
            ))
            await refresh()
        } catch {
            connectionState = .failed
            message = error.localizedDescription
        }
    }

    func refreshHardwareVolumes() async {
        guard !isRefreshingHardwareVolume else { return }
        isRefreshingHardwareVolume = true
        defer { isRefreshingHardwareVolume = false }
        do {
            let event = try await transport.request(
                .refreshHardwareVolume(requestId: UUID().uuidString)
            )
            if case .error(_, let error) = event {
                message = error
                return
            }
            await refresh()
        } catch {
            connectionState = .failed
            message = error.localizedDescription
        }
    }

    func exportDiagnostics(redacted: Bool = true) async -> String? {
        do {
            let event = try await transport.request(.exportDiagnostics(
                requestId: UUID().uuidString,
                redacted: redacted
            ))
            switch event {
            case .diagnostics(_, let json):
                return json
            case .error(_, let message):
                self.message = message
            default:
                message = "The Agent returned an unexpected diagnostics response."
            }
        } catch {
            connectionState = .failed
            message = error.localizedDescription
        }
        return nil
    }

    func restartService(id: String) async {
        do {
            let event = try await transport.request(.restartService(
                requestId: UUID().uuidString,
                serviceId: id
            ))
            if case .error(_, let message) = event {
                self.message = message
            } else {
                await refresh()
            }
        } catch {
            connectionState = .failed
            message = error.localizedDescription
        }
    }
}
