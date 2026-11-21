import Foundation

public struct ServiceDefinition: Sendable {
    public let label: String
    public let displayName: String
    public let requiredInSnapcastMode: Bool

    public init(label: String, displayName: String, requiredInSnapcastMode: Bool) {
        self.label = label
        self.displayName = displayName
        self.requiredInSnapcastMode = requiredInSnapcastMode
    }
}

public struct HealthMarker: Codable, Equatable, Sendable {
    public var completedAt: Date
    public var success: Bool
    public var exitCode: Int?
    public var message: String?

    public init(completedAt: Date, success: Bool, exitCode: Int?, message: String?) {
        self.completedAt = completedAt
        self.success = success
        self.exitCode = exitCode
        self.message = message
    }
}

public struct LocalHealthReader: Sendable {
    public static let localServices: [ServiceDefinition] = [
        .init(label: "com.snapcast.server", displayName: "Snapserver", requiredInSnapcastMode: true),
        .init(label: "com.snapcast.splitter", displayName: "Splitter", requiredInSnapcastMode: true),
        .init(label: "com.snapcast.local-client", displayName: "Local Client", requiredInSnapcastMode: true),
        .init(label: "com.snapcast.pairing", displayName: "Automatic Pairing", requiredInSnapcastMode: true),
        .init(label: "com.snapcast.wake-recovery", displayName: "Wake Recovery", requiredInSnapcastMode: true)
    ]

    private let runner: any CommandRunning
    private let stateDirectory: URL

    public init(
        runner: any CommandRunning = SystemCommandRunner(),
        stateDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Snapcast/state")
    ) {
        self.runner = runner
        self.stateDirectory = stateDirectory
    }

    public func readServices() async -> [ServiceStatus] {
        var services: [ServiceStatus] = []
        for definition in Self.localServices {
            do {
                let result = try await runner.run(
                    executable: "/bin/launchctl",
                    arguments: ["print", "gui/\(getuid())/\(definition.label)"],
                    environment: [:],
                    timeout: 2
                )
                if result.status == 0 {
                    var service = try LaunchdParser.parse(
                        label: definition.label,
                        displayName: definition.displayName,
                        output: result.stdout
                    )
                    attachMarker(to: &service)
                    services.append(service)
                } else {
                    services.append(ServiceStatus(
                        id: definition.label,
                        displayName: definition.displayName,
                        state: .failed,
                        pid: nil,
                        runs: 0,
                        lastExitCode: Int(result.status),
                        lastSuccessAgeSeconds: nil,
                        message: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                }
            } catch {
                services.append(ServiceStatus(
                    id: definition.label,
                    displayName: definition.displayName,
                    state: .unknown,
                    pid: nil,
                    runs: 0,
                    lastExitCode: nil,
                    lastSuccessAgeSeconds: nil,
                    message: String(describing: error)
                ))
            }
        }
        return services
    }

    private func attachMarker(to service: inout ServiceStatus) {
        let fileName: String?
        switch service.id {
        case "com.snapcast.pairing": fileName = "pairing.json"
        case "com.snapcast.wake-recovery": fileName = "wake-local.json"
        default: fileName = nil
        }
        guard let fileName else { return }
        let url = stateDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let marker = try? JSONDecoder.health.decode(HealthMarker.self, from: data) else {
            return
        }
        service.lastSuccessAgeSeconds = max(0, Date().timeIntervalSince(marker.completedAt))
        service.message = marker.message
        if !marker.success && (service.state == .inactive || service.state == .unknown) {
            service.state = .failed
        }
    }
}

private extension JSONDecoder {
    static var health: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
