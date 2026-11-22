import Foundation
import StereoPairCore

protocol ControlTransport: Sendable {
    func request(_ request: ControlRequest) async throws -> ControlEvent
}

struct UnixControlTransport: ControlTransport {
    let socketURL: URL

    func request(_ request: ControlRequest) async throws -> ControlEvent {
        let timeout: TimeInterval = switch request {
        case .setAudioMode, .restartPair:
            45
        case .refreshHardwareVolume:
            20
        case .restartService:
            12
        default:
            5
        }
        return try await Task.detached {
            try UnixControlClient(socketURL: socketURL, timeout: timeout).send(request)
        }.value
    }
}

enum AgentConnectionState: Equatable {
    case connected
    case failed
}
