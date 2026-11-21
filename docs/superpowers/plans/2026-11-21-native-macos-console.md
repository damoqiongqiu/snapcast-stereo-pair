# Native macOS Console Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native SwiftUI control console and health agent for the
two-MacBook stereo runtime, including mode switching, channel controls, realtime
meters, first-run setup, and source packaging.

**Architecture:** Add a Swift package under `native/` with a shared core library,
a per-user control Agent, a CLI, and a SwiftUI application. The Agent owns mode
changes and health aggregation over a user-only Unix Domain Socket. The runtime
audio processes remain independent launchd jobs.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Foundation, Darwin POSIX sockets,
CoreAudio support code, C++/C runtime, zsh integration scripts, XCTest.

**Spec:** `docs/superpowers/specs/2026-11-21-native-macos-console-design.md`

## Global Constraints

- Minimum deployment target is macOS 14.
- No third-party Swift runtime dependencies.
- No root helper, privileged daemon, App Store requirement, paid Developer ID,
  or automatic updater in the first implementation.
- Never read, store, or display remote SSH passwords in the native app.
- SSH automation uses `BatchMode=yes`, a confirmed host key, and bounded
  timeouts.
- The control socket is local-only, permission `0600`, and validates peer UID.
- Protocol commands use fixed enums and argument arrays; no arbitrary shell
  interpolation or executable paths.
- Closing the GUI does not stop audio. Only an explicit audio-mode change stops
  runtime services.
- Snapcast streams stay `48000:24:1`; CoreAudio applies listening volume after
  decoding while output hardware remains at 100%.
- System mode never unloads or deletes BlackHole.
- Expected service stops in system mode are `disabled`, not `failed`.
- English and Simplified Chinese ship in the first native release.
- Runtime, Agent, CLI, and app use GPL-3.0-or-later.

## Review Focus

- A remote stop over SSH fails or hangs while the local mode change must still
  complete and remain recoverable.
- The Agent exits midway through a mode transition; persisted steps must prevent
  a half-running runtime from being shown as healthy.
- A single missed heartbeat must not create false alarms or repeated
  notifications.
- A malicious local process attempts to connect to the control socket or send
  arbitrary command/path input.
- The app closes or crashes while playback continues, and the next launch must
  reconstruct accurate state from the Agent.

---

## Phase 1: Control Plane and Health

### Task 1: Scaffold the Swift control library and stable models

**Files:**
- Create: `native/Package.swift`
- Create: `native/Sources/StereoPairCore/Models.swift`
- Create: `native/Sources/StereoPairCore/ControlProtocol.swift`
- Create: `native/Tests/StereoPairCoreTests/ModelTests.swift`
- Create: `.swift-version`

**Interfaces:**
- Produces: `AudioMode`, `HealthLevel`, `ServiceState`, `ServiceStatus`,
  `ChannelStatus`, `StreamStatus`, `RuntimeSnapshot`, and versioned
  `ControlRequest` / `ControlEvent`.

- [ ] **Step 1: Add a failing model round-trip test**

```swift
import XCTest
@testable import StereoPairCore

final class ModelTests: XCTestCase {
    func testSnapshotRoundTripPreservesModeAndServiceState() throws {
        let service = ServiceStatus(
            id: "com.snapcast.server",
            displayName: "Snapserver",
            state: .running,
            pid: 42,
            runs: 1,
            lastExitCode: nil,
            lastSuccessAgeSeconds: nil,
            message: nil
        )
        let snapshot = RuntimeSnapshot(
            protocolVersion: 1,
            mode: .snapcast,
            health: .healthy,
            services: [service],
            channels: [],
            streams: [],
            issues: [],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(RuntimeSnapshot.self, from: data)

        XCTAssertEqual(decoded.mode, .snapcast)
        XCTAssertEqual(decoded.services.first?.state, .running)
        XCTAssertEqual(decoded.protocolVersion, 1)
    }
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `swift test --package-path native`

Expected: FAIL because `native/Package.swift` and model types do not exist.

- [ ] **Step 3: Create the Swift package and models**

`native/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacStereoPairNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StereoPairCore", targets: ["StereoPairCore"]),
        .executable(name: "StereoPairAgent", targets: ["StereoPairAgent"]),
        .executable(name: "mac-stereo-pairctl", targets: ["mac-stereo-pairctl"])
    ],
    targets: [
        .target(name: "StereoPairCore"),
        .executableTarget(name: "StereoPairAgent", dependencies: ["StereoPairCore"]),
        .executableTarget(name: "mac-stereo-pairctl", dependencies: ["StereoPairCore"]),
        .testTarget(name: "StereoPairCoreTests", dependencies: ["StereoPairCore"])
    ]
)
```

`native/Sources/StereoPairCore/Models.swift`:

```swift
import Foundation

public enum AudioMode: String, Codable, Sendable {
    case snapcast
    case system
    case transitioning
}

public enum HealthLevel: String, Codable, Sendable {
    case healthy
    case degraded
    case failed
    case disabled
}

public enum ServiceState: String, Codable, Sendable {
    case running
    case inactive
    case failed
    case crashLoop
    case disabled
    case unknown
}

public struct ServiceStatus: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var state: ServiceState
    public var pid: Int?
    public var runs: Int
    public var lastExitCode: Int?
    public var lastSuccessAgeSeconds: Double?
    public var message: String?

    public init(
        id: String,
        displayName: String,
        state: ServiceState,
        pid: Int?,
        runs: Int,
        lastExitCode: Int?,
        lastSuccessAgeSeconds: Double?,
        message: String?
    ) {
        self.id = id
        self.displayName = displayName
        self.state = state
        self.pid = pid
        self.runs = runs
        self.lastExitCode = lastExitCode
        self.lastSuccessAgeSeconds = lastSuccessAgeSeconds
        self.message = message
    }
}

