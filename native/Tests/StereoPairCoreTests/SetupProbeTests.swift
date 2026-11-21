import Foundation
import XCTest
@testable import StereoPairCore

final class SetupProbeTests: XCTestCase {
    func testXcodeCommandLineToolsReadyAndMissingStates() {
        XCTAssertEqual(
            SetupResultParser.xcode(
                status: 0,
                output: "/Library/Developer/CommandLineTools\n"
            ).status,
            .ready
        )
        XCTAssertEqual(
            SetupResultParser.xcode(status: 1, output: "").status,
            .missing
        )
    }

    func testHomebrewDetectsReadyOutdatedAndMalformedVersions() {
        XCTAssertEqual(
            SetupResultParser.homebrew(status: 0, output: "Homebrew 4.6.2\n").status,
            .ready
        )
        XCTAssertEqual(
            SetupResultParser.homebrew(status: 0, output: "Homebrew 3.6.0\n").status,
            .outdated
        )
        XCTAssertEqual(
            SetupResultParser.homebrew(status: 0, output: "unexpected output").status,
            .malformed
        )
        XCTAssertEqual(
            SetupResultParser.homebrew(status: 1, output: "").status,
            .missing
        )
    }

    func testBlackHoleAudioDeviceProbeHandlesValidMissingAndMalformedJSON() {
        let fixture = """
        {
          "SPAudioDataType": [{
            "_items": [
              {"_name": "MacBook Pro Speakers"},
              {"_name": "BlackHole 2ch"}
            ]
          }]
        }
        """
        XCTAssertEqual(
            SetupResultParser.audioDevices(status: 0, json: fixture).status,
            .ready
        )
        XCTAssertEqual(
            SetupResultParser.audioDevices(
                status: 0,
                json: #"{"SPAudioDataType":[{"_items":[{"_name":"Speakers"}]}]}"#
            ).status,
            .missing
        )
        XCTAssertEqual(
            SetupResultParser.audioDevices(status: 0, json: "{broken").status,
            .malformed
        )
    }

    func testPortAudioDetectsReadyMissingAndOutdatedPackages() {
        XCTAssertEqual(
            SetupResultParser.portAudio(status: 0, output: "portaudio 19.7.0\n").status,
            .ready
        )
        XCTAssertEqual(
            SetupResultParser.portAudio(status: 0, output: "portaudio 19.6.0\n").status,
            .outdated
        )
        XCTAssertEqual(
            SetupResultParser.portAudio(status: 1, output: "").status,
            .missing
        )
    }

    func testRuntimeRequiresAudioModeAndControlBinaries() {
        XCTAssertEqual(
            SetupResultParser.runtime(
                files: [
                    "set-mode.sh": true,
                    "bin/StereoPairAgent": true,
                    "bin/mac-stereo-pairctl": true
                ]
            ).status,
            .ready
        )
        XCTAssertEqual(
            SetupResultParser.runtime(
                files: [
                    "set-mode.sh": true,
                    "bin/StereoPairAgent": false,
                    "bin/mac-stereo-pairctl": true
                ]
            ).status,
            .missing
        )
    }

    func testSSHDetectsReadyMissingOutdatedAndMalformedOutput() {
        XCTAssertEqual(
            SetupResultParser.ssh(status: 0, output: "OpenSSH_9.8p1, LibreSSL 3.3.6\n").status,
            .ready
        )
        XCTAssertEqual(
            SetupResultParser.ssh(status: 0, output: "OpenSSH_7.9p1\n").status,
            .outdated
        )
        XCTAssertEqual(SetupResultParser.ssh(status: 1, output: "").status, .missing)
        XCTAssertEqual(
            SetupResultParser.ssh(status: 0, output: "unexpected").status,
            .malformed
        )
    }

    func testRemoteSetupActionUsesAValidatedArgumentArray() throws {
        let action = try SetupAction.configureRemote(
            user: "tester",
            host: "198.51.100.20"
        )

        XCTAssertEqual(action.arguments, ["configure-remote", "tester", "198.51.100.20"])
        XCTAssertThrowsError(
            try SetupAction.configureRemote(user: "bad;command", host: "198.51.100.20")
        )
        XCTAssertThrowsError(
            try SetupAction.configureRemote(user: "tester", host: "host name")
        )
    }

    func testForceReinstallActionUsesTheLifecycleHelperCommand() {
        XCTAssertEqual(
            SetupAction.forceReinstallCurrentVersion.arguments,
            ["force-reinstall"]
        )
    }
}
