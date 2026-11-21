import Foundation
import StereoPairCore

let socketURL =
    if let override = ProcessInfo.processInfo.environment["SNAPCAST_CONTROL_SOCKET"] {
        URL(fileURLWithPath: override)
    } else {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Snapcast/run/control.sock")
    }
let requestId = UUID().uuidString
let command = CommandLine.arguments.dropFirst().first ?? "status"
let timeout: TimeInterval = switch command {
case "start", "stop", "restart":
    45
default:
    5
}
let client = UnixControlClient(socketURL: socketURL, timeout: timeout)

do {
    let event: ControlEvent
    switch command {
    case "status":
        event = try client.send(.snapshot(requestId: requestId))
    case "start":
        event = try client.send(.setAudioMode(requestId: requestId, audioMode: .snapcast))
    case "stop":
        event = try client.send(.setAudioMode(requestId: requestId, audioMode: .system))
    case "restart":
        event = try client.send(.restartPair(requestId: requestId))
    case "diagnostics":
        event = try client.send(.exportDiagnostics(requestId: requestId, redacted: true))
    default:
        FileHandle.standardError.write(Data("Usage: mac-stereo-pairctl {status|start|stop|restart|diagnostics}\n".utf8))
        exit(2)
    }

    let data = try JSONEncoder().encode(event)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
