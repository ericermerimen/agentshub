import Foundation

public final class ReportHandler {
    private let store: SessionStore

    public init(store: SessionStore? = nil) {
        self.store = store ?? SessionStore()
    }

    public func handle(sessionId: String, event: String, name: String?, file: String?, cwd: String? = nil, transcriptPath: String? = nil, app: String? = nil) throws {
        var session = try store.read(id: sessionId) ?? Session(id: sessionId)

        // Update name: explicit name > derive from cwd > keep existing
        if let name, session.name == nil {
            session.name = name
        } else if session.name == nil, let cwd {
            session.name = URL(fileURLWithPath: cwd).lastPathComponent
        }

        if let file { session.file = file }
        if let cwd { session.cwd = cwd }
        if let app { session.app = app }

        // Store transcript path and extract task description
        if let transcriptPath {
            session.transcriptPath = transcriptPath
            if session.taskDescription == nil {
                session.taskDescription = Self.extractTaskDescription(from: transcriptPath)
            }
            // Read real context % from Claude Code's status line data
            session.contextPercent = Self.readContextPercent(transcriptPath: transcriptPath)
        }

        // Map event to status
        // "stopped" = Claude finished its turn, waiting for user's next message = idle
        // Only sync/process-exit marks a session as truly "done"
        switch event {
        case "tool-use":    session.status = .running
        case "needs-input": session.status = .needsInput
        case "stopped":     session.status = .idle
        case "error":       session.status = .error
        default:            session.status = .running
        }

        session.lastEventAt = Date()
        try store.write(session)
    }

    /// Read the transcript JSONL and find the first user message to use as task description.
    private static func extractTaskDescription(from path: String) -> String? {
        // Only read the first 50KB to avoid loading huge transcripts
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { fh.closeFile() }
        let chunk = fh.readData(ofLength: 50_000)
        guard let content = String(data: chunk, encoding: .utf8) else { return nil }

        for line in content.components(separatedBy: .newlines) {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            // Claude Code transcript uses "type": "user" for human messages
            let type = obj["type"] as? String
            let role = obj["role"] as? String
            guard type == "user" || role == "human" || role == "user" else { continue }

            // Content can be at top level or inside "message"
            let contentVal = obj["content"] ?? (obj["message"] as? [String: Any])?["content"]

            if let text = contentVal as? String {
                let cleaned = stripTags(text)
                if !cleaned.isEmpty { return truncate(cleaned, maxLength: 80) }
            }
            if let blocks = contentVal as? [[String: Any]] {
                for block in blocks {
                    if block["type"] as? String == "text",
                       let text = block["text"] as? String {
                        let cleaned = stripTags(text)
                        if !cleaned.isEmpty { return truncate(cleaned, maxLength: 80) }
                    }
                }
            }
        }
        return nil
    }

    /// Strip XML/HTML-like tags and command markup from text.
    private static func stripTags(_ text: String) -> String {
        // Remove <command-message>, <command-name>, <command-args> etc.
        var result = text
        // Extract command-args content if present (that's the actual user task)
        if let argsRange = result.range(of: "<command-args>"),
           let argsEnd = result.range(of: "</command-args>") {
            result = String(result[argsRange.upperBound..<argsEnd.lowerBound])
        }
        // Strip remaining tags
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Read real context usage from the last assistant message's token counts.
    /// Claude's context window is 200K tokens. The usage.cache_read_input_tokens + input_tokens
    /// gives the actual tokens used.
    private static func readContextPercent(transcriptPath: String) -> Double? {
        // Read last 100KB of transcript to find the most recent assistant message with usage
        guard let fh = FileHandle(forReadingAtPath: transcriptPath) else { return nil }
        defer { fh.closeFile() }

        let fileSize = fh.seekToEndOfFile()
        let readSize: UInt64 = min(fileSize, 100_000)
        fh.seek(toFileOffset: fileSize - readSize)
        let data = fh.readDataToEndOfFile()
        guard let content = String(data: data, encoding: .utf8) else { return nil }

        // Search lines in reverse for the last assistant message with usage
        let lines = content.components(separatedBy: .newlines).reversed()
        for line in lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let msg = obj["message"] as? [String: Any] ?? obj as [String: Any]?,
                  let usage = (msg["usage"] ?? obj["usage"]) as? [String: Any] else { continue }

            let inputTokens = (usage["input_tokens"] as? Int) ?? 0
            let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0
            let cacheCreate = (usage["cache_creation_input_tokens"] as? Int) ?? 0
            let totalInput = inputTokens + cacheRead + cacheCreate

            if totalInput > 0 {
                // Claude Opus context window: 200K tokens
                return min(Double(totalInput) / 200_000.0, 1.0)
            }
        }
        return nil
    }

    private static func truncate(_ text: String, maxLength: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Take first line only
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        if firstLine.count <= maxLength { return firstLine }
        return String(firstLine.prefix(maxLength - 1)) + "..."
    }
}
