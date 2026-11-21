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
        snapshot.channels = snapshot.channels.map { channel in
            var channel = channel
            channel.peakDb = channel.side == "left" ? metrics.leftPeakDb : metrics.rightPeakDb
            channel.rmsDb = channel.side == "left" ? metrics.leftRmsDb : metrics.rightRmsDb
            channel.clipped = channel.side == "left" ? metrics.leftClipped : metrics.rightClipped
            return channel
        }
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
         .exportDiagnostics(let id, _):
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
    case .exportDiagnostics(let requestId, _):
        return .error(requestId: requestId, message: "Diagnostics export is not available in this build")
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
        if let metrics = runtime.liveMetrics() {
            store.merge(metrics: metrics)
        }
        try? await Task.sleep(for: .milliseconds(50))
    }
}
dispatchMain()
