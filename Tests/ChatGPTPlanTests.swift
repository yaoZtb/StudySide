import Foundation

@main @MainActor struct PlanTests {
    static func main() async throws {
        let request = try ChatGPTPlan.request(access: "mock-token", messages: [
            ChatMessage(role: "user", text: "解释这一页", jpeg: Data([1, 2, 3])),
            ChatMessage(role: "assistant", text: "此前的回答")
        ])
        precondition(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer mock-token")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        precondition(body["model"] as? String == "gpt-6.1-sol")
        precondition(body["store"] as? Bool == false && body["stream"] as? Bool == true)
        let input = body["input"] as! [[String: Any]]
        let image = (input[0]["content"] as! [[String: Any]])[1]
        precondition(image["image_url"] as? String == "data:image/jpeg;base64,AQID")
        precondition(input[1]["role"] as? String == "assistant")

        var reply = ChatGPTPlan.ReplyStream()
        let updated = try reply.consume(#"{"type":"response.output_text.delta","delta":"你好"}"#)
        precondition(updated && reply.text == "你好")
        do { _ = try reply.finalText(); fatalError("An interrupted stream must not succeed") } catch {}
        _ = try reply.consume(#"{"type":"response.completed"}"#)
        let answer = try reply.finalText()
        precondition(answer == "你好")
        var limited = ChatGPTPlan.ReplyStream()
        do {
            _ = try limited.consume(#"{"type":"response.failed","response":{"error":{"code":"subscription_sharing_usage_limit_exceeded"}}}"#)
            fatalError("A quota failure must not succeed")
        } catch { precondition(error.localizedDescription.contains("allowance")) }

        let listener = try Loopback()
        let callback = try await listener.wait(open: { port in
            Task {
                let origin = "http://127.0.0.1:\(port)"
                let (_, wrong) = try await URLSession.shared.data(from: URL(string: origin + "/auth/callback?code=bad&state=wrong")!)
                precondition((wrong as? HTTPURLResponse)?.statusCode == 400)
                let (_, correct) = try await URLSession.shared.data(from: URL(string: origin + "/auth/callback?code=mock&state=expected&client_id=oaiapp_test")!)
                precondition((correct as? HTTPURLResponse)?.statusCode == 200)
            }
            return true
        }, state: "expected")
        precondition(callback.queryItems?.contains(URLQueryItem(name: "code", value: "mock")) == true)
        print("PASS: subscription request with image, streaming completion and quota errors, and real loopback callback with state validation")
    }
}
