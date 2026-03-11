import XCTest
@testable import AgentPingCore

final class APIServerTests: XCTestCase {
    var server: APIServer!
    var tempDir: URL!
    var store: SessionStore!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentping-server-test-\(UUID().uuidString)")
        store = SessionStore(directory: tempDir)
        // Use random port to avoid conflicts in parallel test runs
        server = APIServer(store: store, port: 0)
        try await server.start()
    }

    override func tearDown() async throws {
        server.stop()
        try? FileManager.default.removeItem(at: tempDir)
    }

    private var baseURL: URL {
        URL(string: "http://127.0.0.1:\(server.actualPort)")!
    }

    private func request(_ method: String, _ path: String, body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.httpBody = body
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        return (data, response as! HTTPURLResponse)
    }

    func testHealthEndpoint() async throws {
        let (data, response) = try await request("GET", "v1/health")
        XCTAssertEqual(response.statusCode, 200)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["status"] as? String, "ok")
    }

    func testReportAndGetSession() async throws {
        let body = #"{"session_id":"integ-1","event":"tool-use","cwd":"/tmp","provider":"Claude","model":"Opus 4.6"}"#
        let (_, postRes) = try await request("POST", "v1/report", body: Data(body.utf8))
        XCTAssertEqual(postRes.statusCode, 200)

        let (getData, getRes) = try await request("GET", "v1/sessions/integ-1")
        XCTAssertEqual(getRes.statusCode, 200)
        let session = try JSONDecoder.agentPing.decode(Session.self, from: getData)
        XCTAssertEqual(session.provider, "Claude")
        XCTAssertEqual(session.model, "Opus 4.6")
    }

    func testListAndDeleteSession() async throws {
        let body = #"{"session_id":"list-1","event":"tool-use"}"#
        _ = try await request("POST", "v1/report", body: Data(body.utf8))

        let (listData, listRes) = try await request("GET", "v1/sessions")
        XCTAssertEqual(listRes.statusCode, 200)
        let sessions = try JSONDecoder.agentPing.decode([Session].self, from: listData)
        XCTAssertEqual(sessions.count, 1)

        let (_, delRes) = try await request("DELETE", "v1/sessions/list-1")
        XCTAssertEqual(delRes.statusCode, 204)

        let (listData2, _) = try await request("GET", "v1/sessions")
        let sessions2 = try JSONDecoder.agentPing.decode([Session].self, from: listData2)
        XCTAssertEqual(sessions2.count, 0)
    }

    func testConcurrentReports() async throws {
        // Send 10 concurrent reports
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let body = #"{"session_id":"concurrent-\#(i)","event":"tool-use"}"#
                    let (_, res) = try await self.request("POST", "v1/report", body: Data(body.utf8))
                    XCTAssertEqual(res.statusCode, 200)
                }
            }
            try await group.waitForAll()
        }

        let sessions = try store.listAll()
        XCTAssertEqual(sessions.count, 10)
    }
}
