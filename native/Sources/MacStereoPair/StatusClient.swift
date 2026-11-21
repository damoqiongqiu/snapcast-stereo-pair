import Foundation
import StereoPairCore

protocol ControlTransport: Sendable {
    func request(_ request: ControlRequest) async throws -> ControlEvent
}

struct UnixControlTransport: ControlTransport {
    let socketURL: URL

    func request(_ request: ControlRequest) async throws -> ControlEvent {
        try await Task.detached {
            try UnixControlClient(socketURL: socketURL).send(request)
        }.value
    }
}

enum AgentConnectionState: Equatable {
    case connected
    case failed
}
