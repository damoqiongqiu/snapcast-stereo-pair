import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int)
    case boolean(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }
}

public enum SnapserverClientError: Error {
    case invalidResponse
    case rpc(String)
    case http(Int)
}

public actor SnapserverClient {
    private struct RPCRequest: Encodable {
        let id: String
        let jsonrpc = "2.0"
        let method: String
        let params: JSONValue?
    }

    private struct RPCResponse: Decodable {
        let result: JSONValue?
        let error: RPCError?
    }

    private struct RPCError: Decodable {
        let message: String
    }

    private let endpoint: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(endpoint: URL = URL(string: "http://127.0.0.1:1780/jsonrpc")!) {
        self.endpoint = endpoint
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        self.session = URLSession(configuration: configuration)
    }

    public func getStatus() async throws -> SnapserverStatus {
        let data = try await rpc(id: "status", method: "Server.GetStatus", params: nil)
        return try SnapserverStatus.decode(responseData: data)
    }

    public func setVolume(clientId: String, percent: Int) async throws {
        _ = try await rpc(
            id: "volume-\(clientId)",
            method: "Client.SetVolume",
            params: .object([
                "id": .string(clientId),
                "volume": .object([
                    "percent": .integer(min(100, max(0, percent))),
                    "muted": .boolean(false)
                ])
            ])
        )
    }

    public func setMute(clientId: String, muted: Bool) async throws {
        _ = try await rpc(
            id: "mute-\(clientId)",
            method: "Client.SetVolume",
            params: .object([
                "id": .string(clientId),
                "volume": .object(["muted": .boolean(muted)])
            ])
        )
    }

    public func setLatency(clientId: String, milliseconds: Int) async throws {
        _ = try await rpc(
            id: "latency-\(clientId)",
            method: "Client.SetLatency",
            params: .object([
                "id": .string(clientId),
                "latency": .integer(min(500, max(0, milliseconds)))
            ])
        )
    }

    private func rpc(id: String, method: String, params: JSONValue?) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(RPCRequest(id: id, method: method, params: params))

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw SnapserverClientError.http(status)
        }
        let envelope = try decoder.decode(RPCResponse.self, from: data)
        if let error = envelope.error {
            throw SnapserverClientError.rpc(error.message)
        }
        guard envelope.result != nil else {
            throw SnapserverClientError.invalidResponse
        }
        return data
    }
}
