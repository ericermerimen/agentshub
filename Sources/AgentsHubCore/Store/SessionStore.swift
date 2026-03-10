import Foundation

public final class SessionStore {
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agentshub/sessions")
    }

    private func filePath(for id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
    }

    private func ensureDirectory() throws {
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    public func write(_ session: Session) throws {
        try ensureDirectory()
        let data = try JSONEncoder.agentsHub.encode(session)
        try data.write(to: filePath(for: session.id), options: .atomic)
    }

    public func read(id: String) throws -> Session? {
        let path = filePath(for: id)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path)
        return try JSONDecoder.agentsHub.decode(Session.self, from: data)
    }

    public func listAll() throws -> [Session] {
        try ensureDirectory()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return try files.compactMap { url in
            let data = try Data(contentsOf: url)
            return try? JSONDecoder.agentsHub.decode(Session.self, from: data)
        }
    }

    public func delete(id: String) throws {
        let path = filePath(for: id)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }

    @discardableResult
    public func deleteUnavailable() throws -> Int {
        let sessions = try listAll()
        var count = 0
        for session in sessions where session.status == .unavailable {
            try delete(id: session.id)
            count += 1
        }
        return count
    }
}
