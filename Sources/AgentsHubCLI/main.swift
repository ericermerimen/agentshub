import Foundation
import ArgumentParser
import AgentsHubCore

struct AgentsHubCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agentshub",
        abstract: "AgentsHub CLI - manage Claude Code sessions",
        subcommands: [Report.self, List.self, Status.self, Clear.self, Delete.self]
    )
}

struct Report: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Report a session event (called by hooks)")

    @Option(name: .long, help: "Session ID")
    var session: String?

    @Option(name: .long, help: "Event type: tool-use, needs-input, stopped, error")
    var event: String

    @Option(name: .long, help: "Task name")
    var name: String?

    @Option(name: .long, help: "Current file")
    var file: String?

    /// JSON payload from stdin (Claude Code hooks pass session_id and cwd here)
    private struct StdinPayload: Decodable {
        let session_id: String?
        let cwd: String?
        let transcript_path: String?
    }

    /// Map TERM_PROGRAM env var to a display name
    private static func detectApp() -> String? {
        guard let term = ProcessInfo.processInfo.environment["TERM_PROGRAM"] else { return nil }
        switch term.lowercased() {
        case "ghostty":                return "Ghostty"
        case "vscode":                 return "VSCode"
        case "iterm.app":              return "iTerm"
        case "apple_terminal":         return "Terminal"
        case "warpterminal":           return "Warp"
        case "alacritty":              return "Alacritty"
        case "kitty":                  return "kitty"
        case "wezterm":                return "WezTerm"
        case "tmux":                   return "tmux"
        default:                       return term
        }
    }

    private func readStdinPayload() -> StdinPayload? {
        let data = FileHandle.standardInput.availableData
        guard !data.isEmpty else {
            return nil
        }
        return try? JSONDecoder().decode(StdinPayload.self, from: data)
    }

    func run() throws {
        let stdin = readStdinPayload()
        guard let sessionId = session ?? stdin?.session_id else {
            throw ValidationError("Session ID is required via --session or stdin JSON")
        }
        let handler = ReportHandler()
        try handler.handle(
            sessionId: sessionId,
            event: event,
            name: name,
            file: file,
            cwd: stdin?.cwd,
            transcriptPath: stdin?.transcript_path,
            app: Self.detectApp()
        )
    }
}

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List active sessions")

    @Flag(name: .long, help: "Output as JSON")
    var json = false

    func run() throws {
        let store = SessionStore()
        let sessions = try store.listAll()

        if json {
            let data = try JSONEncoder.agentsHub.encode(sessions)
            print(String(data: data, encoding: .utf8) ?? "[]")
        } else {
            for s in sessions {
                let name = s.name ?? "unnamed"
                let app = s.app ?? "unknown"
                print("[\(s.status.rawValue)] \(name) (\(app))")
            }
        }
    }
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "One-line status summary")

    func run() throws {
        let store = SessionStore()
        let sessions = try store.listAll()
        let running = sessions.filter { $0.status == .running }.count
        let needsInput = sessions.filter { $0.status == .needsInput }.count
        let idle = sessions.filter { $0.status == .idle }.count
        print("\(running) running, \(needsInput) needs input, \(idle) idle")
    }
}

struct Clear: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Clear finished sessions from history")

    @Flag(name: .long, help: "Clear all history (done + error)")
    var all = false

    @Option(name: .long, help: "Clear sessions older than N hours")
    var olderThan: Int?

    func run() throws {
        let store = SessionStore()
        if let hours = olderThan {
            let count = try store.deleteOlderThan(Double(hours) * 3600)
            print("Cleared \(count) sessions older than \(hours)h")
        } else if all {
            let count = try store.deleteHistory()
            print("Cleared \(count) history sessions")
        } else {
            let count = try store.deleteUnavailable()
            print("Cleared \(count) unavailable sessions")
        }
    }
}

struct Delete: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Delete a specific session")

    @Argument(help: "Session ID to delete")
    var sessionId: String

    func run() throws {
        let store = SessionStore()
        try store.delete(id: sessionId)
        print("Deleted session \(sessionId)")
    }
}

AgentsHubCommand.main()
