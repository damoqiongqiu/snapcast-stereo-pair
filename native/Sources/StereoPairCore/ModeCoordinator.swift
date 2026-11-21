import Foundation

public enum ModeCoordinatorError: Error {
    case invalidMode
    case localFailure(Int32, String)
}

public struct ModeTransitionResult: Codable, Equatable, Sendable {
    public var mode: AudioMode
    public var remoteWarning: String?

    public init(mode: AudioMode, remoteWarning: String?) {
        self.mode = mode
        self.remoteWarning = remoteWarning
    }
}

public actor ModeCoordinator {
    private struct RemoteConfiguration: Decodable {
        let user: String
        let host: String
        let helperPath: String
    }

    private let runner: any CommandRunning
    private let supportDirectory: URL

    public init(
        runner: any CommandRunning = SystemCommandRunner(),
        supportDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Snapcast")
    ) {
        self.runner = runner
        self.supportDirectory = supportDirectory
    }

    public func setMode(_ mode: AudioMode) async throws -> ModeTransitionResult {
        guard mode != .transitioning else {
            throw ModeCoordinatorError.invalidMode
        }
        let scriptMode = mode == .snapcast ? "snapcast" : "native"
        let local = try await runner.run(
            executable: "/bin/zsh",
            arguments: [supportDirectory.appendingPathComponent("set-mode.sh").path, scriptMode],
            environment: [:],
            timeout: 30
        )
        guard local.status == 0 else {
            throw ModeCoordinatorError.localFailure(local.status, local.stderr)
        }

        let warning = await applyRemoteModeBestEffort(mode: mode)
        try writeModeMarker(mode)
        return ModeTransitionResult(mode: mode, remoteWarning: warning)
    }

    private func applyRemoteModeBestEffort(mode: AudioMode) async -> String? {
        let configURL = supportDirectory.appendingPathComponent("state/remote-control.json")
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(RemoteConfiguration.self, from: data) else {
            return "Remote control is not configured"
        }
        do {
            let result = try await runner.run(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=3",
                    "-o", "ServerAliveInterval=2",
                    "-o", "ServerAliveCountMax=2",
                    "\(config.user)@\(config.host)",
                    "/bin/zsh", config.helperPath, mode.rawValue
                ],
                environment: [:],
                timeout: 8
            )
            return result.status == 0 ? nil : "Remote mode change failed: SSH exit \(result.status)"
        } catch {
            return "Remote mode change failed: \(error.localizedDescription)"
        }
    }

    private func writeModeMarker(_ mode: AudioMode) throws {
        let stateDirectory = supportDirectory.appendingPathComponent("state", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode([
            "mode": mode.rawValue,
            "updatedAt": ISO8601DateFormatter().string(from: Date())
        ])
        try data.write(to: stateDirectory.appendingPathComponent("audio-mode.json"), options: .atomic)
    }
}
