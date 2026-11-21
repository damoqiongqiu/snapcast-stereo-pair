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
    case modeChanged(requestId: String, result: ModeTransitionResult)
    case error(requestId: String, message: String)
    case success(requestId: String)
}
