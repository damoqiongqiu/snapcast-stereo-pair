import Combine
import Foundation
import StereoPairCore
import XCTest
@testable import MacStereoPair

@MainActor
final class ConsoleViewModelTests: XCTestCase {
    func testDisconnectedAgentStartsFailed() {
        let model = ConsoleViewModel(transport: FixtureTransport())

        XCTAssertEqual(model.connectionState, .failed)
        XCTAssertFalse(model.healthy)
    }

    func testFirstSnapshotPopulatesChannelsAndHealth() async {
        let transport = FixtureTransport(snapshot: .healthy)
        let model = ConsoleViewModel(transport: transport)

        await model.refresh()

        XCTAssertEqual(model.connectionState, .connected)
        XCTAssertEqual(model.left?.clientId, "left-client")
        XCTAssertEqual(model.right?.clientId, "right-client")
        XCTAssertEqual(model.snapshot?.health, .healthy)
        XCTAssertNil(model.message)
    }

    func testEquivalentSnapshotWithNewTimestampDoesNotRepublish() {
        let model = ConsoleViewModel(transport: FixtureTransport())
        model.apply(snapshot: .healthy)

        var publicationCount = 0
        let cancellable = model.objectWillChange.sink { _ in
            publicationCount += 1
        }
        defer { cancellable.cancel() }

        var equivalent = RuntimeSnapshot.healthy
        equivalent.updatedAt = equivalent.updatedAt.addingTimeInterval(1)
        model.apply(snapshot: equivalent)

        XCTAssertEqual(publicationCount, 0)
    }

    func testMenuBarStateIgnoresWaveformOnlySnapshotChanges() {
        let model = ConsoleViewModel(transport: FixtureTransport())
        model.apply(snapshot: .healthy)

        var publicationCount = 0
        let cancellable = model.menuBar.objectWillChange.sink { _ in
            publicationCount += 1
        }
        defer { cancellable.cancel() }

        var waveformOnlyChange = RuntimeSnapshot.healthy
        waveformOnlyChange.updatedAt = waveformOnlyChange.updatedAt.addingTimeInterval(1)
        waveformOnlyChange.channels[0].peakDb = -12
        model.apply(snapshot: waveformOnlyChange)
        XCTAssertEqual(publicationCount, 0)

        var volumeChange = waveformOnlyChange
        volumeChange.channels[0].volume = 51
        volumeChange.channels[1].volume = 91
        model.apply(snapshot: volumeChange)
        XCTAssertEqual(publicationCount, 1)
    }

    func testWaveformOnlySnapshotChangeDoesNotRepublishConsoleRoot() {
        let model = ConsoleViewModel(transport: FixtureTransport())
        model.apply(snapshot: .healthy)

        var publicationCount = 0
        let cancellable = model.objectWillChange.sink { _ in
            publicationCount += 1
        }
        defer { cancellable.cancel() }

        var waveformOnlyChange = RuntimeSnapshot.healthy
        waveformOnlyChange.updatedAt = waveformOnlyChange.updatedAt.addingTimeInterval(1)
        waveformOnlyChange.channels[0].peakDb = -8
        waveformOnlyChange.channels[0].rmsDb = -20
        model.apply(snapshot: waveformOnlyChange)

        XCTAssertEqual(publicationCount, 0)
        XCTAssertEqual(model.liveChannels.left?.peakDb, -8)
    }

    func testControlSnapshotPollingRunsFourTimesPerSecond() {
        XCTAssertEqual(
            ConsolePollingPolicy.snapshotInterval(consoleVisible: true),
            .milliseconds(250)
        )
    }

    func testHiddenConsolePollsOncePerSecond() {
        XCTAssertEqual(
            ConsolePollingPolicy.snapshotInterval(consoleVisible: false),
            .seconds(1)
        )
    }

    func testDuplicateModeCommandIsIgnoredWhileTransitionIsInFlight() async {
        let transport = SuspendedModeTransport(snapshot: .healthy)
        let model = ConsoleViewModel(transport: transport)

        let first = Task { await model.setMode(.system) }
        await transport.waitForModeRequest()
        await model.setMode(.snapcast)

        let modeRequestCount = await transport.modeRequestCount()
        XCTAssertEqual(modeRequestCount, 1)
        await transport.resumeModeRequest()
        await first.value
    }

