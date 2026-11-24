import XCTest
@testable import StereoPairCore

final class LaunchdParserTests: XCTestCase {
    func testRunningJobParsesRunsPIDAndExitState() throws {
        let output = """
            state = running
            path = /tmp/Library/LaunchAgents/com.snapcast.server.plist
            runs = 3
            pid = 4812
            last exit code = 0
        """
        let result = try LaunchdParser.parse(
            label: "com.snapcast.server",
            displayName: "Snapserver",
            output: output
        )
        XCTAssertEqual(result.state, .running)
        XCTAssertEqual(result.pid, 4812)
        XCTAssertEqual(result.runs, 3)
        XCTAssertEqual(result.lastExitCode, 0)
    }

    func testStoppedJobDoesNotRequirePID() throws {
        let output = """
            state = not running
            runs = 0
            last exit code = 78
        """
        let result = try LaunchdParser.parse(
            label: "com.snapcast.pairing",
            displayName: "Automatic Pairing",
            output: output
        )
        XCTAssertEqual(result.state, .inactive)
        XCTAssertNil(result.pid)
        XCTAssertEqual(result.lastExitCode, 78)
    }
}