public struct ChannelStatus: Codable, Equatable, Sendable {
    public var side: String
    public var clientId: String
    public var streamId: String
    public var connected: Bool
    public var deviceName: String?
    public var volume: Int
    public var muted: Bool
    public var latencyMs: Int
    public var peakDb: Double?
    public var rmsDb: Double?
    public var clipped: Bool

    public init(
        side: String,
        clientId: String,
        streamId: String,
        connected: Bool,
        deviceName: String?,
        volume: Int,
        muted: Bool,
        latencyMs: Int,
        peakDb: Double?,
        rmsDb: Double?,
        clipped: Bool
    ) {
        self.side = side
        self.clientId = clientId
        self.streamId = streamId
        self.connected = connected
        self.deviceName = deviceName
        self.volume = volume
        self.muted = muted
        self.latencyMs = latencyMs
        self.peakDb = peakDb
        self.rmsDb = rmsDb
        self.clipped = clipped
    }
}

public struct StreamStatus: Codable, Equatable, Sendable {
    public var id: String
    public var state: String
    public var sampleFormat: String?
    public var clientIds: [String]

    public init(
        id: String,
        state: String,
        sampleFormat: String?,
        clientIds: [String]
    ) {
        self.id = id
        self.state = state
        self.sampleFormat = sampleFormat
        self.clientIds = clientIds
    }
}

public struct RuntimeSnapshot: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var mode: AudioMode
    public var health: HealthLevel
    public var services: [ServiceStatus]
    public var channels: [ChannelStatus]
    public var streams: [StreamStatus]
    public var issues: [String]
    public var updatedAt: Date

    public init(
        protocolVersion: Int,
        mode: AudioMode,
        health: HealthLevel,
        services: [ServiceStatus],
        channels: [ChannelStatus],
        streams: [StreamStatus],
        issues: [String],
        updatedAt: Date
    ) {
        self.protocolVersion = protocolVersion
        self.mode = mode
        self.health = health
        self.services = services
        self.channels = channels
        self.streams = streams
        self.issues = issues
        self.updatedAt = updatedAt
    }
}
```

`native/Sources/StereoPairCore/ControlProtocol.swift`:

```swift
import Foundation

public let controlProtocolVersion = 1

public enum ControlRequest: Codable, Equatable, Sendable {
    case snapshot(requestId: String)
    case subscribe(requestId: String)
    case setAudioMode(requestId: String, audioMode: AudioMode)
    case restartPair(requestId: String)
    case setClientVolume(requestId: String, clientId: String, percent: Int)
    case setClientMute(requestId: String, clientId: String, muted: Bool)
    case setClientLatency(requestId: String, clientId: String, milliseconds: Int)
    case exportDiagnostics(requestId: String, redacted: Bool)
}

