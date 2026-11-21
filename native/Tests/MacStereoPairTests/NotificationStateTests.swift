import Foundation
import StereoPairCore
import XCTest
@testable import MacStereoPair

final class NotificationStateTests: XCTestCase {
    func testClientOfflineRaisesOneNotificationAfterGraceAndResetsAfterRecovery() {
        var tracker = IncidentTracker(now: .reference)
        let offline = makeSnapshot(rightConnected: false)
        let recovered = makeSnapshot(rightConnected: true)

        XCTAssertEqual(tracker.update(snapshot: offline, now: .reference), [])
        XCTAssertEqual(
            tracker.update(snapshot: offline, now: .reference.addingTimeInterval(5)),
            []
        )
        XCTAssertEqual(
            tracker.update(snapshot: offline, now: .reference.addingTimeInterval(6)),
            [.raised(Incident(kind: .channelOffline, subject: "RightAudio"))]
        )
        XCTAssertEqual(
            tracker.update(snapshot: offline, now: .reference.addingTimeInterval(8)),
            []
        )
        XCTAssertEqual(
            tracker.update(snapshot: recovered, now: .reference.addingTimeInterval(9)),
            [.resolved(Incident(kind: .channelOffline, subject: "RightAudio"))]
        )
    }

    func testSystemModeDisabledServicesNeverRaiseFailureNotifications() {
        var tracker = IncidentTracker(now: .reference)
        let system = makeSnapshot(
            mode: .system,
            health: .disabled,
            rightConnected: false,
            serviceState: .disabled,
            issues: []
        )

        XCTAssertEqual(tracker.update(snapshot: system, now: .reference), [])
        XCTAssertEqual(
            tracker.update(snapshot: system, now: .reference.addingTimeInterval(60)),
            []
        )
    }

    func testFailedServiceRaisesAfterRestartGraceAndOnlyOnce() {
        var tracker = IncidentTracker(now: .reference)
        let failed = makeSnapshot(serviceState: .failed)

        XCTAssertEqual(tracker.update(snapshot: failed, now: .reference), [])
        XCTAssertEqual(
            tracker.update(snapshot: failed, now: .reference.addingTimeInterval(3)),
            [
                .raised(Incident(kind: .serviceFailure, subject: "com.snapcast.server")),
                .raised(Incident(kind: .serviceFailure, subject: "com.snapcast.wake-recovery"))
            ]
        )
        XCTAssertEqual(
            tracker.update(snapshot: failed, now: .reference.addingTimeInterval(4)),
            []
        )
    }

    func testRoutingIssueRecoversIndependentlyOfOtherIncidents() {
        var tracker = IncidentTracker(now: .reference)
        let degraded = makeSnapshot(issues: ["LeftAudio does not use 48000:24:1"])
        let healthy = makeSnapshot()

        XCTAssertEqual(
            tracker.update(snapshot: degraded, now: .reference),
            [.raised(Incident(kind: .routing, subject: "LeftAudio does not use 48000:24:1"))]
        )
        XCTAssertEqual(
            tracker.update(snapshot: healthy, now: .reference.addingTimeInterval(1)),
            [.resolved(Incident(kind: .routing, subject: "LeftAudio does not use 48000:24:1"))]
        )
    }

    func testPersistedActiveIncidentIsNotRepeatedAfterAppRestart() {
        let incident = Incident(kind: .channelOffline, subject: "RightAudio")
        var tracker = IncidentTracker(
            activeIncidents: [incident],
            now: .reference
        )
        let offline = makeSnapshot(rightConnected: false)
        let recovered = makeSnapshot(rightConnected: true)

        XCTAssertEqual(
            tracker.update(snapshot: offline, now: .reference.addingTimeInterval(8)),
            []
        )
        XCTAssertEqual(
            tracker.update(snapshot: recovered, now: .reference.addingTimeInterval(9)),
            [.resolved(incident)]
        )
    }

    private func makeSnapshot(
        mode: AudioMode = .snapcast,
        health: HealthLevel = .healthy,
        rightConnected: Bool = true,
        serviceState: ServiceState = .running,
        issues: [String] = []
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
                    pid: serviceState == .running ? 42 : nil,
                    runs: 1,
                    lastExitCode: serviceState == .failed ? 1 : nil,
                    lastSuccessAgeSeconds: nil,
                    message: nil
                ),
                ServiceStatus(
                    id: "com.snapcast.wake-recovery",
                    displayName: "Wake Recovery",
                    state: serviceState,
                    pid: serviceState == .running ? 43 : nil,
                    runs: 1,
                    lastExitCode: serviceState == .failed ? 1 : nil,
                    lastSuccessAgeSeconds: nil,
                    message: nil
                )
            ],
            channels: [
                ChannelStatus(
                    side: "left",
                    clientId: "left-client",
                    streamId: "LeftAudio",
                    connected: true,
                    deviceName: "Speakers",
                    volume: 100,
                    muted: false,
                    latencyMs: 0,
                    peakDb: nil,
                    rmsDb: nil,
                    clipped: false
                ),
                ChannelStatus(
                    side: "right",
                    clientId: "right-client",
                    streamId: "RightAudio",
                    connected: rightConnected,
                    deviceName: "Speakers",
                    volume: 100,
                    muted: false,
                    latencyMs: 0,
                    peakDb: nil,
                    rmsDb: nil,
                    clipped: false
                )
            ],
            streams: [],
            issues: issues,
            updatedAt: .reference
        )
    }
}

private extension Date {
    static let reference = Date(timeIntervalSince1970: 1_700_000_000)
}
