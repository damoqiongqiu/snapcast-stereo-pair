import Foundation

public enum LaunchdParser {
    public static func parse(
        label: String,
        displayName: String,
        output: String
    ) throws -> ServiceStatus {
        func value(_ key: String) -> String? {
            output.split(separator: "\n").compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("\(key) = ") else { return nil }
                return String(trimmed.dropFirst(key.count + 3))
            }.first
        }

        let rawState = value("state") ?? "unknown"
        let state: ServiceState =
            switch rawState {
            case "running": .running
            case "not running": .inactive
            default: .unknown
            }
        let pid = value("pid").flatMap(Int.init)
        let runs = value("runs").flatMap(Int.init) ?? 0
        let rawExit = value("last exit code")
        let exitCode = rawExit == "(never exited)" ? nil : rawExit.flatMap(Int.init)
        return ServiceStatus(
            id: label,
            displayName: displayName,
            state: state,
            pid: pid,
            runs: runs,
            lastExitCode: exitCode,
            lastSuccessAgeSeconds: nil,
            message: nil
        )
    }
}
