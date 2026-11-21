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
    case .setAudioMode(_, let mode):
        return .error(
            requestId: requestID(for: request),
            message: "Audio mode transition is provided by the mode coordinator: \(mode.rawValue)"
        )
    case .restartPair, .setClientVolume, .setClientMute, .setClientLatency, .exportDiagnostics:
        return .error(requestId: requestID(for: request), message: "Command is not available in this build")
    }
}

try server.start()
Task {
    while !Task.isCancelled {
        await updateSnapshot()
        try? await Task.sleep(for: .seconds(1))
    }
}
dispatchMain()