public enum ControlEvent: Codable, Equatable, Sendable {
    case snapshot(RuntimeSnapshot)
    case error(requestId: String, message: String)
    case success(requestId: String)
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `swift test --package-path native`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add native/Package.swift native/Sources/StereoPairCore native/Tests/StereoPairCoreTests
git commit -m "feat: add native stereo pair control models"
```

---

### Task 2: Parse launchd jobs and aggregate local service health

**Files:**
- Create: `native/Sources/StereoPairCore/CommandRunner.swift`
- Create: `native/Sources/StereoPairCore/LaunchdParser.swift`
- Create: `native/Sources/StereoPairCore/LocalHealthReader.swift`
- Create: `native/Tests/StereoPairCoreTests/LaunchdParserTests.swift`
- Modify: `integration/scripts/ensure-pair-routing.sh`
- Modify: `integration/scripts/wake-recovery-local.sh`
- Modify: `integration/scripts/wake-recovery-remote.sh`
- Create: `integration/test/test-health-markers.sh`

**Interfaces:**
- Consumes: model types from Task 1.
- Produces: `CommandRunning.run(executable:arguments:environment:)`,
  `LaunchdParser.parse(label:output:)`, and
  `LocalHealthReader.readServices()`.

- [ ] **Step 1: Write a failing parser test with a real launchctl-shaped fixture**

```swift
func testRunningJobParsesRunsPIDAndExitState() throws {
    let output = """
        state = running
        path = /Users/tester/Library/LaunchAgents/com.snapcast.server.plist
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
```

- [ ] **Step 2: Run and verify failure**

Run: `swift test --package-path native --filter LaunchdParserTests`

Expected: FAIL because `LaunchdParser` is missing.

- [ ] **Step 3: Implement the parser and command abstraction**

```swift
public struct CommandResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
}

public protocol CommandRunning: Sendable {
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) async throws -> CommandResult
}

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
        let state: ServiceState = switch rawState {
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
```

Implement `SystemCommandRunner` with `/usr/bin/env` or direct absolute paths,
capture pipes, and a hard timeout using `Task` plus process termination.

- [ ] **Step 4: Add service definitions and health reader**

```swift
public struct ServiceDefinition: Sendable {
    public let label: String
    public let displayName: String
    public let requiredInSnapcastMode: Bool
}

public static let localServices: [ServiceDefinition] = [
    .init(label: "com.snapcast.server", displayName: "Snapserver", requiredInSnapcastMode: true),
    .init(label: "com.snapcast.splitter", displayName: "Splitter", requiredInSnapcastMode: true),
    .init(label: "com.snapcast.local-client", displayName: "Local Client", requiredInSnapcastMode: true),
    .init(label: "com.snapcast.pairing", displayName: "Automatic Pairing", requiredInSnapcastMode: true),
    .init(label: "com.snapcast.wake-recovery", displayName: "Wake Recovery", requiredInSnapcastMode: true)
]
```

`LocalHealthReader` invokes:

```swift
try await runner.run(
    executable: "/bin/launchctl",
    arguments: ["print", "gui/\(getuid())/\(definition.label)"],
    environment: [:]
)
```

It parses each job and returns stable service records.

Add atomic JSON result markers for interval and one-shot work:

```text
~/Library/Application Support/Snapcast/state/pairing.json
~/Library/Application Support/Snapcast/state/wake-local.json
~/Library/Application Support/Snapcast/state/wake-remote.json
```

Each marker contains `completedAt`, `success`, `exitCode`, and a short redacted
message. Use `mktemp` in the state directory followed by `mv` for atomic
replacement. `ensure-pair-routing.sh` succeeds without both clients online, so
the marker records the actual reason instead of representing that condition as
a failed job.

Add `test-health-markers.sh` coverage for success, expected waiting, failure,
and malformed marker replacement.

- [ ] **Step 5: Run tests and commit**

Run: `swift test --package-path native --filter LaunchdParserTests`

Expected: PASS.

```bash
git add native/Sources/StereoPairCore native/Tests/StereoPairCoreTests integration/scripts integration/test/test-health-markers.sh
git commit -m "feat: monitor launchd service health"
```

---

### Task 3: Add Snapserver stream/client inspection

**Files:**
- Create: `native/Sources/StereoPairCore/SnapserverModels.swift`
- Create: `native/Sources/StereoPairCore/SnapserverClient.swift`
- Create: `native/Tests/StereoPairCoreTests/SnapserverDecodingTests.swift`

**Interfaces:**
- Consumes: `URLSession`, local JSON-RPC.
- Produces: `SnapserverClient.getStatus()`,
  `SnapserverClient.setVolume(clientId:percent:)`,
  `setMute`, `setLatency`, and normalized channel/stream models.

- [ ] **Step 1: Add a failing decode test using a complete status fixture**

The fixture must include two groups, `LeftAudio` and `RightAudio`, connected
clients, config volumes, and stream URIs. Assert that the normalized result has
one client per stream and preserves volume/mute values.

- [ ] **Step 2: Run and verify failure**

Run: `swift test --package-path native --filter SnapserverDecodingTests`

Expected: FAIL because the response models and client do not exist.

- [ ] **Step 3: Implement private RPC response models and normalization**

```swift
public actor SnapserverClient {
    private let endpoint = URL(string: "http://127.0.0.1:1780/jsonrpc")!

    public func getStatus() async throws -> SnapserverStatus {
        try await rpc(id: "status", method: "Server.GetStatus", params: nil)
    }

    public func setVolume(clientId: String, percent: Int) async throws {
        let value = min(100, max(0, percent))
        _ = try await rpc(
            id: "volume-\(clientId)",
            method: "Client.SetVolume",
            params: ["id": clientId, "volume": ["percent": value, "muted": false]]
        )
    }
}
```

Use a closed JSON value type for every RPC payload:

```swift
public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int)
    case boolean(Bool)
    case object([String: JSONValue])
    case null
}
```

`setVolume` constructs a typed `JSONValue.object`; it does not use `[String: Any]`
or interpolated JSON text.

Use `URLSessionConfiguration.ephemeral`, a 2 second timeout, one JSON encoder,
one decoder, and typed errors for network, RPC, and decoding failures.

- [ ] **Step 4: Verify stream format and route**

Add a health transformer that emits an issue unless:

```text
LeftAudio  == exactly one connected client
RightAudio == exactly one connected client
both sample formats == 48000:24:1
```

- [ ] **Step 5: Run tests and commit**

Run: `swift test --package-path native --filter SnapserverDecodingTests`

Expected: PASS.

```bash
git add native/Sources/StereoPairCore native/Tests/StereoPairCoreTests
git commit -m "feat: inspect snapserver channels and streams"
```

---

### Task 4: Publish splitter meters through shared memory

**Files:**
- Create: `integration/capture/audio_metrics.h`
- Create: `integration/capture/audio_metrics.c`
- Modify: `integration/capture/capture-blackhole-pa.c`
- Modify: `integration/scripts/build-macos.sh`
- Modify: `integration/launchagents/splitter.plist.in`
- Modify: `test/test_main.cpp`

**Interfaces:**
- Produces fixed shared-memory record:

```c
typedef struct {
    uint64_t sequence;
    uint64_t timestamp_ns;
    float left_peak_db;
    float left_rms_db;
    float right_peak_db;
    float right_rms_db;
    uint32_t left_clipped;
    uint32_t right_clipped;
    uint32_t sample_rate;
    uint32_t flags;
} SnapcastAudioMetrics;
```

- [ ] **Step 1: Write failing metric conversion tests**

Test silence returns `-120 dBFS`, full-scale pulse returns `0 dBFS`, and values
above full scale set the clip flag.

- [ ] **Step 2: Run and verify failure**

Run: `./integration/scripts/build-macos.sh && ./bin/snapcast_test --reporter compact`

Expected: FAIL because metric helpers do not exist.

- [ ] **Step 3: Implement metrics and shared-memory publisher**

Use a POSIX shared-memory object name derived from the current UID, for example:

```text
snapcast-stereo-metrics-\(getuid())
```

The writer updates `sequence` with release semantics after writing the payload.
The splitter updates once per callback and must not block the audio path.

- [ ] **Step 4: Add `--metrics-shm NAME` to the splitter**

The LaunchAgent passes the rendered name. Missing metric support is a startup
error so health cannot silently disappear.

- [ ] **Step 5: Run unit tests and a five-second real splitter smoke test**

Run:

```sh
./integration/scripts/build-macos.sh
./bin/snapcast_test --reporter compact
launchctl kickstart -k "gui/$(id -u)/com.snapcast.splitter"
sleep 5
integration/scripts/check-health.sh
```

Expected: tests pass and health sees a fresh metric sequence.

- [ ] **Step 6: Commit**

```bash
git add integration/capture integration/scripts/build-macos.sh integration/launchagents/splitter.plist.in test/test_main.cpp
git commit -m "feat: publish splitter audio metrics"
```

---

### Task 5: Implement the Unix socket protocol, Agent, and CLI

**Files:**
- Create: `native/Sources/StereoPairCore/UnixSocket.swift`
- Create: `native/Sources/StereoPairCore/ControlServer.swift`
- Create: `native/Sources/StereoPairCore/ControlClient.swift`
- Create: `native/Sources/StereoPairAgent/main.swift`
- Create: `native/Sources/mac-stereo-pairctl/main.swift`
- Create: `native/Tests/StereoPairCoreTests/ControlProtocolTests.swift`
- Create: `integration/test/test-control-plane.sh`

**Interfaces:**
- Socket path: `~/Library/Application Support/Snapcast/run/control.sock`
- Socket permissions: `0600`
- Message format: one JSON object per line
- Produces CLI:

```text
mac-stereo-pairctl status --json
mac-stereo-pairctl start
mac-stereo-pairctl stop
mac-stereo-pairctl restart
mac-stereo-pairctl diagnostics --redacted
```

- [ ] **Step 1: Write a failing protocol integration test**

Start an in-process test server in a temporary directory, connect through a
Unix socket, request a snapshot, and assert a valid `ControlEvent.snapshot` is
returned. Open a second socket owned by a different test UID if available and
assert rejection; otherwise cover peer rejection through an injected credential
checker.

- [ ] **Step 2: Run and verify failure**

Run: `swift test --package-path native --filter ControlProtocolTests`

Expected: FAIL because socket transport types do not exist.

- [ ] **Step 3: Implement socket transport and peer validation**

Use `AF_UNIX`, `SOCK_STREAM`, `getpeereid`, `DispatchSource.makeReadSource`, and a
serial queue. Set `umask(0o077)` before binding and explicitly `chmod` the socket
to `0600`. Delete a stale socket only when no process answers a probe.

- [ ] **Step 4: Implement Agent snapshot and subscription loop**

The Agent periodically combines:

- launchd states;
- Snapserver status;
- splitter metrics;
- pairing/wake markers.

It sends snapshots on request and subscriptions on state or meter changes.

- [ ] **Step 5: Implement the CLI**

The CLI resolves the socket path, sends one request, waits for the matching
request ID, prints human-readable output by default, and raw stable JSON with
`--json`.

- [ ] **Step 6: Add an isolated shell integration test**

`integration/test/test-control-plane.sh` uses temporary `SUPPORT_DIR`, a fake
Snapserver fixture, and a test socket. It verifies:

- socket mode is `0600`;
- snapshot JSON parses;
- version mismatch is rejected;
- unknown command is rejected.

- [ ] **Step 7: Run tests and commit**

Run:

```sh
swift test --package-path native
integration/test/test-control-plane.sh
```

Expected: PASS.

```bash
git add native integration/test/test-control-plane.sh
git commit -m "feat: add local stereo pair control agent"
```

---

### Task 6: Implement mode transitions, persistence, and remote best effort

**Files:**
- Create: `native/Sources/StereoPairCore/ModeCoordinator.swift`
- Create: `native/Sources/StereoPairCore/RemoteController.swift`
- Create: `native/Sources/StereoPairCore/TransitionJournal.swift`
- Create: `native/Tests/StereoPairCoreTests/ModeCoordinatorTests.swift`
- Modify: `integration/scripts/set-mode.sh`
- Modify: `integration/scripts/install-local.sh`
- Create: `integration/test/test-mode-transitions.sh`

**Interfaces:**
- Consumes: `CommandRunning`, `SnapserverClient`, control events.
- Produces: idempotent `setMode(.snapcast | .system)` with partial-state result.

- [ ] **Step 1: Write failing transition tests**

Use a fake command runner and verify this exact successful order for system
mode:

```text
stop local client output
switch to saved output
stop pairing and wake recovery
stop splitter and server
attempt remote stop
persist completed mode
```

Add tests for:

- duplicate `setMode(.system)` calls;
- local switch failure triggers pair-mode rollback;
- remote timeout returns local success plus a degradation warning;
- persisted journal resumes after Agent restart.

- [ ] **Step 2: Run and verify failure**

Run: `swift test --package-path native --filter ModeCoordinatorTests`

Expected: FAIL because coordinator and journal types are absent.

- [ ] **Step 3: Implement the transition journal**

Write JSON atomically to:

```text
~/Library/Application Support/Snapcast/state/mode-transition.json
```

Fields: target mode, completed steps, saved output UID, saved client volumes,
start time, and last error.

- [ ] **Step 4: Implement local mode switching**

Extend the rendered `set-mode.sh` with explicit subcommands needed by the Agent:

```text
stop-playback
switch-system-output
stop-runtime
start-runtime
```

Keep `native` and `snapcast` compatibility wrappers for existing users.

- [ ] **Step 5: Implement bounded remote control**

Read `REMOTE_USER` and `REMOTE_HOST` through an installed configuration JSON
generated by `pair-config.sh`; never parse `pair.env` in Swift. Install a fixed
remote helper at:

```text
~/Library/Application Support/Snapcast/remote-mode.sh
```

Construct this exact argument array:

```swift
[
    "/usr/bin/ssh",
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=3",
    "-o", "ServerAliveInterval=2",
    "-o", "ServerAliveCountMax=2",
    "\(remoteUser)@\(remoteHost)",
    "/bin/zsh",
    remoteHelperPath,
    "system"
]
```

The remote path is rendered at installation time and passed as one argument, not
interpreted by a shell. No password prompt is permitted.

- [ ] **Step 6: Run shell and unit tests**

Run:

```sh
swift test --package-path native --filter ModeCoordinatorTests
integration/test/test-mode-transitions.sh
```

Expected: PASS.

- [ ] **Step 7: Hardware validation and commit**

Run both modes on the two Macs and confirm:

- system mode removes BlackHole from system output;
- audio returns directly through the saved device;
- remote failure leaves no local rollback;
- pair mode restores both streams.

```bash
git add native integration/scripts integration/test
git commit -m "feat: add safe remote-aware audio mode transitions"
```

---

### Task 7: Install and supervise the control Agent

**Files:**
- Create: `integration/launchagents/control-agent.plist.in`
- Create: `native/Packaging/build-native.sh`
- Create: `integration/scripts/install-native.sh`
- Modify: `integration/scripts/install-local.sh`
- Modify: `integration/scripts/check-health.sh`
- Modify: `integration/scripts/uninstall-local.sh`
- Modify: `integration/scripts/set-mode.sh`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- LaunchAgent label: `com.snapcast.control-agent`
- Agent executable: `~/Library/Application Support/Snapcast/bin/StereoPairAgent`

- [ ] **Step 1: Add a failing installer test**

Extend `integration/test/test-wake-recovery.sh` or add
`test-control-agent-install.sh` with a temporary home and fake launchctl. Assert
that install renders the Agent plist, installs the socket directory with `0700`,
and bootstraps the Agent.

- [ ] **Step 2: Run and verify failure**

Run: `integration/test/test-control-agent-install.sh`

Expected: FAIL because installer and template are missing.

- [ ] **Step 3: Implement build and LaunchAgent**

`native/Packaging/build-native.sh` runs:

```sh
swift build --package-path native -c release --product StereoPairAgent
swift build --package-path native -c release --product mac-stereo-pairctl
```

The Agent LaunchAgent uses a rendered support path, runs as the logged-in user,
and keeps the GUI-independent monitor alive.

- [ ] **Step 4: Extend health checks**

`check-health.sh` calls `mac-stereo-pairctl status --json`, verifies protocol
version, and fails on missing Agent or malformed JSON.

- [ ] **Step 5: Run all automated checks**

Run:

```sh
swift test --package-path native
integration/test/test-control-agent-install.sh
integration/test/test-wake-recovery.sh
integration/test/test-mode-transitions.sh
zsh -n integration/scripts/*.sh integration/test/*.sh
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add integration native/Packaging .github/workflows/ci.yml
git commit -m "feat: install the native control agent"
```

---

## Phase 2: Native Console

### Task 8: Add SwiftUI app target, theme, and localization

**Files:**
- Modify: `native/Package.swift`
- Create: `native/Sources/MacStereoPair/MacStereoPairApp.swift`
- Create: `native/Sources/MacStereoPair/Theme.swift`
- Create: `native/Sources/MacStereoPair/Resources/en.lproj/Localizable.strings`
- Create: `native/Sources/MacStereoPair/Resources/zh-Hans.lproj/Localizable.strings`
- Create: `native/Tests/StereoPairCoreTests/LocalizationTests.swift`

**Interfaces:**
- Produces: executable product `MacStereoPair` and shared semantic design
  tokens.

- [ ] **Step 1: Write a failing localization coverage test**

Parse both `.strings` files and assert identical non-empty keys for English and
Simplified Chinese, including mode, service, volume, latency, error, setup, and
accessibility strings.

- [ ] **Step 2: Run and verify failure**

Run: `swift test --package-path native --filter LocalizationTests`

Expected: FAIL because resources and app target do not exist.

- [ ] **Step 3: Add the app target with `LSUIElement` packaging metadata**

Extend `native/Package.swift` with:

```swift
.executableTarget(
    name: "MacStereoPair",
    dependencies: ["StereoPairCore"],
    resources: [.process("Resources")]
),
.testTarget(
    name: "MacStereoPairTests",
    dependencies: ["StereoPairCore", "MacStereoPair"]
)
```

```swift
@main
struct MacStereoPairApp: App {
    var body: some Scene {
        WindowGroup {
            ConsoleView()
        }
        MenuBarExtra("MacBook Stereo Pair", systemImage: "hifispeaker.2.fill") {
            MenuBarContent()
        }
    }
}
```

- [ ] **Step 4: Implement semantic tokens**

Define backgrounds, surfaces, text, muted text, separator, success, warning,
error, info, radii, spacing, and typography in `Theme.swift`. Use system colors
where they preserve dark/light appearance.

- [ ] **Step 5: Run tests and commit**

Run: `swift test --package-path native --filter LocalizationTests`

Expected: PASS.

```bash
git add native/Package.swift native/Sources/MacStereoPair native/Tests/StereoPairCoreTests
git commit -m "feat: scaffold native stereo console"
```

---

### Task 9: Connect the app to the Agent and model live state

**Files:**
- Create: `native/Sources/MacStereoPair/ConsoleViewModel.swift`
- Create: `native/Sources/MacStereoPair/StatusClient.swift`
- Create: `native/Tests/MacStereoPairTests/ConsoleViewModelTests.swift`
- Modify: `native/Package.swift`

**Interfaces:**
- Consumes: `ControlClient`, `RuntimeSnapshot`.
- Produces: `@MainActor @Observable ConsoleViewModel` with modes, channels,
  services, meter samples, transition progress, errors, and commands.

- [ ] **Step 1: Write failing view-model tests**

Cover:

- disconnected Agent starts in failed state;
- first snapshot populates channels and health;
- switching mode prevents duplicate commands;
- system mode marks services disabled without errors;
- master volume preserves channel offsets.

- [ ] **Step 2: Run and verify failure**

Run: `swift test --package-path native --filter ConsoleViewModelTests`

Expected: FAIL because the view model does not exist.

- [ ] **Step 3: Implement the observable state machine**

Use an injected protocol:

```swift
public protocol ControlTransport: Sendable {
    func request(_ request: ControlRequest) async throws -> ControlEvent
    func events() async throws -> AsyncStream<ControlEvent>
}
```

The view model reconnects with bounded exponential backoff and never triggers
mode changes from connection recovery.

- [ ] **Step 4: Implement volume derivation**

Apply the approved offset algorithm:

```swift
func masterChanged(from old: Int, to new: Int) {
    let delta = new - old
    leftVolume = min(100, max(0, leftVolume + delta))
    rightVolume = min(100, max(0, rightVolume + delta))
}
```

Send one command per changed client and surface partial failure.

- [ ] **Step 5: Run tests and commit**

Run: `swift test --package-path native --filter ConsoleViewModelTests`

Expected: PASS.

```bash
git add native/Package.swift native/Sources/MacStereoPair native/Tests/MacStereoPairTests
git commit -m "feat: connect native console to control agent"
```

---

### Task 10: Build the dual-channel professional console

**Files:**
- Create: `native/Sources/MacStereoPair/ConsoleView.swift`
- Create: `native/Sources/MacStereoPair/ModeSelector.swift`
- Create: `native/Sources/MacStereoPair/ChannelStrip.swift`
- Create: `native/Sources/MacStereoPair/MasterControl.swift`
- Create: `native/Sources/MacStereoPair/AudioMeter.swift`

**Interfaces:**
- Consumes: `ConsoleViewModel`.
- Produces: the approved dual-channel layout from the design spec.

- [ ] **Step 1: Add failing snapshot/view-state tests**

Cover healthy, transition, degraded, and system snapshots and assert derived
labels, button availability, and channel visibility.

- [ ] **Step 2: Run and verify failure**

Run: `swift test --package-path native --filter ConsoleViewModelTests`

Expected: FAIL for missing derived UI properties.

- [ ] **Step 3: Implement the stable main layout**

Use a top mode selector, two equal channel columns, central master controls, and
the status bus beneath. Do not rebuild the page hierarchy between modes.

- [ ] **Step 4: Implement meters and channel controls**

`AudioMeter` receives peak/RMS/clip, draws a vertical scale, supports peak hold,
and exposes accessibility text. Channel strips provide volume, mute, latency,
device, route, and connection state.

- [ ] **Step 5: Build and render all four states**

Run:

```sh
swift build --package-path native --product MacStereoPair
```

Capture the app in healthy, transitioning, degraded, and system states for
review.

- [ ] **Step 6: Commit**

```bash
git add native/Sources/MacStereoPair
git commit -m "feat: build dual-channel stereo console"
```

---

### Task 11: Add the partitioned LED status bus and advanced diagnostics

**Files:**
- Create: `native/Sources/MacStereoPair/StatusBus.swift`
- Create: `native/Sources/MacStereoPair/ServiceLED.swift`
- Create: `native/Sources/MacStereoPair/AdvancedView.swift`
- Modify: `native/Sources/MacStereoPair/Theme.swift`

**Interfaces:**
- Consumes service and stream snapshots.
- Produces `Control | Audio Path | Routing | Recovery` instrumentation.

- [ ] **Step 1: Write failing LED-state tests**

Verify steady green for healthy, pulsing green only for fresh activity, amber for
degraded, red for failed, and dim gray for intentionally disabled. Verify each
state also has non-color text.

- [ ] **Step 2: Run and verify failure**

Run: `swift test --package-path native --filter LEDStateTests`

Expected: FAIL because the status-bus mapping is missing.

- [ ] **Step 3: Implement the status bus**

Use the approved four zones. The pulse animation:

- affects only the LED halo;
- runs at a calm two-second cadence;
- stops under Reduce Motion;
- has a static non-color label.

- [ ] **Step 4: Implement Advanced Diagnostics**

Provide logs, redacted export, protocol/runtime versions, raw snapshot, and
per-service maintenance actions. Do not duplicate normal volume or routing
controls there.

- [ ] **Step 5: Run tests and commit**

Run: `swift test --package-path native`

Expected: PASS.

```bash
git add native/Sources/MacStereoPair
git commit -m "feat: add console status bus and diagnostics"
```

---

### Task 12: Add menu bar actions, notifications, localization, and accessibility

**Files:**
- Create: `native/Sources/MacStereoPair/MenuBarContent.swift`
- Create: `native/Sources/MacStereoPair/NotificationManager.swift`
- Create: `native/Tests/MacStereoPairTests/NotificationStateTests.swift`
- Modify: `native/Sources/MacStereoPair/ConsoleView.swift`
- Modify: localization resources

**Interfaces:**
- Produces menu-bar mode/volume/mute/status controls and deduplicated incident
  notifications.

- [ ] **Step 1: Write failing notification tests**

Assert one notification per incident, no repeat while unchanged, reset after
recovery, and no failure notification for system-mode disabled services.

- [ ] **Step 2: Run and verify failure**

Run: `swift test --package-path native --filter NotificationStateTests`

Expected: FAIL because incident tracking is missing.

- [ ] **Step 3: Implement menu bar and notification behavior**

The menu includes current mode, status, master volume, mute, reconnect/restart,
open console, and quit GUI. Request notification permission after first
successful setup, not on app launch.

- [ ] **Step 4: Complete accessibility and language coverage**

Add English and Simplified Chinese strings, voice-over labels, keyboard
shortcuts, focus order, and Reduce Motion behavior.

- [ ] **Step 5: Run tests and commit**

Run:

```sh
swift test --package-path native
swift build --package-path native --product MacStereoPair
```

Expected: PASS.

```bash
git add native/Sources/MacStereoPair native/Tests/MacStereoPairTests
git commit -m "feat: add menu bar controls and accessibility"
```

---

## Phase 3: First-Run Setup and Distribution

### Task 13: Implement environment probing and safe Terminal handoff

**Files:**
- Create: `native/Sources/StereoPairCore/SetupModels.swift`
- Create: `native/Sources/StereoPairCore/SetupProbe.swift`
- Create: `native/Sources/StereoPairCore/TerminalLauncher.swift`
- Create: `native/Tests/StereoPairCoreTests/SetupProbeTests.swift`
- Create: `integration/scripts/native-setup-helper.sh`

**Interfaces:**
- Produces dependency checks and a generated setup command channel.

- [ ] **Step 1: Write failing setup-probe tests**

Test valid, missing, outdated, and malformed results for Xcode Command Line
Tools, Homebrew, BlackHole, PortAudio, runtime, and SSH. Assert remediation text
is stable and localized.

- [ ] **Step 2: Run and verify failure**

Run: `swift test --package-path native --filter SetupProbeTests`

Expected: FAIL because setup types are absent.

- [ ] **Step 3: Implement probes with absolute executables**

Use fixed checks:

```text
/usr/bin/xcode-select -p
/usr/sbin/system_profiler SPAudioDataType -json
/usr/bin/ssh
```

For Homebrew, check these two absolute locations in order and use the first
existing executable:

```text
/opt/homebrew/bin/brew
/usr/local/bin/brew
```

Also validate the installed runtime and control Agent.

- [ ] **Step 4: Implement safe Terminal handoff**

Generate a temporary script under the support directory, `chmod 700`, write
fixed commands, and open it in Terminal through `/usr/bin/open -a Terminal`.
Remove the script after completion or expiry.

- [ ] **Step 5: Run tests and commit**

Run: `swift test --package-path native --filter SetupProbeTests`

Expected: PASS.

```bash
git add native/Sources/StereoPairCore native/Tests integration/scripts/native-setup-helper.sh
git commit -m "feat: probe mac audio setup safely"
```

---

### Task 14: Build the approved first-run wizard

**Files:**
- Create: `native/Sources/MacStereoPair/Setup/SetupFlowView.swift`
- Create: `native/Sources/MacStereoPair/Setup/SetupSidebar.swift`
- Create: `native/Sources/MacStereoPair/Setup/SetupViewModel.swift`
- Create: `native/Sources/MacStereoPair/Setup/LocalSetupStep.swift`
- Create: `native/Sources/MacStereoPair/Setup/RemoteSetupStep.swift`
- Create: `native/Sources/MacStereoPair/Setup/VerificationStep.swift`
- Create: `native/Tests/MacStereoPairTests/SetupViewModelTests.swift`

**Interfaces:**
- Consumes: setup probes, runtime commands, SSH validation, and pair config.
- Produces: resumable first-run flow.

- [ ] **Step 1: Write failing wizard-state tests**

Cover:

- fresh install starts at welcome;
- completed checks resume at the next incomplete step;
- Terminal handoff remains pending until polling observes completion;
- remote failure shows retry without erasing local state;
- final verification enables the console.

- [ ] **Step 2: Run and verify failure**

Run: `swift test --package-path native --filter SetupViewModelTests`

Expected: FAIL because setup flow does not exist.

- [ ] **Step 3: Implement the side-bar wizard**

Use the approved persistent step sidebar. Current step content includes explicit
status LEDs, a primary Terminal action, a secondary explanation action, and no
raw commands in the main path.

- [ ] **Step 4: Implement remote setup**

Collect user and host into validated fields. Generate `ssh-keygen`/`ssh-copy-id`
Terminal guidance only when needed. Validate `BatchMode=yes` SSH before
continuing. Store non-secret configuration only through the runtime config
helper.

- [ ] **Step 5: Implement final local verification**

Verify both clients, both streams, format, volume paths, and mode switching
before marking setup complete.

- [ ] **Step 6: Run tests and commit**

Run:

```sh
swift test --package-path native
swift build --package-path native --product MacStereoPair
```

Expected: PASS.

```bash
git add native/Sources/MacStereoPair/Setup native/Tests/MacStereoPairTests
git commit -m "feat: add native first-run setup wizard"
```

---

### Task 15: Package and install the native application

**Files:**
- Create: `native/Packaging/MacStereoPair-Info.plist`
- Create: `native/Packaging/build-app.sh`
- Modify: `native/Packaging/build-native.sh`
- Create: `integration/scripts/install-native.sh`
- Create: `integration/scripts/uninstall-native.sh`
- Modify: `integration/scripts/install-local.sh`
- Modify: `.gitignore`

**Interfaces:**
- Produces `~/Applications/MacBook Stereo Pair.app`.
- Installs Agent and CLI into the runtime support directory.

- [ ] **Step 1: Add a failing packaging smoke test**

Build into a temporary prefix and assert:

- app bundle exists;
- `Contents/MacOS/MacStereoPair` is executable;
- `Info.plist` declares `LSUIElement=true`;
- app, Agent, and CLI are ad-hoc signed;
- no source/build path is embedded in release output.

- [ ] **Step 2: Run and verify failure**

Run: `native/Packaging/build-app.sh --output "$PWD/.build/native-test-app"`

Expected: FAIL because packaging script and plist do not exist.

- [ ] **Step 3: Implement release build and app bundle**

`build-app.sh`:

```sh
swift build --package-path native -c release --product MacStereoPair
mkdir -p "$output/Contents/MacOS" "$output/Contents/Resources"
cp native/.build/release/MacStereoPair "$output/Contents/MacOS/MacStereoPair"
cp native/Packaging/MacStereoPair-Info.plist "$output/Contents/Info.plist"
codesign --force --deep --sign - "$output"
```

Use a temporary build directory for release outputs.

- [ ] **Step 4: Implement user-level install and uninstall**

Install the app under `~/Applications`, Agent and CLI under the runtime support
directory. Bootstrap the Agent LaunchAgent after installation. Uninstall
bootouts the Agent but does not stop audio unless the user separately chooses
system mode.

- [ ] **Step 5: Run packaging smoke and installer tests**

Run:

```sh
native/Packaging/build-app.sh --output "$PWD/.build/native-test-app"
integration/test/test-control-agent-install.sh
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add native/Packaging integration/scripts .gitignore
git commit -m "feat: package and install native stereo console"
```

---

### Task 16: Add Homebrew build-from-source formula

**Files:**
- Create: `packaging/homebrew/macbook-stereo-pair.rb`
- Create: `docs/homebrew.md`
- Create: `integration/test/test-homebrew-formula.sh`

**Interfaces:**
- Produces a formula that builds from the repository source and installs the app
  without a paid Developer ID.

- [ ] **Step 1: Write a failing formula structure test**

Run Ruby syntax and audit checks in an isolated Homebrew environment. Assert the
formula depends on Xcode Command Line Tools at build time, invokes the native
build script, installs the app bundle, and does not declare an App Store
dependency.

- [ ] **Step 2: Run and verify failure**

Run: `integration/test/test-homebrew-formula.sh`

Expected: FAIL because the formula does not exist.

- [ ] **Step 3: Implement the formula**

The `install` block calls:

```ruby
system "native/Packaging/build-app.sh",
       "--output",
       buildpath/"MacBook Stereo Pair.app"
prefix.install "MacBook Stereo Pair.app"
bin.install "native/.build/release/mac-stereo-pairctl"
```

Document Gatekeeper behavior and source-build limitations.

- [ ] **Step 4: Run formula checks and commit**

Run: `integration/test/test-homebrew-formula.sh`

Expected: PASS.

```bash
git add packaging/homebrew docs/homebrew.md integration/test/test-homebrew-formula.sh
git commit -m "feat: add source Homebrew packaging"
```

---

### Task 17: Complete documentation, CI, and hardware release gate

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/architecture.md`
- Modify: `docs/installation.md`
- Modify: `docs/troubleshooting.md`
- Modify: `docs/upstream-sync.md`
- Modify: `.github/workflows/ci.yml`
- Create: `docs/native-console.md`
- Create: `integration/test/test-native-release.sh`

**Interfaces:**
- Produces release documentation and a repeatable acceptance script.

- [ ] **Step 1: Update public documentation**

Document:

- native-first UI and Snapweb fallback status;
- menu-bar/window behavior;
- two audio modes;
- SSH key-only remote behavior;
- source install and Gatekeeper notes;
- macOS 14 minimum;
- service health and notification semantics;
- advanced diagnostics and redaction;
- protocol version compatibility.

- [ ] **Step 2: Update CI**

Add:

```sh
swift test --package-path native
swift build --package-path native -c release
integration/test/test-control-plane.sh
integration/test/test-mode-transitions.sh
integration/test/test-control-agent-install.sh
integration/test/test-homebrew-formula.sh
integration/test/test-native-release.sh
```

- [ ] **Step 3: Create hardware release checklist**

The script/checklist requires two Macs and records:

- model, macOS, BlackHole, PortAudio, Swift;
- both modes;
- remote online/offline;
- sleep/wake;
- service crash/restart;
- meter behavior;
- localization screenshot;
- accessibility check;
- no credentials in diagnostics.

- [ ] **Step 4: Run the complete automated test suite**

Run:

```sh
./integration/scripts/build-macos.sh
swift test --package-path native
swift build --package-path native -c release
integration/test/test-pair-config.sh
integration/test/test-audio-levels.sh
integration/test/test-pair-routing.sh
integration/test/test-wake-recovery.sh
integration/test/test-control-plane.sh
integration/test/test-mode-transitions.sh
integration/test/test-control-agent-install.sh
integration/test/test-homebrew-formula.sh
zsh -n integration/scripts/*.sh integration/test/*.sh
plutil -lint integration/launchagents/*.plist.in
./scripts/check-public-tree.sh
```

Expected: PASS.

- [ ] **Step 5: Complete two-Mac hardware acceptance and commit**

Record all hardware checks from the design spec. Do not claim release readiness
without both systems online.

```bash
git add README.md AGENTS.md CHANGELOG.md docs .github/workflows/ci.yml integration/test
git commit -m "docs: document native macOS console release"
```

---

## Final Verification

Run:

```sh
./integration/scripts/build-macos.sh
cmake --build .build-tests -j 8 --target snapcast_test
./bin/snapcast_test --reporter compact
swift test --package-path native
swift build --package-path native -c release
integration/test/test-control-plane.sh
integration/test/test-mode-transitions.sh
integration/test/test-control-agent-install.sh
integration/test/test-homebrew-formula.sh
zsh -n integration/scripts/*.sh integration/test/*.sh
plutil -lint integration/launchagents/*.plist.in
./scripts/check-public-tree.sh
```

Expected:

- every command exits 0;
- both audio modes work on two Macs;
- the GUI, menu bar, and CLI agree on state;
- remote failure degrades without blocking local system-audio recovery;
- no new crash reports or secrets appear in diagnostics.
