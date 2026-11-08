import Foundation

final class MockProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var code = 200
    nonisolated(unsafe) static var body = ""
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct CoreTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fatalError("FAIL: \(name)") }
        print("PASS: \(name)")
    }
    static func main() async throws {
        let settings = AISettings(baseURL: "https://example.com/v1/", model: "vision-model")
        let endpoint = try settings.endpoint()
        expect(endpoint.absoluteString == "https://example.com/v1/chat/completions", "base URL preserves API prefix")
        let full = try AISettings(baseURL: "https://example.com/v1/chat/completions", model: "vision").endpoint()
        expect(full == endpoint, "full endpoint is not duplicated")
        for invalid in ["http://example.com/v1", "https://user:secret@example.com/v1", "https://example.com/v1?key=secret", "", "file:///tmp/foo"] {
            do { _ = try AISettings(baseURL: invalid, model: "vision").endpoint(); fatalError("Accepted invalid URL") }
            catch { print("PASS: reject invalid endpoint") }
        }
        _ = try AISettings(baseURL: "http://127.0.0.1:8080/v1", model: "vision").endpoint()
        print("PASS: local HTTP API allowed")
        var messages: [ChatMessage] = []
        for index in 0..<10 {
            messages.append(ChatMessage(role: "user", text: "slide \(index)", jpeg: Data([1, 2, 3])))
            messages.append(ChatMessage(role: "assistant", text: "answer \(index)"))
        }
        let request = try ChatAPI.request(settings: settings, key: " test-key ", messages: messages)
        let payload = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let sent = payload["messages"] as! [[String: Any]]
        expect(sent.count == 17, "history bounded to 16 messages plus system")
        expect(sent.filter { $0["content"] is [[String: Any]] }.count == 3, "only newest three images sent")
        expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key", "key in authorization header")
        expect(!String(data: request.httpBody!, encoding: .utf8)!.contains("test-key"), "key excluded from body")
        expect(sent.last?["content"] as? String == "answer 9", "history order retained")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockProtocol.self]
        let session = URLSession(configuration: config)
        MockProtocol.body = "{\"choices\":[{\"message\":{\"content\":\"测试回答\"}}]}"
        let reply = try await ChatAPI.reply(settings: settings, key: "", messages: messages, session: session)
        expect(reply == "测试回答", "parse successful response")
        MockProtocol.body = "{\"choices\":[{\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"第一步\"}]}}]}"
        let parts = try await ChatAPI.reply(settings: settings, key: "", messages: [], session: session)
        expect(parts == "第一步", "parse content-parts response")
        for code in [401, 429, 500] {
            MockProtocol.code = code
            do { _ = try await ChatAPI.reply(settings: settings, key: "", messages: [], session: session); fatalError("Accepted HTTP error") }
            catch { expect(error.localizedDescription.contains(String(code)), "HTTP \(code) is explained") }
        }
        MockProtocol.code = 200
        for body in ["{}", "not json", "{\"choices\":[{\"message\":{\"content\":\"\"}}]}"] {
            MockProtocol.body = body
            do { _ = try await ChatAPI.reply(settings: settings, key: "", messages: [], session: session); fatalError("Accepted malformed response") }
            catch { print("PASS: reject missing or malformed model output") }
        }
        print("All core checks passed; no external API contacted.")
    }
}
