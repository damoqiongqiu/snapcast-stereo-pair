import Darwin
import Foundation

public let nativeRuntimeVersion = "0.2.0"

public struct DiagnosticsReport: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var runtimeVersion: String
    public var protocolVersion: Int
    public var mode: AudioMode
    public var health: HealthLevel
    public var services: [ServiceStatus]
    public var channels: [ChannelStatus]
    public var streams: [StreamStatus]
    public var issues: [String]

    public init(
        schemaVersion: Int,
        generatedAt: Date,
        runtimeVersion: String,
        protocolVersion: Int,
        mode: AudioMode,
        health: HealthLevel,
        services: [ServiceStatus],
        channels: [ChannelStatus],
        streams: [StreamStatus],
        issues: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.runtimeVersion = runtimeVersion
        self.protocolVersion = protocolVersion
        self.mode = mode
        self.health = health
        self.services = services
        self.channels = channels
        self.streams = streams
        self.issues = issues
    }
}

public enum DiagnosticsBuilder {
    public static func make(
        snapshot: RuntimeSnapshot,
        runtimeVersion: String = nativeRuntimeVersion,
        redacted: Bool,
        generatedAt: Date = Date()
    ) -> DiagnosticsReport {
        let services = snapshot.services.map { service in
            var service = service
            if redacted {
                service.message = service.message.map(DiagnosticsRedactor.redact)
            }
            return service
        }
        let issues = redacted ? snapshot.issues.map(DiagnosticsRedactor.redact) : snapshot.issues
        return DiagnosticsReport(
            schemaVersion: 1,
            generatedAt: generatedAt,
            runtimeVersion: runtimeVersion,
            protocolVersion: snapshot.protocolVersion,
            mode: snapshot.mode,
            health: snapshot.health,
            services: services,
            channels: snapshot.channels,
            streams: snapshot.streams,
            issues: issues
        )
    }
}

public enum DiagnosticsRedactor {
    public static func redact(_ value: String) -> String {
        var result = value
        let replacements: [(String, String)] = [
            (#"/Users/[^\n"]+"#, "<redacted-path>"),
            (#"\b[A-Za-z0-9._-]+@[A-Za-z0-9.-]+\b"#, "<redacted>"),
            (#"\b(?:\d{1,3}\.){3}\d{1,3}\b"#, "<redacted-address>"),
            (#"\b[0-9a-fA-F]{32,}\b"#, "<redacted-token>")
        ]
        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        return result
    }
}

public enum ServiceMaintenance {
    public static func restartArguments(serviceId: String) -> [String]? {
        guard LocalHealthReader.localServices.contains(where: { $0.label == serviceId }) else {
            return nil
        }
        return ["kickstart", "-k", "gui/\(getuid())/\(serviceId)"]
    }
}