    func testSystemModeDisablesServicesWithoutReportingAnError() async {
        let transport = FixtureTransport(snapshot: .system)
        let model = ConsoleViewModel(transport: transport)

        await model.refresh()

        XCTAssertEqual(model.snapshot?.mode, .system)
        XCTAssertEqual(model.snapshot?.health, .disabled)
        XCTAssertTrue(model.snapshot?.services.allSatisfy { $0.state == .disabled } == true)
        XCTAssertNil(model.message)
    }

    func testMasterVolumePreservesChannelOffsets() async {
        let transport = FixtureTransport(snapshot: .healthy)
        let model = ConsoleViewModel(transport: transport)
        await model.refresh()

        await model.setMaster(76)

        let volumes = await transport.volumeRequests()
        XCTAssertEqual(volumes, [
            .init(clientId: "left-client", percent: 56),
            .init(clientId: "right-client", percent: 96)
        ])
    }

    func testDiagnosticsExportReturnsTheAgentPayload() async {
        let model = ConsoleViewModel(transport: DiagnosticsTransport())

        let payload = await model.exportDiagnostics(redacted: true)

        XCTAssertEqual(payload, #"{"health":"healthy","protocolVersion":1}"#)
    }

    func testServiceRestartSendsOnlyTheSelectedKnownService() async {
        let transport = DiagnosticsTransport()
        let model = ConsoleViewModel(transport: transport)

        await model.restartService(id: "com.snapcast.splitter")

        let restartedServices = await transport.restartedServices()
        XCTAssertEqual(restartedServices, ["com.snapcast.splitter"])
    }

    func testHardwareVolumeRefreshRequestsAgentAndReloadsSnapshot() async {
        let transport = HardwareVolumeRefreshTransport(snapshot: .healthy)
        let model = ConsoleViewModel(transport: transport)

        await model.refreshHardwareVolumes()

        let refreshRequests = await transport.refreshRequests()
        let snapshotRequests = await transport.snapshotRequests()
        XCTAssertEqual(refreshRequests, 1)
        XCTAssertEqual(snapshotRequests, 1)
        XCTAssertEqual(model.hardwareVolume(side: "left")?.volumePercent, 100)
        XCTAssertFalse(model.isRefreshingHardwareVolume)
    }

    func testOlderSnapshotCannotOverwriteNewerSnapshot() async {
        let transport = OutOfOrderSnapshotTransport()
        let model = ConsoleViewModel(transport: transport)

        let olderRefresh = Task { await model.refresh() }
        await transport.waitForSnapshotRequests(count: 1)
        let newerRefresh = Task { await model.refresh() }
        await transport.waitForSnapshotRequests(count: 2)

        await transport.resumeSnapshot(at: 1, volume: 30)
        await newerRefresh.value
        await transport.resumeSnapshot(at: 0, volume: 10)
        await olderRefresh.value

        XCTAssertEqual(model.left?.volume, 30)
    }

    func testPollingSkipsSnapshotsWhileVolumeInteractionIsActive() async {
        let transport = SnapshotCountingTransport()
        let model = ConsoleViewModel(transport: transport)

        model.beginVolumeInteraction()
        await model.refreshIfIdleForPolling()
        let requestsWhileDragging = await transport.snapshotRequests()
        XCTAssertEqual(requestsWhileDragging, 0)

        model.endVolumeInteraction()
        await model.refreshIfIdleForPolling()
        let requestsAfterDrag = await transport.snapshotRequests()
        XCTAssertEqual(requestsAfterDrag, 1)
    }

    func testVolumeInteractionStateSupportsNestedControls() {
        let model = ConsoleViewModel(transport: SnapshotCountingTransport())

        model.beginVolumeInteraction()
        model.beginVolumeInteraction()
        XCTAssertTrue(model.isVolumeInteractionActive)

        model.endVolumeInteraction()
        XCTAssertTrue(model.isVolumeInteractionActive)

        model.endVolumeInteraction()
        XCTAssertFalse(model.isVolumeInteractionActive)
    }

    func testViewStateCoversHealthyTransitionDegradedAndSystemModes() {
        let healthy = ConsoleViewModel(transport: FixtureTransport())
        healthy.apply(snapshot: .healthy)
        XCTAssertTrue(healthy.canChangeMode)
        XCTAssertFalse(healthy.showsTransition)
        XCTAssertTrue(healthy.showsChannelControls)

        let transitioning = ConsoleViewModel(transport: FixtureTransport())
        transitioning.apply(snapshot: .transitioning)
        XCTAssertFalse(transitioning.canChangeMode)
        XCTAssertTrue(transitioning.showsTransition)
        XCTAssertTrue(transitioning.showsChannelControls)

        let degraded = ConsoleViewModel(transport: FixtureTransport())
        degraded.apply(snapshot: .degraded)
        XCTAssertTrue(degraded.canChangeMode)
        XCTAssertTrue(degraded.showsWarning)
        XCTAssertTrue(degraded.showsChannelControls)

        let system = ConsoleViewModel(transport: FixtureTransport())
        system.apply(snapshot: .system)
        XCTAssertTrue(system.canChangeMode)
        XCTAssertTrue(system.showsChannelControls)
        XCTAssertEqual(system.snapshot?.health, .disabled)
    }
}

private struct FixtureTransport: ControlTransport {
    var snapshot: RuntimeSnapshot = .healthy
    private let recorder = VolumeRecorder()

