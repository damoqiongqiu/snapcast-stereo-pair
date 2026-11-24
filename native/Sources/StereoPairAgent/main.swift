import Foundation
import StereoPairCore

let socketURL =
    if let override = ProcessInfo.processInfo.environment["SNAPCAST_CONTROL_SOCKET"] {
        URL(fileURLWithPath: override)
    } else {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Snapcast/run/control.sock")
    }
let runtime = AgentRuntime()
let modeCoordinator = ModeCoordinator()
let snapserver = SnapserverClient()
let commandRunner = SystemCommandRunner()

final class SnapshotStore: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot = RuntimeSnapshot(
        protocolVersion: controlProtocolVersion,
        mode: .transitioning,
        health: .disabled,
        services: [],
        channels: [],
        streams: [],
        issues: ["Agent starting"],
        updatedAt: Date()
    )

    func set(_ value: RuntimeSnapshot) {
        lock.lock()
        snapshot = value
        lock.unlock()
    }

    func get() -> RuntimeSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    func merge(metrics: AudioMetricsSnapshot) {
        lock.lock()
        snapshot.channels = ChannelMetricsApplication.apply(metrics, to: snapshot.channels)
        lock.unlock()
    }
}

let store = SnapshotStore()

func updateSnapshot() async {
    let snapshot = await runtime.snapshot()
    store.set(snapshot)
}

func cachedSnapshot() -> RuntimeSnapshot {
    store.get()
}

func requestID(for request: ControlRequest) -> String {
    switch request {
    case .snapshot(let id), .subscribe(let id), .setAudioMode(let id, _), .restartPair(let id),
         .setClientVolume(let id, _, _), .setClientMute(let id, _, _), .setClientLatency(let id, _, _),
         .refreshHardwareVolume(let id), .restartService(let id, _), .exportDiagnostics(let id, _):
        id
    }
}

let server = UnixControlServer(socketURL: socketURL) { request in
    switch request {
    case .snapshot, .subscribe:
        return .snapshot(cachedSnapshot())
    case .setAudioMode(let requestId, let mode):
        do {
            let result = try await modeCoordinator.setMode(mode)
            await updateSnapshot()
            return .modeChanged(requestId: requestId, result: result)
        } catch {
            return .error(requestId: requestId, message: error.localizedDescription)
        }
    case .restartPair(let requestId):
        do {
            let result = try await modeCoordinator.setMode(.snapcast)
            await updateSnapshot()
            return .modeChanged(requestId: requestId, result: result)
        } catch {
            return .error(requestId: requestId, message: error.localizedDescription)
        }
    case .setClientVolume(let requestId, let clientId, let percent):
        do {
            try await snapserver.setVolume(clientId: clientId, percent: percent)
            await updateSnapshot()
            return .success(requestId: requestId)
        } catch {
            return .error(requestId: requestId, message: error.localizedDescription)
        }
    case .setClientMute(let requestId, let clientId, let muted):
        do {
            try await snapserver.setMute(clientId: clientId, muted: muted)
            await updateSnapshot()
            return .success(requestId: requestId)
        } catch {
            return .error(requestId: requestId, message: error.localizedDescription)
        }
    case .setClientLatency(let requestId, let clientId, let milliseconds):
        do {
            try await snapserver.setLatency(clientId: clientId, milliseconds: milliseconds)
            await updateSnapshot()
            return .success(requestId: requestId)
        } catch {
            return .error(requestId: requestId, message: error.localizedDescription)
        }
    case .refreshHardwareVolume(let requestId):
        await runtime.refreshHardwareVolumes()
        await updateSnapshot()
        return .success(requestId: requestId)
    case .restartService(let requestId, let serviceId):
        guard let arguments = ServiceMaintenance.restartArguments(serviceId: serviceId) else {
            return .error(requestId: requestId, message: "Unknown runtime service")
        }
        do {
            let result = try await commandRunner.run(
                executable: "/bin/launchctl",
                arguments: arguments,
                environment: [:],
                timeout: 5
            )
            guard result.status == 0 else {
                return .error(
                    requestId: requestId,
                    message: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            await updateSnapshot()
            return .success(requestId: requestId)
        } catch {
            return .error(requestId: requestId, message: error.localizedDescription)
        }
    case .exportDiagnostics(let requestId, let redacted):
        let report = DiagnosticsBuilder.make(snapshot: cachedSnapshot(), redacted: redacted)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(report)
            return .diagnostics(
                requestId: requestId,
                json: String(decoding: data, as: UTF8.self)
            )
        } catch {
            return .error(requestId: requestId, message: error.localizedDescription)
        }
    }
}

try server.start()
Task {
    while !Task.isCancelled {
        await updateSnapshot()
        try? await Task.sleep(for: .seconds(1))
    }
}
Task {
    while !Task.isCancelled {
        if let metrics = await runtime.liveMetrics() {
            store.merge(metrics: metrics)
        }
        try? await Task.sleep(for: AudioMetricsSamplingPolicy.interval)
    }
}
Task {
    await runtime.refreshHardwareVolumes()
    var secondsSinceRemoteRefresh = 0
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        secondsSinceRemoteRefresh += 2
        let includeRemote = secondsSinceRemoteRefresh >= 30
        if includeRemote {
            secondsSinceRemoteRefresh = 0
        }
        await runtime.refreshHardwareVolumes(includeRemote: includeRemote)
    }
}
dispatchMain()
