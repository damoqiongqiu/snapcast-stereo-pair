import Foundation

public enum TerminalLauncherError: Error {
    case couldNotCreateScript
    case couldNotLaunchTerminal
}

public struct TerminalScriptBuilder {
    public static func writeScript(
        action: SetupAction,
        helperURL: URL,
        supportDirectory: URL
    ) throws -> URL {
        let scriptsDirectory = supportDirectory.appendingPathComponent("setup", isDirectory: true)
        try FileManager.default.createDirectory(
            at: scriptsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let scriptURL = scriptsDirectory
            .appendingPathComponent("stereo-pair-setup-\(UUID().uuidString).command")
        let command = ([helperURL.path] + action.arguments)
            .map(shellQuote)
            .joined(separator: " ")
        let script = """
        #!/bin/zsh
        set -euo pipefail
        /bin/zsh \(command)
        """
        guard FileManager.default.createFile(
            atPath: scriptURL.path,
            contents: Data(script.utf8),
            attributes: [.posixPermissions: 0o700]
        ) else {
            throw TerminalLauncherError.couldNotCreateScript
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: scriptURL.path
        )
        return scriptURL
    }

    public static func removeExpiredScripts(
        in supportDirectory: URL,
        olderThan interval: TimeInterval = 24 * 60 * 60,
        now: Date = Date()
    ) {
        let directory = supportDirectory.appendingPathComponent("setup", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return
        }
        for url in urls {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let modified, now.timeIntervalSince(modified) > interval {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

public struct TerminalLauncher {
    public init() {}

    public func open(_ scriptURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", scriptURL.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw TerminalLauncherError.couldNotLaunchTerminal
        }
        guard process.terminationStatus == 0 else {
            throw TerminalLauncherError.couldNotLaunchTerminal
        }
    }
}
