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
        } catch {
            sessions = []
        }
    }

    /// Sync: validate each active session is still alive, mark stale ones as done.
    public func sync() {
        do {
            var allSessions = try store.listAll()
            var changed = false

            for i in allSessions.indices {
                let s = allSessions[i]
                guard [.running, .needsInput, .idle].contains(s.status) else { continue }

                let staleness = Date().timeIntervalSince(s.lastEventAt)

                if staleness > 300 { // 5 minutes with no event
                    let hasProcess = s.pid.map { Self.isProcessAlive($0) } ?? false

                    if !hasProcess {
                        allSessions[i].status = .done
                        try? store.write(allSessions[i])
                        changed = true
                    }
                }
            }

            if changed {
                sessions = allSessions.sorted { $0.lastEventAt > $1.lastEventAt }
            }
            lastSyncAt = Date()
        } catch {
            sessions = []
        }
    }

    /// Check if a process is still alive using kill(pid, 0) syscall.
    /// This is ~1000x cheaper than spawning a `ps` subprocess.
    private static func isProcessAlive(_ pid: Int) -> Bool {
        guard pid > 0 else { return false }
        return Darwin.kill(Int32(pid), 0) == 0
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
