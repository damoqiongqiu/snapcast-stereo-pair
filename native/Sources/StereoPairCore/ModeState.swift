import Foundation

public enum PersistedAudioModeReader {
    public static func read(
        supportDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Snapcast")
    ) -> AudioMode? {
        let url = supportDirectory.appendingPathComponent("state/audio-mode.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawMode = object["mode"] as? String,
              let mode = AudioMode(rawValue: rawMode),
              mode != .transitioning else {
            return nil
        }
        return mode
    }
}

public enum SystemModeSnapshotNormalizer {
    public static func normalize(
        _ snapshot: RuntimeSnapshot,
        persistedMode: AudioMode?
    ) -> RuntimeSnapshot {
        guard persistedMode == .system else { return snapshot }

        var normalized = snapshot
        normalized.mode = .system
        normalized.channels = []
        normalized.streams = []
        normalized.services = snapshot.services.map { service in
            guard service.state != .running && service.state != .crashLoop else {
                return service
            }
            var disabled = service
            disabled.state = .disabled
            disabled.pid = nil
            disabled.message = nil
            return disabled
        }

        let unexpectedRunning = normalized.services.contains {
            $0.state == .running || $0.state == .crashLoop
        }
        if unexpectedRunning {
            normalized.health = .degraded
            normalized.issues = ["Runtime services are unexpectedly running in system mode"]
        } else {
            normalized.health = .disabled
            normalized.issues = []
        }
        return normalized
    }
}
