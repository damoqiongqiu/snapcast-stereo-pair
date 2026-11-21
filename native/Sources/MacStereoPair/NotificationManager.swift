import Foundation
import StereoPairCore
import UserNotifications

enum IncidentKind: String, Codable, Hashable, Sendable {
    case serviceFailure
    case channelOffline
    case routing
    case wakeRecovery

    var gracePeriod: TimeInterval {
        switch self {
        case .serviceFailure:
            return 3
        case .channelOffline:
            return 6
        case .routing:
            return 0
        case .wakeRecovery:
            return 30
        }
    }
}

struct Incident: Codable, Hashable, Sendable {
    let kind: IncidentKind
    let subject: String

    var identifier: String {
        "stereo-pair.\(kind.rawValue).\(subject)"
    }
}

enum IncidentTransition: Equatable, Sendable {
    case raised(Incident)
    case resolved(Incident)
}

struct IncidentTracker {
    private var pendingSince: [Incident: Date] = [:]
    private var active: Set<Incident> = []

    init(activeIncidents: Set<Incident> = [], now: Date = Date()) {
        active = activeIncidents
    }

    var activeIncidents: Set<Incident> {
        active
    }

    mutating func update(snapshot: RuntimeSnapshot, now: Date) -> [IncidentTransition] {
        let candidates = candidateIncidents(in: snapshot)
        let candidateSet = Set(candidates)
        var transitions: [IncidentTransition] = []

        for incident in candidates where !active.contains(incident) {
            let startedAt = pendingSince[incident] ?? now
            pendingSince[incident] = startedAt
            if now.timeIntervalSince(startedAt) >= incident.kind.gracePeriod {
                pendingSince.removeValue(forKey: incident)
                active.insert(incident)
                transitions.append(.raised(incident))
            }
        }

        let resolved = active
            .filter { !candidateSet.contains($0) }
            .sorted(by: incidentSort)
        for incident in resolved {
            active.remove(incident)
            transitions.append(.resolved(incident))
        }

        pendingSince = pendingSince.filter { candidateSet.contains($0.key) }
        return transitions
    }

    private func candidateIncidents(in snapshot: RuntimeSnapshot) -> [Incident] {
        guard snapshot.mode != .system, snapshot.mode != .transitioning else {
            return []
        }

        var incidents: [Incident] = []
        for service in snapshot.services
            where service.state == .failed || service.state == .crashLoop {
            incidents.append(Incident(kind: .serviceFailure, subject: service.id))
        }
        for channel in snapshot.channels where !channel.connected {
            incidents.append(Incident(kind: .channelOffline, subject: channel.streamId))
            if channel.streamId == "LeftAudio" || channel.streamId == "RightAudio" {
                incidents.append(Incident(kind: .wakeRecovery, subject: channel.streamId))
            }
        }
        for issue in snapshot.issues {
            incidents.append(Incident(kind: .routing, subject: issue))
        }
        return incidents
    }

    private func incidentSort(_ lhs: Incident, _ rhs: Incident) -> Bool {
        if lhs.kind.rawValue == rhs.kind.rawValue {
            return lhs.subject < rhs.subject
        }
        return lhs.kind.rawValue < rhs.kind.rawValue
    }
}

@MainActor
final class NotificationManager: ObservableObject {
    @Published private(set) var authorizationGranted = false

    private let center: UNUserNotificationCenter
    private var tracker: IncidentTracker
    private let defaults: UserDefaults

    private static let setupCompleteKey = "stereo-pair.setup-complete"
    private static let activeIncidentsKey = "stereo-pair.active-incidents"

    init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard
    ) {
        self.center = center
        self.defaults = defaults
        let data = defaults.data(forKey: Self.activeIncidentsKey)
        let active = data.flatMap {
            try? JSONDecoder().decode(Set<Incident>.self, from: $0)
        } ?? []
        tracker = IncidentTracker(activeIncidents: active)
    }

    var setupComplete: Bool {
        defaults.bool(forKey: Self.setupCompleteKey)
    }

    func markSetupComplete() async {
        defaults.set(true, forKey: Self.setupCompleteKey)
        do {
            authorizationGranted = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            authorizationGranted = false
        }
    }

    func process(snapshot: RuntimeSnapshot, language: AppLanguage) async {
        guard setupComplete else { return }
        let transitions = tracker.update(snapshot: snapshot, now: Date())
        if let data = try? JSONEncoder().encode(tracker.activeIncidents) {
            defaults.set(data, forKey: Self.activeIncidentsKey)
        }
        for transition in transitions {
            switch transition {
            case .raised(let incident):
                await schedule(incident, language: language)
            case .resolved(let incident):
                center.removePendingNotificationRequests(withIdentifiers: [incident.identifier])
                center.removeDeliveredNotifications(withIdentifiers: [incident.identifier])
            }
        }
    }

    private func schedule(_ incident: Incident, language: AppLanguage) async {
        let content = UNMutableNotificationContent()
        content.title = language.text("notification.\(incident.kind.rawValue).title")
        content.body = language.format(
            "notification.\(incident.kind.rawValue).bodyFormat",
            displaySubject(for: incident)
        )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: incident.identifier,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    private func displaySubject(for incident: Incident) -> String {
        switch incident.subject {
        case "com.snapcast.server":
            return "Snapserver"
        case "com.snapcast.splitter":
            return "Splitter"
        case "com.snapcast.local-client":
            return "Local Client"
        case "com.snapcast.wake-recovery":
            return "Wake Recovery"
        default:
            return incident.subject
        }
    }
}
