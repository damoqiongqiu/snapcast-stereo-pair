import Foundation

public actor AgentRuntime {
    private let healthReader: LocalHealthReader
    private let snapserver: SnapserverClient
    private let metricsReader: MetricsReader
    private let supportDirectory: URL
    private var stabilizer = SnapshotStabilizer()

    public init(
        healthReader: LocalHealthReader = LocalHealthReader(),
        snapserver: SnapserverClient = SnapserverClient(),
        metricsReader: MetricsReader = MetricsReader(),
        supportDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Snapcast")
    ) {
        self.healthReader = healthReader
        self.snapserver = snapserver
        self.metricsReader = metricsReader
        self.supportDirectory = supportDirectory
    }

    public func snapshot() async -> RuntimeSnapshot {
        let candidate = await candidateSnapshot()
        let normalized = SystemModeSnapshotNormalizer.normalize(
            candidate,
            persistedMode: PersistedAudioModeReader.read(supportDirectory: supportDirectory)
        )
        return stabilizer.stabilize(normalized)
    }

    private func candidateSnapshot() async -> RuntimeSnapshot {
        async let servicesTask = healthReader.readServices()
        let services = await servicesTask
        let metrics = metricsReader.read()

        do {
            let status = try await snapserver.getStatus()
            let channels = status.channels.map { channel in
                var channel = channel
                if let metrics {
                    channel.peakDb = channel.side == "left" ? metrics.leftPeakDb : metrics.rightPeakDb
                    channel.rmsDb = channel.side == "left" ? metrics.leftRmsDb : metrics.rightRmsDb
                    channel.clipped = channel.side == "left" ? metrics.leftClipped : metrics.rightClipped
                }
                return channel
            }
            let running = services.filter { $0.state == .running }.count
            let mode: AudioMode = running > 0 ? .snapcast : .system
            let health: HealthLevel =
                if services.contains(where: { $0.state == .failed || $0.state == .crashLoop }) || !status.healthIssues.isEmpty {
                    .degraded
                } else {
                    .healthy
                }
            return RuntimeSnapshot(
                protocolVersion: controlProtocolVersion,
                mode: mode,
                health: health,
                services: services,
                channels: channels,
                streams: status.streams,
                issues: status.healthIssues,
                updatedAt: Date()
            )
        } catch {
            let running = services.filter { $0.state == .running }.count
            let mode: AudioMode = running > 0 ? .snapcast : .disabledMode
            return RuntimeSnapshot(
                protocolVersion: controlProtocolVersion,
                mode: mode,
                health: running > 0 ? .failed : .disabled,
                services: services,
                channels: [],
                streams: [],
                issues: ["Snapserver control API is unavailable"],
                updatedAt: Date()
            )
        }
    }

    public func liveMetrics() -> AudioMetricsSnapshot? {
        metricsReader.read()
    }
}

private extension AudioMode {
    static var disabledMode: AudioMode { .system }
}
