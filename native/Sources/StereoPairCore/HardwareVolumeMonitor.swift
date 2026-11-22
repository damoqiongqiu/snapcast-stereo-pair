import Foundation

public actor HardwareVolumeMonitor {
    private typealias Measurement = (volume: Double?, error: String?)

    private struct DeviceConfiguration: Decodable {
        let localOutputUID: String
        let remoteOutputUID: String
        let leftIsRemote: Bool
    }

    private struct RemoteConfiguration: Decodable {
        let user: String
        let host: String
        let volumeReaderPath: String?
    }

    private let supportDirectory: URL
    private let runner: any CommandRunning
    private let fileManager: FileManager

    public init(
        supportDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Snapcast"),
        runner: any CommandRunning = SystemCommandRunner(),
        fileManager: FileManager = .default
    ) {
        self.supportDirectory = supportDirectory
        self.runner = runner
        self.fileManager = fileManager
    }

    public func cached() -> [HardwareVolumeStatus] {
        loadCache()
    }

    public func refresh(includeRemote: Bool = true) async -> [HardwareVolumeStatus] {
        let previous = Dictionary(uniqueKeysWithValues: loadCache().map { ($0.side, $0) })
        guard let devices = loadDevices() else {
            return unavailableStatuses(
                error: "Hardware volume configuration is unavailable",
                previous: previous
            )
        }

        async let localTask = readLocalVolume(uid: devices.localOutputUID)
        let remoteMeasurement: Measurement? =
            if includeRemote {
                if let remote = loadRemote() {
                    await readRemoteVolume(configuration: remote, uid: devices.remoteOutputUID)
                } else {
                    (nil, "Remote system volume configuration is unavailable")
                }
            } else {
                nil
            }
        let localMeasurement = await localTask

        let localSide = devices.leftIsRemote ? "right" : "left"
        let remoteSide = devices.leftIsRemote ? "left" : "right"
        let localStatus = status(
            side: localSide,
            measurement: localMeasurement,
            previous: previous[localSide]
        )
        let remoteStatus: HardwareVolumeStatus
        if let remoteMeasurement {
            remoteStatus = status(
                side: remoteSide,
                measurement: remoteMeasurement,
                previous: previous[remoteSide]
            )
        } else if let cached = previous[remoteSide] {
            remoteStatus = cached
        } else {
            remoteStatus = HardwareVolumeStatus(
                side: remoteSide,
                volumePercent: nil,
                checkedAt: nil,
                error: "Remote system volume has not been read"
            )
        }
        let statuses = [remoteStatus, localStatus].sorted { $0.side < $1.side }
        writeCache(statuses)
        return statuses
    }

    private func status(
        side: String,
        measurement: Measurement,
        previous: HardwareVolumeStatus?
    ) -> HardwareVolumeStatus {
        if let volume = measurement.volume {
            return HardwareVolumeStatus(
                side: side,
                volumePercent: volume,
                checkedAt: Date(),
                error: measurement.error
            )
        }
        if let previous, let volume = previous.volumePercent {
            return HardwareVolumeStatus(
                side: side,
                volumePercent: volume,
                checkedAt: previous.checkedAt,
                error: measurement.error
            )
        }
        return HardwareVolumeStatus(
            side: side,
            volumePercent: nil,
            checkedAt: nil,
            error: measurement.error
        )
    }

    private func readLocalVolume(uid: String) async -> Measurement {
        do {
            let result = try await runner.run(
                executable: supportDirectory.appendingPathComponent("bin/set-audio-volume").path,
                arguments: ["get", uid],
                environment: [:],
                timeout: 2
            )
            return parseVolume(result)
        } catch {
            return (nil, "Local system volume is unavailable")
        }
    }

    private func readRemoteVolume(
        configuration: RemoteConfiguration,
        uid: String
    ) async -> Measurement {
        guard let readerPath = configuration.volumeReaderPath else {
            return (nil, "Remote system volume reader is not configured")
        }
        do {
            let result = try await runner.run(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=3",
                    "-o", "ServerAliveInterval=2",
                    "-o", "ServerAliveCountMax=2",
                    "\(configuration.user)@\(configuration.host)",
                    readerPath,
                    "get",
                    uid
                ],
                environment: [:],
                timeout: 8
            )
            return parseVolume(result)
        } catch {
            return (nil, "Remote system volume is unavailable")
        }
    }

    private func parseVolume(_ result: CommandResult) -> Measurement {
        guard result.status == 0 else {
            return (nil, "System volume read failed")
        }
        let value = result.stdout
            .split(separator: "\n")
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value,
              let volume = Double(value),
              (0...100).contains(volume) else {
            return (nil, "System volume response is invalid")
        }
        return (volume, nil)
    }

    private func unavailableStatuses(
        error: String,
        previous: [String: HardwareVolumeStatus]
    ) -> [HardwareVolumeStatus] {
        [
            previous["left"].map {
                HardwareVolumeStatus(
                    side: $0.side,
                    volumePercent: $0.volumePercent,
                    checkedAt: $0.checkedAt,
                    error: error
                )
            } ?? HardwareVolumeStatus(
                side: "left",
                volumePercent: nil,
                checkedAt: nil,
                error: error
            ),
            previous["right"].map {
                HardwareVolumeStatus(
                    side: $0.side,
                    volumePercent: $0.volumePercent,
                    checkedAt: $0.checkedAt,
                    error: error
                )
            } ?? HardwareVolumeStatus(
                side: "right",
                volumePercent: nil,
                checkedAt: nil,
                error: error
            )
        ]
    }

    private func loadDevices() -> DeviceConfiguration? {
        decode(
            DeviceConfiguration.self,
            from: supportDirectory.appendingPathComponent("state/audio-devices.json")
        )
    }

    private func loadRemote() -> RemoteConfiguration? {
        decode(
            RemoteConfiguration.self,
            from: supportDirectory.appendingPathComponent("state/remote-control.json")
        )
    }

    private func loadCache() -> [HardwareVolumeStatus] {
        let url = supportDirectory.appendingPathComponent("state/hardware-volume-cache.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HardwareVolumeStatus].self, from: data)) ?? []
    }

    private func writeCache(_ statuses: [HardwareVolumeStatus]) {
        let directory = supportDirectory.appendingPathComponent("state", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(statuses)
            let temporary = directory.appendingPathComponent(".hardware-volume.\(UUID().uuidString)")
            try data.write(to: temporary, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            let destination = directory.appendingPathComponent("hardware-volume-cache.json")
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temporary, to: destination)
        } catch {
            return
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
