import Foundation
import Combine

public final class SessionManager: ObservableObject {
    @Published public private(set) var sessions: [Session] = []
    @Published public private(set) var lastSyncAt: Date?

    public let store: SessionStore

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
            lastSyncAt = Date()
        } catch {
            sessions = []
        }
    }

    /// Sync: re-read all session files from disk.
    /// Sessions move to History only via explicit SessionEnd hook event or manual "Mark as Done".
    public func sync() {
        reload()
    }

    public func clearUnavailable() {
        do {
            try store.deleteUnavailable()
            reload()
        } catch {}
    }

    public func clearHistory() {
        do {
            try store.deleteHistory()
            reload()
        } catch {}
    }

    public func deleteSession(id: String) {
        do {
            try store.delete(id: id)
            reload()
        } catch {}
    }

    /// Remove finished sessions older than 24 hours.
    public func autoPurgeOldSessions() {
        do {
            try store.deleteOlderThan(24 * 60 * 60)
            reload()
        } catch {}
    }

    public func markReviewed(id: String) {
        guard var session = sessions.first(where: { $0.id == id }) else { return }
        session.reviewedAt = Date()
        updateSession(session)
    }

    public func togglePin(id: String) {
        guard var session = sessions.first(where: { $0.id == id }) else { return }
        session.pinned = !session.pinned
        updateSession(session)
    }

    public var totalCost: Double {
        sessions.compactMap(\.costUsd).reduce(0, +)
    }

    public func updateSession(_ session: Session) {
        do {
            try store.write(session)
            reload()
        } catch {}
    }
}
