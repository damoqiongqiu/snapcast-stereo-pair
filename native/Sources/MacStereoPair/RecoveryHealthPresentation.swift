import Foundation
import StereoPairCore

enum RecoveryHealthPresentation {
    static let maximumPairingSuccessAge: TimeInterval = 45

    static func effectiveState(for service: ServiceStatus?) -> ServiceState? {
        guard let service else { return nil }
        guard service.id == "com.snapcast.pairing",
              service.state == .inactive,
              service.lastExitCode == 0,
              let successAge = service.lastSuccessAgeSeconds,
              successAge >= 0,
              successAge <= maximumPairingSuccessAge else {
            return service.state
        }
        return .running
    }
}