    func request(_ request: ControlRequest) async throws -> ControlEvent {
        switch request {
        case .snapshot, .subscribe:
            return .snapshot(snapshot)
        case .setAudioMode(let requestId, let mode):
            return .modeChanged(
                requestId: requestId,
                result: ModeTransitionResult(mode: mode, remoteWarning: nil)
            )
        case .setClientVolume(_, let clientId, let percent):
            await recorder.append(.init(clientId: clientId, percent: percent))
            return .success(requestId: "volume")
        default:
            return .success(requestId: request.requestId)
        }
    }

    func volumeRequests() async -> [VolumeRequest] {
        await recorder.values
    }
}

private struct VolumeRequest: Equatable, Sendable {
    let clientId: String
    let percent: Int
}

private actor VolumeRecorder {
    private(set) var values: [VolumeRequest] = []

    func append(_ value: VolumeRequest) {
        values.append(value)
    }
}

private struct DiagnosticsTransport: ControlTransport {
    private let recorder = ServiceRestartRecorder()

    func request(_ request: ControlRequest) async throws -> ControlEvent {
        switch request {
        case .exportDiagnostics(let requestId, _):
            return .diagnostics(
                requestId: requestId,
                json: #"{"health":"healthy","protocolVersion":1}"#
            )
        case .restartService(let requestId, let serviceId):
            await recorder.append(serviceId)
            return .success(requestId: requestId)
        case .snapshot:
            return .snapshot(.healthy)
        default:
            return .success(requestId: request.requestId)
        }
    }

