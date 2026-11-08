import Foundation

@main struct LocalSubscriptionTests {
    static func main() async throws {
        let input = try LocalSubscription.claudeInput(messages: [ChatMessage(role: "user", text: "hello", jpeg: Data([1,2,3]))])
        let object = try JSONSerialization.jsonObject(with: input) as! [String: Any]
        let content = (object["message"] as! [String: Any])["content"] as! [[String: Any]]
        precondition(content.last?["type"] as? String == "image")
        let response = try LocalSubscription.parseClaude(Data(#"{"type":"result","subtype":"success","is_error":false,"result":"ok"}"#.utf8))
        precondition(response == "ok")
        let good = """
        {"event":"step_update","step_update":{"state":"DONE","step_type":"tool","tool_info":{"parameters":{"path":"slide_0.jpg"}}}}
        {"event":"result","result":{"status":"SUCCESS","response":"看到了截图"}}
        """
        let imageResponse = try LocalSubscription.parseGemini(Data(good.utf8), requiredImage: "slide_0.jpg")
        precondition(imageResponse == "看到了截图")
        do {
            _ = try LocalSubscription.parseGemini(Data(#"{"event":"result","result":{"status":"SUCCESS","response":"猜测的答案"}}"#.utf8), requiredImage: "slide_0.jpg")
            fatalError("Must not accept image answer without reading screenshot")
        } catch {}
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("keban-local-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = try await CLIJob.run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", "fixture-success"], input: Data(), folder: folder, timeout: 5)
        precondition(output.status == 0 && String(decoding: output.data, as: UTF8.self) == "fixture-success")
        let waiting = Task { try await CLIJob.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], input: Data(), folder: folder, timeout: 15) }
        try await Task.sleep(for: .milliseconds(100))
        waiting.cancel()
        do { _ = try await waiting.value; fatalError("Cancellation did not propagate") }
        catch is CancellationError {}
        print("PASS: image payload, native results, missing-image refusal, process execution and cancellation")
    }
}
