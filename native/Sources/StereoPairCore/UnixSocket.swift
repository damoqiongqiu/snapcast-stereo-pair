import Darwin
import Foundation

public enum UnixSocketError: Error, LocalizedError {
    case create(Int32)
    case bind(Int32)
    case listen(Int32)
    case connect(Int32)
    case peerRejected
    case invalidMessage

    public var errorDescription: String? {
        switch self {
        case .create(let code): "Could not create control socket: \(code)"
        case .bind(let code): "Could not bind control socket: \(code)"
        case .listen(let code): "Could not listen on control socket: \(code)"
        case .connect(let code): "Could not connect to control Agent: \(code)"
        case .peerRejected: "Control socket peer is not the current user"
        case .invalidMessage: "Control protocol message is invalid"
        }
    }
}

public final class UnixControlServer: @unchecked Sendable {
    public typealias Handler = @Sendable (ControlRequest) async -> ControlEvent

    private let socketURL: URL
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.snapcast.stereo-pair.control")
    private var listeningFD: Int32 = -1

    public init(socketURL: URL, handler: @escaping Handler) {
        self.socketURL = socketURL
        self.handler = handler
    }

    public func start() throws {
        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        unlink(socketURL.path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UnixSocketError.create(errno) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketURL.path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw UnixSocketError.bind(ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.copyBytes(from: pathBytes)
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            close(fd)
            throw UnixSocketError.bind(code)
        }
        chmod(socketURL.path, S_IRUSR | S_IWUSR)
        guard listen(fd, 8) == 0 else {
            let code = errno
            close(fd)
            throw UnixSocketError.listen(code)
        }
        listeningFD = fd

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.acceptLoop()
        }
    }

    public func stop() {
        if listeningFD >= 0 {
            shutdown(listeningFD, SHUT_RDWR)
            close(listeningFD)
            listeningFD = -1
        }
        unlink(socketURL.path)
    }

    private func acceptLoop() {
        while listeningFD >= 0 {
            let clientFD = accept(listeningFD, nil, nil)
            if clientFD < 0 {
                if errno == EINTR { continue }
                return
            }
            Task { [weak self] in
                await self?.serve(clientFD: clientFD)
            }
        }
    }

    private func serve(clientFD: Int32) async {
        defer { close(clientFD) }
        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(clientFD, &peerUID, &peerGID) == 0, peerUID == getuid() else {
            return
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(clientFD, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        guard let line = data.split(separator: 0x0A).first,
              let request = try? JSONDecoder().decode(ControlRequest.self, from: Data(line)) else {
            return
        }
        let response = await handler(request)
        guard var encoded = try? JSONEncoder().encode(response) else { return }
        encoded.append(0x0A)
        encoded.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let count = write(clientFD, base.advanced(by: offset), raw.count - offset)
                if count <= 0 { break }
                offset += count
            }
        }
    }
}

public struct UnixControlClient: Sendable {
    private let socketURL: URL

    public init(socketURL: URL) {
        self.socketURL = socketURL
    }

    public func send(_ request: ControlRequest) throws -> ControlEvent {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UnixSocketError.create(errno) }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketURL.path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw UnixSocketError.connect(ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &address.sun_path) {
            $0.copyBytes(from: pathBytes)
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { throw UnixSocketError.connect(errno) }

        var encoded = try JSONEncoder().encode(request)
        encoded.append(0x0A)
        encoded.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            _ = write(fd, base, raw.count)
        }
        shutdown(fd, SHUT_WR)

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        guard let line = data.split(separator: 0x0A).first else {
            throw UnixSocketError.invalidMessage
        }
        return try JSONDecoder().decode(ControlEvent.self, from: Data(line))
    }
}
