import XCTest
@testable import AgentPingCore

final class ModelExtractionTests: XCTestCase {
    var tempDir: URL!
    var store: SessionStore!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentping-model-test-\(UUID().uuidString)")
        store = SessionStore(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testExtractsClaudeOpusModel() throws {
        let transcript = tempDir.appendingPathComponent("transcript.jsonl")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let line = #"{"type":"assistant","model":"claude-opus-4-6","message":{"content":"hello","usage":{"input_tokens":100}}}"#
        try line.write(to: transcript, atomically: true, encoding: .utf8)

        let handler = ReportHandler(store: store)
        try handler.handle(sessionId: "model-test", event: "tool-use", name: nil, file: nil, cwd: "/tmp", transcriptPath: transcript.path)

        let session = try store.read(id: "model-test")
        XCTAssertEqual(session?.provider, "Claude")
        XCTAssertEqual(session?.model, "Opus 4.6")
    }

    func testExtractsClaudeSonnetModel() throws {
        let transcript = tempDir.appendingPathComponent("transcript2.jsonl")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let line = #"{"type":"assistant","model":"claude-sonnet-4-6","message":{"content":"hello","usage":{"input_tokens":100}}}"#
        try line.write(to: transcript, atomically: true, encoding: .utf8)

        let handler = ReportHandler(store: store)
        try handler.handle(sessionId: "sonnet-test", event: "tool-use", name: nil, file: nil, cwd: "/tmp", transcriptPath: transcript.path)

        let session = try store.read(id: "sonnet-test")
        XCTAssertEqual(session?.provider, "Claude")
        XCTAssertEqual(session?.model, "Sonnet 4.6")
    }

    func testExtractsClaudeHaikuModel() throws {
        let transcript = tempDir.appendingPathComponent("transcript3.jsonl")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let line = #"{"type":"assistant","model":"claude-haiku-4-5-20251001","message":{"content":"hello","usage":{"input_tokens":100}}}"#
        try line.write(to: transcript, atomically: true, encoding: .utf8)

        let handler = ReportHandler(store: store)
        try handler.handle(sessionId: "haiku-test", event: "tool-use", name: nil, file: nil, cwd: "/tmp", transcriptPath: transcript.path)

        let session = try store.read(id: "haiku-test")
        XCTAssertEqual(session?.provider, "Claude")
        XCTAssertEqual(session?.model, "Haiku 4.5")
    }

    func testNoModelWithoutTranscript() throws {
        let handler = ReportHandler(store: store)
        try handler.handle(sessionId: "no-transcript", event: "tool-use", name: nil, file: nil, cwd: "/tmp", transcriptPath: nil)

        let session = try store.read(id: "no-transcript")
        XCTAssertNil(session?.provider)
        XCTAssertNil(session?.model)
    }

    func testHumanizeModelName() {
        XCTAssertEqual(ReportHandler.humanizeModelName("claude-opus-4-6"), ("Claude", "Opus 4.6"))
        XCTAssertEqual(ReportHandler.humanizeModelName("claude-sonnet-4-6"), ("Claude", "Sonnet 4.6"))
        XCTAssertEqual(ReportHandler.humanizeModelName("claude-haiku-4-5-20251001"), ("Claude", "Haiku 4.5"))
        XCTAssertEqual(ReportHandler.humanizeModelName("claude-sonnet-4-5-20241022"), ("Claude", "Sonnet 4.5"))
        XCTAssertEqual(ReportHandler.humanizeModelName("unknown-model"), ("Unknown", "unknown-model"))
    }
}