    func restartedServices() async -> [String] {
        await recorder.values
    }
}

private actor ServiceRestartRecorder {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}

private actor HardwareVolumeRefreshTransport: ControlTransport {
    let snapshot: RuntimeSnapshot
    private var hardwareRequests = 0
    private var snapshots = 0

    init(snapshot: RuntimeSnapshot) {
        self.snapshot = snapshot
    }

    func request(_ request: ControlRequest) async throws -> ControlEvent {
        switch request {
        case .refreshHardwareVolume(let requestId):
            hardwareRequests += 1
            return .success(requestId: requestId)
        case .snapshot:
            snapshots += 1
            return .snapshot(snapshotWithHardwareVolume)
        default:
            return .success(requestId: request.requestId)
        }
    }

    func refreshRequests() -> Int {
        hardwareRequests
    }

    func snapshotRequests() -> Int {
        snapshots
    }

    private var snapshotWithHardwareVolume: RuntimeSnapshot {
        var value = snapshot
        value.hardwareVolumes = [
            HardwareVolumeStatus(
                side: "left",
                volumePercent: 100,
                checkedAt: Date(),
                error: nil
            )
        ]
        return value
    }
}

private actor SuspendedModeTransport: ControlTransport {
    let snapshot: RuntimeSnapshot
    private var modeContinuation: CheckedContinuation<ControlEvent, Never>?
    private var requestCount = 0

    init(snapshot: RuntimeSnapshot) {
        self.snapshot = snapshot
    }

    func request(_ request: ControlRequest) async throws -> ControlEvent {
        if case .setAudioMode(let requestId, let mode) = request {
            requestCount += 1
            return await withCheckedContinuation { continuation in
                modeContinuation = continuation
                modeRequestID = requestId
                requestedMode = mode
            }
        }
        return .snapshot(snapshot)
    }

    func waitForModeRequest() async {
        while modeContinuation == nil {
            await Task.yield()
        }
    }

    func modeRequestCount() -> Int {
        requestCount
    }

    func resumeModeRequest() {
        guard let modeContinuation, let modeRequestID, let requestedMode else { return }
        self.modeContinuation = nil
        modeContinuation.resume(returning: .modeChanged(
            requestId: modeRequestID,
            result: ModeTransitionResult(mode: requestedMode, remoteWarning: nil)
        ))
    }

    private var modeRequestID: String?
    private var requestedMode: AudioMode?
}

private actor OutOfOrderSnapshotTransport: ControlTransport {
    private var continuations: [CheckedContinuation<ControlEvent, Never>] = []

    func request(_ request: ControlRequest) async throws -> ControlEvent {
        guard case .snapshot = request else {
            return .success(requestId: request.requestId)
        }
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitForSnapshotRequests(count: Int) async {
        while continuations.count < count {
            await Task.yield()
        }
    }

    func resumeSnapshot(at index: Int, volume: Int) {
        var snapshot = RuntimeSnapshot.healthy
        snapshot.channels[0].volume = volume
        continuations[index].resume(returning: .snapshot(snapshot))
    }
}

private actor SnapshotCountingTransport: ControlTransport {
    private var snapshots = 0

    func request(_ request: ControlRequest) async throws -> ControlEvent {
        switch request {
        case .snapshot:
            snapshots += 1
            return .snapshot(.healthy)
        default:
            return .success(requestId: request.requestId)
        }
    }

    func snapshotRequests() -> Int {
        snapshots
    }
}

private extension ControlRequest {
    var requestId: String {
        switch self {
        case .snapshot(let requestId),
             .subscribe(let requestId),
             .setAudioMode(let requestId, _),
             .restartPair(let requestId),
             .setClientVolume(let requestId, _, _),
             .setClientMute(let requestId, _, _),
             .setClientLatency(let requestId, _, _),
             .refreshHardwareVolume(let requestId),
             .restartService(let requestId, _),
             .exportDiagnostics(let requestId, _):
            return requestId
        }
    }
}

private extension RuntimeSnapshot {
    static let healthy = make(
        mode: .snapcast,
        health: .healthy,
        leftVolume: 50,
        rightVolume: 90,
        serviceState: .running,
        issues: []
    )

    static let transitioning = make(
        mode: .transitioning,
        health: .degraded,
        leftVolume: 50,
        rightVolume: 90,
        serviceState: .running,
        issues: []
    )

    static let degraded = make(
        mode: .snapcast,
        health: .degraded,
        leftVolume: 50,
        rightVolume: 90,
        serviceState: .running,
        issues: ["RightAudio has no connected client"]
    )

    static let system = make(
        mode: .system,
        health: .disabled,
        leftVolume: 50,
        rightVolume: 90,
        serviceState: .disabled,
        issues: []
    )

    private static func make(
        mode: AudioMode,
        health: HealthLevel,
        leftVolume: Int,
        rightVolume: Int,
        serviceState: ServiceState,
        issues: [String]
    ) -> RuntimeSnapshot {
        RuntimeSnapshot(
            protocolVersion: controlProtocolVersion,
            mode: mode,
            health: health,
            services: [
                ServiceStatus(
                    id: "com.snapcast.server",
                    displayName: "Snapserver",
                    state: serviceState,
                    pid: nil,
                    runs: 1,
                    lastExitCode: nil,
                    lastSuccessAgeSeconds: nil,
                    message: nil
                ),
                ServiceStatus(
                    id: "com.snapcast.splitter",
                    displayName: "Splitter",
                    state: serviceState,
                    pid: nil,
                    runs: 1,
                    lastExitCode: nil,
                    lastSuccessAgeSeconds: nil,
                    message: nil
                ),
                ServiceStatus(
                    id: "com.snapcast.wake-recovery",
                    displayName: "Wake Recovery",
                    state: serviceState,
                    pid: nil,
                    runs: 1,
                    lastExitCode: nil,
                    lastSuccessAgeSeconds: nil,
                    message: nil
                )
            ],
            channels: [
                ChannelStatus(
                    side: "left",
                    clientId: "left-client",
                    streamId: "LeftAudio",
                    connected: mode != .system,
                    deviceName: "MacBook Speakers",
                    volume: leftVolume,
                    muted: false,
                    latencyMs: 0,
                    peakDb: -18,
                    rmsDb: -24,
                    clipped: false
                ),
                ChannelStatus(
                    side: "right",
                    clientId: "right-client",
                    streamId: "RightAudio",
                    connected: mode != .system,
                    deviceName: "MacBook Speakers",
                    volume: rightVolume,
                    muted: false,
                    latencyMs: 0,
                    peakDb: -16,
                    rmsDb: -22,
                    clipped: false
                )
            ],
            streams: [],
            issues: issues,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
