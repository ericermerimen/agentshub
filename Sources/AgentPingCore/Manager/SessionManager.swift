import Foundation
import Combine

public final class SessionManager: ObservableObject {
    @Published public private(set) var sessions: [Session] = []

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
        let activePids = Self.runningClaudePids()

        do {
            var allSessions = try store.listAll()
            var changed = false

            for i in allSessions.indices {
                let s = allSessions[i]
                guard [.running, .needsInput, .idle].contains(s.status) else { continue }

                // Check 1: if session has a transcript path, check the file's mtime
                // Check 2: if no event in 5+ minutes and no matching Claude process, mark done
                let staleness = Date().timeIntervalSince(s.lastEventAt)

                if staleness > 300 { // 5 minutes with no event
                    // Check if any Claude process is still associated
                    let hasProcess = s.pid.map { activePids.contains($0) } ?? false

                    if !hasProcess {
                        allSessions[i].status = .done
                        try? store.write(allSessions[i])
                        changed = true
                    }
                }
            }

            if changed {
                reload()
            } else {
                sessions = allSessions.sorted { $0.lastEventAt > $1.lastEventAt }
            }
        } catch {
            sessions = []
        }
    }

    /// Find PIDs of running claude/Claude Code processes.
    private static func runningClaudePids() -> Set<Int> {
        var pids = Set<Int>()
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-eo", "pid,comm"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.lowercased().contains("claude") {
                        let parts = trimmed.split(separator: " ", maxSplits: 1)
                        if let pidStr = parts.first, let pid = Int(pidStr) {
                            pids.insert(pid)
                        }
                    }
                }
            }
        } catch {}

        return pids
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
