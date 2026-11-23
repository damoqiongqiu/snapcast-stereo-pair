import Foundation

public struct SnapserverStatus: Equatable, Sendable {
    public var channels: [ChannelStatus]
    public var streams: [StreamStatus]
    public var healthIssues: [String]

    public init(channels: [ChannelStatus], streams: [StreamStatus], healthIssues: [String]) {
        self.channels = channels
        self.streams = streams
        self.healthIssues = healthIssues
    }

    public static func decode(
        responseData: Data,
        now: Date = Date(),
        staleAfter: TimeInterval = 6
    ) throws -> SnapserverStatus {
        let response = try JSONDecoder().decode(StatusResponse.self, from: responseData)
        return normalize(
            server: response.result.server,
            now: now,
            staleAfter: max(1, staleAfter)
        )
    }

    private static func normalize(
        server: ServerPayload,
        now: Date,
        staleAfter: TimeInterval
    ) -> SnapserverStatus {
        var channels: [ChannelStatus] = []
        var streamClients: [String: [String]] = [:]
        for group in server.groups {
            for client in group.clients {
                let connected = isLive(client, now: now, staleAfter: staleAfter)
                if connected {
                    streamClients[group.streamID, default: []].append(client.id)
                }
                channels.append(ChannelStatus(
                    side: group.streamID == "LeftAudio" ? "left" : "right",
                    clientId: client.id,
                    streamId: group.streamID,
                    connected: connected,
                    deviceName: nil,
                    volume: client.config.volume.percent,
                    muted: client.config.volume.muted,
                    latencyMs: client.config.latency,
                    peakDb: nil,
                    rmsDb: nil,
                    clipped: false
                ))
            }
        }

        let streams = server.streams.map {
            StreamStatus(
                id: $0.id,
                state: $0.status,
                sampleFormat: $0.uri.query.sampleFormat,
                clientIds: streamClients[$0.id] ?? []
            )
        }

        var issues: [String] = []
        for id in ["LeftAudio", "RightAudio"] {
            let count = streamClients[id]?.count ?? 0
            if count != 1 {
                issues.append("\(id) has no connected client")
            }
            if server.streams.first(where: { $0.id == id })?.uri.query.sampleFormat != "48000:24:1" {
                issues.append("\(id) does not use 48000:24:1")
            }
        }
        return SnapserverStatus(channels: channels, streams: streams, healthIssues: issues)
    }

    private static func isLive(
        _ client: ClientPayload,
        now: Date,
        staleAfter: TimeInterval
    ) -> Bool {
        guard client.connected else { return false }
        guard let lastSeen = client.lastSeen else { return true }
        return now.timeIntervalSince(lastSeen.date) <= staleAfter
    }
}

private struct StatusResponse: Decodable {
    let result: StatusResult
}

private struct StatusResult: Decodable {
    let server: ServerPayload
}

private struct ServerPayload: Decodable {
    let groups: [GroupPayload]
    let streams: [StreamPayload]
}

private struct GroupPayload: Decodable {
    let id: String
    let streamID: String
    let clients: [ClientPayload]

    enum CodingKeys: String, CodingKey {
        case id
        case streamID = "stream_id"
        case clients
    }
}

private struct ClientPayload: Decodable {
    let id: String
    let connected: Bool
    let config: ClientConfigPayload
    let lastSeen: TimestampPayload?
}

private struct ClientConfigPayload: Decodable {
    let volume: VolumePayload
    let latency: Int
}

private struct VolumePayload: Decodable {
    let percent: Int
    let muted: Bool
}

private struct TimestampPayload: Decodable {
    let sec: Int
    let usec: Int

    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(sec) + (TimeInterval(usec) / 1_000_000))
    }
}

private struct StreamPayload: Decodable {
    let id: String
    let status: String
    let uri: StreamURIPayload
}

private struct StreamURIPayload: Decodable {
    let query: StreamQueryPayload
}

private struct StreamQueryPayload: Decodable {
    let sampleFormat: String?

    enum CodingKeys: String, CodingKey {
        case sampleFormat = "sampleformat"
    }
}
