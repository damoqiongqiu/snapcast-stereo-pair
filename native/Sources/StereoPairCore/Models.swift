import Foundation

public enum AudioMode: String, Codable, Sendable {
    case snapcast
    case system
    case transitioning
}

public enum HealthLevel: String, Codable, Sendable {
    case healthy
    case degraded
    case failed
    case disabled
}

public enum ServiceState: String, Codable, Sendable {
    case running
    case inactive
    case failed
    case crashLoop
    case disabled
    case unknown
}

public struct ServiceStatus: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var state: ServiceState
    public var pid: Int?
    public var runs: Int
    public var lastExitCode: Int?
    public var lastSuccessAgeSeconds: Double?
    public var message: String?

    public init(
        id: String,
        displayName: String,
        state: ServiceState,
        pid: Int?,
        runs: Int,
        lastExitCode: Int?,
        lastSuccessAgeSeconds: Double?,
        message: String?
    ) {
        self.id = id
        self.displayName = displayName
        self.state = state
        self.pid = pid
        self.runs = runs
        self.lastExitCode = lastExitCode
        self.lastSuccessAgeSeconds = lastSuccessAgeSeconds
        self.message = message
    }
}

public struct ChannelStatus: Codable, Equatable, Sendable {
    public var side: String
    public var clientId: String
    public var streamId: String
    public var connected: Bool
    public var deviceName: String?
    public var volume: Int
    public var muted: Bool
    public var latencyMs: Int
    public var peakDb: Double?
    public var rmsDb: Double?
    public var clipped: Bool

    public init(
        side: String,
        clientId: String,
        streamId: String,
        connected: Bool,
        deviceName: String?,
        volume: Int,
        muted: Bool,
        latencyMs: Int,
        peakDb: Double?,
        rmsDb: Double?,
        clipped: Bool
    ) {
        self.side = side
        self.clientId = clientId
        self.streamId = streamId
        self.connected = connected
        self.deviceName = deviceName
        self.volume = volume
        self.muted = muted
        self.latencyMs = latencyMs
        self.peakDb = peakDb
        self.rmsDb = rmsDb
        self.clipped = clipped
    }
}

public struct StreamStatus: Codable, Equatable, Sendable {
    public var id: String
    public var state: String
    public var sampleFormat: String?
    public var clientIds: [String]

    public init(
        id: String,
        state: String,
        sampleFormat: String?,
        clientIds: [String]
    ) {
        self.id = id
        self.state = state
        self.sampleFormat = sampleFormat
        self.clientIds = clientIds
    }
}

public struct HardwareVolumeStatus: Codable, Equatable, Sendable {
    public var side: String
    public var volumePercent: Double?
    public var checkedAt: Date?
    public var error: String?

    public init(
        side: String,
        volumePercent: Double?,
        checkedAt: Date?,
        error: String?
    ) {
        self.side = side
        self.volumePercent = volumePercent
        self.checkedAt = checkedAt
        self.error = error
    }
}

public struct RuntimeSnapshot: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var mode: AudioMode
    public var health: HealthLevel
    public var services: [ServiceStatus]
    public var channels: [ChannelStatus]
    public var streams: [StreamStatus]
    public var hardwareVolumes: [HardwareVolumeStatus]
    public var issues: [String]
    public var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case mode
        case health
        case services
        case channels
        case streams
        case hardwareVolumes
        case issues
        case updatedAt
    }

    public init(
        protocolVersion: Int,
        mode: AudioMode,
        health: HealthLevel,
        services: [ServiceStatus],
        channels: [ChannelStatus],
        streams: [StreamStatus],
        hardwareVolumes: [HardwareVolumeStatus] = [],
        issues: [String],
        updatedAt: Date
    ) {
        self.protocolVersion = protocolVersion
        self.mode = mode
        self.health = health
        self.services = services
        self.channels = channels
        self.streams = streams
        self.hardwareVolumes = hardwareVolumes
        self.issues = issues
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
        mode = try container.decode(AudioMode.self, forKey: .mode)
        health = try container.decode(HealthLevel.self, forKey: .health)
        services = try container.decode([ServiceStatus].self, forKey: .services)
        channels = try container.decode([ChannelStatus].self, forKey: .channels)
        streams = try container.decode([StreamStatus].self, forKey: .streams)
        hardwareVolumes = try container.decodeIfPresent(
            [HardwareVolumeStatus].self,
            forKey: .hardwareVolumes
        ) ?? []
        issues = try container.decode([String].self, forKey: .issues)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
