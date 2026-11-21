import Foundation

public struct SetupProbe: Sendable {
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

    public func checkAll() async -> [SetupCheck] {
        async let xcode = checkXcode()
        async let homebrew = checkHomebrew()
        async let blackHole = checkBlackHole()
        async let ssh = checkSSH()
        let brewPath = homebrewExecutable()
        async let portAudio = checkPortAudio(brewPath: brewPath)
        return await [xcode, homebrew, blackHole, portAudio, checkRuntime(), ssh]
    }

    private func checkXcode() async -> SetupCheck {
        do {
            let result = try await runner.run(
                executable: "/usr/bin/xcode-select",
                arguments: ["-p"],
                environment: [:],
                timeout: 3
            )
            return SetupResultParser.xcode(status: result.status, output: result.stdout)
        } catch {
            return SetupResultParser.xcode(status: 1, output: "")
        }
    }

    private func checkHomebrew() async -> SetupCheck {
        guard let path = homebrewExecutable() else {
            return SetupResultParser.homebrew(status: 1, output: "")
        }
        do {
            let result = try await runner.run(
                executable: path,
                arguments: ["--version"],
                environment: [:],
                timeout: 4
            )
            return SetupResultParser.homebrew(status: result.status, output: result.stdout)
        } catch {
            return SetupResultParser.homebrew(status: 1, output: "")
        }
    }

    private func checkBlackHole() async -> SetupCheck {
        do {
            let result = try await runner.run(
                executable: "/usr/sbin/system_profiler",
                arguments: ["SPAudioDataType", "-json"],
                environment: [:],
                timeout: 8
            )
            return SetupResultParser.audioDevices(status: result.status, json: result.stdout)
        } catch {
            return SetupResultParser.audioDevices(status: 1, json: "")
        }
    }

    private func checkPortAudio(brewPath: String?) async -> SetupCheck {
        guard let brewPath else {
            return SetupResultParser.portAudio(status: 1, output: "")
        }
        do {
            let result = try await runner.run(
                executable: brewPath,
                arguments: ["list", "--versions", "portaudio"],
                environment: [:],
                timeout: 4
            )
            return SetupResultParser.portAudio(status: result.status, output: result.stdout)
        } catch {
            return SetupResultParser.portAudio(status: 1, output: "")
        }
    }

    private func checkRuntime() -> SetupCheck {
        let manager = FileManager.default
        let files = [
            "set-mode.sh": manager.fileExists(atPath: supportDirectory.appendingPathComponent("set-mode.sh").path),
            "bin/StereoPairAgent": manager.fileExists(
                atPath: supportDirectory.appendingPathComponent("bin/StereoPairAgent").path
            ),
            "bin/mac-stereo-pairctl": manager.fileExists(
                atPath: supportDirectory.appendingPathComponent("bin/mac-stereo-pairctl").path
            )
        ]
        return SetupResultParser.runtime(files: files)
    }

    private func checkSSH() async -> SetupCheck {
        do {
            let result = try await runner.run(
                executable: "/usr/bin/ssh",
                arguments: ["-V"],
                environment: [:],
                timeout: 3
            )
            return SetupResultParser.ssh(
                status: result.status,
                output: result.stdout + result.stderr
            )
        } catch {
            return SetupResultParser.ssh(status: 1, output: "")
        }
    }

    private func homebrewExecutable() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
