import Foundation
import Network

#if os(macOS)

enum BroadcastServerError: LocalizedError {
    case noPortAvailable

    var errorDescription: String? {
        "사용 가능한 로컬 포트를 찾지 못했습니다."
    }
}

/// A minimal HTTP server bound to loopback only. Serves a player page at "/" and a
/// continuously chunked ADTS/AAC byte stream at "/stream.aac" that Safari's <audio> element
/// can play live, the same technique internet radio stations use.
nonisolated final class BroadcastServer {
    private let queue = DispatchQueue(label: "com.colsonmixer.broadcast")
    private var listener: NWListener?
    private var streamingConnections: [ObjectIdentifier: NWConnection] = [:]

    private(set) var port: UInt16 = 0
    var onClientCountChanged: (@Sendable (Int) -> Void)?

    func start(preferredPort: UInt16 = 17320) throws {
        stop()

        var lastError: Error?
        for candidatePort in preferredPort...(preferredPort + 9) {
            guard let nwPort = NWEndpoint.Port(rawValue: candidatePort) else { continue }
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: nwPort)
            do {
                let newListener = try NWListener(using: parameters, on: nwPort)
                newListener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }
                newListener.start(queue: queue)
                listener = newListener
                port = candidatePort
                return
            } catch {
                lastError = error
            }
        }
        throw lastError ?? BroadcastServerError.noPortAvailable
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            for connection in streamingConnections.values {
                connection.cancel()
            }
            streamingConnections.removeAll()
            port = 0
        }
    }

    /// Wraps one encoded AAC packet in an HTTP chunk and fans it out to every connected client.
    func broadcast(_ data: Data) {
        let chunk = Self.chunkFrame(data)
        queue.async { [weak self] in
            guard let self else { return }
            for connection in self.streamingConnections.values {
                connection.send(content: chunk, completion: .idempotent)
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self, let data, let requestText = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            let firstLine = requestText.split(separator: "\r\n").first.map(String.init) ?? ""
            let path = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? "/"

            switch path {
            case "/stream.aac":
                self.beginStreaming(on: connection)
            case "/":
                self.respondWithPlayerPage(on: connection)
            default:
                self.respondNotFound(on: connection)
            }
        }
    }

    private func beginStreaming(on connection: NWConnection) {
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: audio/aac\r\nTransfer-Encoding: chunked\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n"
        connection.send(content: Data(headers.utf8), completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            let id = ObjectIdentifier(connection)
            self.streamingConnections[id] = connection
            self.onClientCountChanged?(self.streamingConnections.count)
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed, .cancelled:
                    self?.remove(id)
                default:
                    break
                }
            }
        })
    }

    private func respondWithPlayerPage(on connection: NWConnection) {
        let body = Data(Self.playerHTML.utf8)
        var response = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func respondNotFound(on connection: NWConnection) {
        let body = Data("Not Found".utf8)
        var response = Data("HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func remove(_ id: ObjectIdentifier) {
        queue.async { [weak self] in
            guard let self else { return }
            self.streamingConnections.removeValue(forKey: id)
            self.onClientCountChanged?(self.streamingConnections.count)
        }
    }

    private static func chunkFrame(_ data: Data) -> Data {
        var frame = Data(String(data.count, radix: 16).utf8)
        frame.append(contentsOf: [0x0D, 0x0A])
        frame.append(data)
        frame.append(contentsOf: [0x0D, 0x0A])
        return frame
    }

    private static let playerHTML = """
    <!DOCTYPE html>
    <html lang="ko">
    <head>
    <meta charset="utf-8">
    <title>콜슨믹서 방송</title>
    <style>
    body { font-family: -apple-system, sans-serif; background: #111; color: #eee; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
    .player { text-align: center; }
    audio { margin-top: 16px; width: 320px; }
    </style>
    </head>
    <body>
    <div class="player">
    <h1>콜슨믹서 방송 중</h1>
    <audio controls autoplay src="/stream.aac"></audio>
    </div>
    </body>
    </html>
    """
}

#endif
