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
            // Always update to show the latest message
            session.taskDescription = Self.extractLastMessage(from: transcriptPath) ?? session.taskDescription
            // Read real context % from Claude Code's status line data
            session.contextPercent = Self.readContextPercent(transcriptPath: transcriptPath)
            // Extract provider and model from transcript
            if session.provider == nil || session.model == nil,
               let modelId = Self.readModelFromTranscript(transcriptPath) {
                let (provider, model) = Self.humanizeModelName(modelId)
                session.provider = provider
                session.model = model
            }
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

    /// Read the end of the transcript JSONL and find the last meaningful message.
    /// Prefers the last assistant text, falls back to the last user message.
    public static func extractLastMessage(from path: String) -> String? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { fh.closeFile() }

        // Read the last 100KB to find recent messages
        let fileSize = fh.seekToEndOfFile()
        let readSize: UInt64 = min(fileSize, 100_000)
        fh.seek(toFileOffset: fileSize - readSize)
        let data = fh.readDataToEndOfFile()
        guard let content = String(data: data, encoding: .utf8) else { return nil }

        var lastAssistant: String?
        var lastUser: String?

        let lines = content.components(separatedBy: .newlines).reversed()
        for line in lines {
            // Stop early once we have both
            if lastAssistant != nil && lastUser != nil { break }

            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            let type = obj["type"] as? String
            let role = obj["role"] as? String

            let isAssistant = type == "assistant" || role == "assistant"
            let isUser = type == "user" || role == "human" || role == "user"

            guard isAssistant || isUser else { continue }

            let contentVal = obj["content"] ?? (obj["message"] as? [String: Any])?["content"]
            let text = extractText(from: contentVal)
            guard let text, !text.isEmpty else { continue }

            if isAssistant && lastAssistant == nil {
                lastAssistant = text
            } else if isUser && lastUser == nil {
                lastUser = text
            }
        }

        let result = lastAssistant ?? lastUser
        return result.map { truncate($0, maxLength: 120) }
    }

    /// Extract plain text from a transcript content value (string or array of blocks).
    private static func extractText(from contentVal: Any?) -> String? {
        if let text = contentVal as? String {
            let cleaned = stripTags(text)
            return cleaned.isEmpty ? nil : cleaned
        }
        if let blocks = contentVal as? [[String: Any]] {
            let texts = blocks.compactMap { block -> String? in
                guard block["type"] as? String == "text",
                      let text = block["text"] as? String else { return nil }
                let cleaned = stripTags(text)
                return cleaned.isEmpty ? nil : cleaned
            }
            return texts.first
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
    public static func readContextPercent(transcriptPath: String) -> Double? {
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

    /// Parse a Claude model ID into (provider, displayName).
    /// e.g. "claude-opus-4-6" -> ("Claude", "Opus 4.6")
    /// e.g. "claude-haiku-4-5-20251001" -> ("Claude", "Haiku 4.5")
    public static func humanizeModelName(_ modelId: String) -> (provider: String, model: String) {
        guard modelId.hasPrefix("claude-") else {
            return ("Unknown", modelId)
        }
        // Strip "claude-" prefix
        let rest = String(modelId.dropFirst(7)) // drop "claude-"
        // Known families: opus, sonnet, haiku
        for family in ["opus", "sonnet", "haiku"] {
            guard rest.hasPrefix(family) else { continue }
            let afterFamily = String(rest.dropFirst(family.count))
            // afterFamily is like "-4-6" or "-4-5-20251001"
            let parts = afterFamily.split(separator: "-").compactMap { Int($0) }
            // Take first two numeric parts as major.minor version
            if parts.count >= 2 {
                return ("Claude", "\(family.capitalized) \(parts[0]).\(parts[1])")
            } else if parts.count == 1 {
                return ("Claude", "\(family.capitalized) \(parts[0])")
            }
            return ("Claude", family.capitalized)
        }
        return ("Claude", rest)
    }

    /// Extract the model ID from the last assistant message in a Claude transcript.
    public static func readModelFromTranscript(_ path: String) -> String? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { fh.closeFile() }

        let fileSize = fh.seekToEndOfFile()
        let readSize: UInt64 = min(fileSize, 100_000)
        fh.seek(toFileOffset: fileSize - readSize)
        let data = fh.readDataToEndOfFile()
        guard let content = String(data: data, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: .newlines).reversed()
        for line in lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  obj["type"] as? String == "assistant" else { continue }
            // Model can be at top level or nested in message
            if let model = obj["model"] as? String { return model }
            if let msg = obj["message"] as? [String: Any],
               let model = msg["model"] as? String { return model }
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
