import Foundation
import Network

public final class APIServer {
    private var listener: NWListener?
    private let router: APIRouter
    private let queue = DispatchQueue(label: "com.agentping.api", qos: .utility)
    private let requestedPort: UInt16
    private(set) public var actualPort: UInt16 = 0

    /// Port file location: ~/.agentping/port
    private static var portFilePath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agentping/port")
    }

    public init(store: SessionStore, port: UInt16 = 19199) {
        self.requestedPort = port
        self.router = APIRouter(store: store)
    }

    public func start() async throws {
        let port: NWEndpoint.Port
        if requestedPort == 0 {
            // Random port for testing
            port = .any
        } else {
            port = NWEndpoint.Port(rawValue: requestedPort) ?? .any
        }

        let params = NWParameters.tcp
        params.acceptLocalOnly = true

        let listener = try NWListener(using: params, on: port)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let port = listener.port {
                        self?.actualPort = port.rawValue
                        self?.writePortFile()
                    }
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        removePortFile()
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)

        var buffer = Data()
        receiveData(connection: connection, buffer: &buffer)
    }

    private func receiveData(connection: NWConnection, buffer: inout Data) {
        var buffer = buffer
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let data {
                buffer.append(data)
            }

            // Check for oversized request
            if buffer.count > 1_048_576 + 8192 {
                let response = HTTPResponse.error(413, "Payload Too Large", "Request too large")
                self.send(response, on: connection)
                return
            }

            // Try to parse the complete request
            if let request = HTTPRequestParser.parseIfComplete(buffer) {
                let response = self.router.handle(request)
                self.send(response, on: connection)
                return
            }

            // If connection is complete but we couldn't parse, it's malformed
            if isComplete || error != nil {
                let response = HTTPResponse.error(400, "Bad Request", "Malformed HTTP request")
                self.send(response, on: connection)
                return
            }

            // Otherwise, keep reading
            self.receiveData(connection: connection, buffer: &buffer)
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        let data = response.serialize()
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func writePortFile() {
        let url = Self.portFilePath
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "\(actualPort)".write(to: url, atomically: true, encoding: .utf8)
    }

    private func removePortFile() {
        try? FileManager.default.removeItem(at: Self.portFilePath)
    }

    /// Read the port from the port file. Returns nil if not available.
    public static func readPort() -> UInt16? {
        guard let content = try? String(contentsOf: portFilePath, encoding: .utf8),
              let port = UInt16(content.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return port
    }
}
