import Foundation
import Combine

public final class SessionManager: ObservableObject {
    @Published public private(set) var sessions: [Session] = []

    private let store: SessionStore

    public init(store: SessionStore? = nil) {
        self.store = store ?? SessionStore()
    }

    public var activeSessions: [Session] {
        sessions.filter { [.running, .needsInput, .idle].contains($0.status) }
    }

    public var historySessions: [Session] {
        sessions.filter { [.done, .error].contains($0.status) }
    }

    public var needsInputCount: Int {
        sessions.filter { $0.status == .needsInput }.count
    }

    public var unavailableCount: Int {
        sessions.filter { $0.status == .unavailable }.count
    }

    public func reload() {
        do {
            sessions = try store.listAll()
                .sorted { $0.lastEventAt > $1.lastEventAt }
        } catch {
            sessions = []
        }
    }

    public func clearUnavailable() {
        do {
            try store.deleteUnavailable()
            reload()
        } catch {}
    }

    public func updateSession(_ session: Session) {
        do {
            try store.write(session)
            reload()
        } catch {}
    }
}
