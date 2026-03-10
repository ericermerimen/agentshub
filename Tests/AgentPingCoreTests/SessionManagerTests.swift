import XCTest
@testable import AgentPingCore

final class SessionManagerTests: XCTestCase {
    var manager: SessionManager!
    var store: SessionStore!
    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentping-mgr-\(UUID().uuidString)")
        store = SessionStore(directory: tempDir)
        manager = SessionManager(store: store)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testLoadSessions() throws {
        let s1 = Session(id: "s1", status: .running)
        let s2 = Session(id: "s2", status: .needsInput)
        try store.write(s1)
        try store.write(s2)

        manager.reload()
        XCTAssertEqual(manager.sessions.count, 2)
    }

    func testActiveSessions() throws {
        let s1 = Session(id: "s1", status: .running)
        let s2 = Session(id: "s2", status: .done)
        let s3 = Session(id: "s3", status: .needsInput)
        try store.write(s1)
        try store.write(s2)
        try store.write(s3)

        manager.reload()
        XCTAssertEqual(manager.activeSessions.count, 2)
    }

    func testNeedsInputCount() throws {
        let s1 = Session(id: "s1", status: .running)
        let s2 = Session(id: "s2", status: .needsInput)
        let s3 = Session(id: "s3", status: .needsInput)
        try store.write(s1)
        try store.write(s2)
        try store.write(s3)

        manager.reload()
        XCTAssertEqual(manager.needsInputCount, 2)
    }

    func testUnavailableCount() throws {
        let s1 = Session(id: "s1", status: .unavailable)
        let s2 = Session(id: "s2", status: .running)
        try store.write(s1)
        try store.write(s2)

        manager.reload()
        XCTAssertEqual(manager.unavailableCount, 1)
    }

    func testClearUnavailable() throws {
        let s1 = Session(id: "s1", status: .unavailable)
        let s2 = Session(id: "s2", status: .running)
        try store.write(s1)
        try store.write(s2)

        manager.reload()
        manager.clearUnavailable()
        XCTAssertEqual(manager.sessions.count, 1)
        XCTAssertEqual(manager.sessions.first?.id, "s2")
    }
}
