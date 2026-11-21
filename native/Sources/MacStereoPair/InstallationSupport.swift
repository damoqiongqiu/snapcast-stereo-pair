import Foundation
import StereoPairCore

enum InstallationSupport {
    static func helperURL(
        supportDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Snapcast")
    ) throws -> URL {
        let candidates = [
            ProcessInfo.processInfo.environment["SNAPCAST_SETUP_HELPER"],
            supportDirectory.appendingPathComponent("setup/native-setup-helper.sh").path,
            supportDirectory.appendingPathComponent("bin/native-setup-helper.sh").path,
            "/opt/homebrew/share/macbook-stereo-pair/integration/scripts/native-setup-helper.sh",
            "/usr/local/share/macbook-stereo-pair/integration/scripts/native-setup-helper.sh"
        ].compactMap { $0 }
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }
        throw TerminalLauncherError.couldNotCreateScript
    }
}
