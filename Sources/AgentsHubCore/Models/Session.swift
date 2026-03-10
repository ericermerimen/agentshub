import Foundation

public enum SessionStatus: String, Codable, CaseIterable {
    case running
    case needsInput = "needs-input"
    case idle
    case done
    case error
    case unavailable
}

public struct Session: Codable, Identifiable, Equatable {
    public let id: String
    public var name: String?
    public var status: SessionStatus
    public var app: String?
    public var pid: Int?
    public var windowId: Int?
    public var cwd: String?
    public var file: String?
    public var startedAt: Date
    public var lastEventAt: Date
    public var notifications: Bool
    public var costUsd: Double?

    public init(
        id: String,
        name: String? = nil,
        status: SessionStatus = .running,
        app: String? = nil,
        pid: Int? = nil,
        windowId: Int? = nil,
        cwd: String? = nil,
        file: String? = nil,
        startedAt: Date = Date(),
        lastEventAt: Date = Date(),
        notifications: Bool = true,
        costUsd: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.app = app
        self.pid = pid
        self.windowId = windowId
        self.cwd = cwd
        self.file = file
        self.startedAt = startedAt
        self.lastEventAt = lastEventAt
        self.notifications = notifications
        self.costUsd = costUsd
    }
}

extension JSONDecoder {
    public static let agentsHub: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension JSONEncoder {
    public static let agentsHub: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
