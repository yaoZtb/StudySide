import AppKit
import CryptoKit
import Network
import Security

private let issuer = "https://auth.openai.com"
private let resource = "https://api.openai.com/v1"
private let planScope = "chatgpt.tokens.use.direct"

private extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    init?(base64URL value: String) {
        let s = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        self.init(base64Encoded: s + String(repeating: "=", count: (4 - s.count % 4) % 4))
    }
}

@MainActor final class Loopback {
    private let listener: NWListener
    private var result: CheckedContinuation<URLComponents, Error>?
    private var timer: Task<Void, Never>?
    private var opened = false

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func wait(open: @escaping (UInt16) -> Bool, state: String) async throws -> URLComponents {
        try await withCheckedThrowingContinuation { continuation in
            result = continuation
            listener.stateUpdateHandler = { [weak self] status in
                Task { @MainActor in
                    guard let self, self.result != nil else { return }
                    switch status {
                    case .ready:
                        guard !self.opened else { return }
                        self.opened = true
                        if let port = self.listener.port?.rawValue, open(port) { return }
                        self.finish(.failure(AppError.message("Could not open the ChatGPT sign-in page.")))
                    case .failed: self.finish(.failure(AppError.message("Could not start the local sign-in callback listener.")))
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.read(connection, state: state) }
            }
            listener.start(queue: .main)
            timer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(180))
                if !Task.isCancelled { self?.finish(.failure(AppError.message("Sign-in timed out. Please try again."))) }
            }
        }
    }

    private func read(_ connection: NWConnection, state: String) {
        connection.start(queue: .main)
        receive(connection, state: state, accumulated: Data())
    }

    private func receive(_ connection: NWConnection, state: String, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, ended, error in
            Task { @MainActor in
                guard let self, self.result != nil, error == nil, let data else { connection.cancel(); return }
                let request = accumulated + data
                guard request.count <= 32768 else { connection.cancel(); return }
                guard let eol = request.range(of: Data([13, 10])) else {
                    if ended { connection.cancel() } else { self.receive(connection, state: state, accumulated: request) }
                    return
                }
                let words = String(decoding: request[..<eol.lowerBound], as: UTF8.self).split(separator: " ")
                let callback = words.count == 3 && words[0] == "GET" && words[1].hasPrefix("/auth/callback?")
                    ? URLComponents(string: "http://127.0.0.1" + words[1]) : nil
                let states = callback?.queryItems?.filter { $0.name == "state" } ?? []
                let valid = states.count == 1 && states.first?.value == state
                let body = valid ? "Return to StudySide to finish ChatGPT sign-in." : "Invalid or unrelated callback."
                let status = valid ? "200 OK" : "400 Bad Request"
                let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                if let callback, valid { self.finish(.success(callback)) }
            }
        }
    }

    private func finish(_ outcome: Result<URLComponents, Error>) {
        guard let continuation = result else { return }
        result = nil
        timer?.cancel()
        listener.cancel()
        continuation.resume(with: outcome)
    }
}

struct PlanProfile: Codable, Identifiable {
    var id: String { client }
    var client: String
    var subject: String
    var email: String
    var idToken: String?
    var access: String?
    var refresh: String?
    var expires: Date
}

struct PlanStore: Codable {
    var profiles: [PlanProfile] = []
    var active: String?
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "local.keban.study-assistant.chatgpt",
        kSecAttrAccount as String: "plan-profiles"
    ]
    static func load() -> Self {
        var query = query
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return .init() }
        return (try? JSONDecoder().decode(Self.self, from: data)) ?? .init()
    }
    func save() throws {
        let values = [kSecValueData as String: try JSONEncoder().encode(self)]
        var status = SecItemUpdate(Self.query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(Self.query.merging(values) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AppError.message("Could not save the ChatGPT connection to Keychain.") }
    }
}

enum ChatGPTPlan {
    static let model = "gpt-6.1-sol"
    private static let tokenURL = URL(string: issuer + "/api/accounts/oauth/token")!
    private static let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private struct Tokens: Decodable {
        var access_token: String
        var refresh_token: String?
        var id_token: String?
        var expires_in: Double
        var scope: String?
    }

    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AppError.message("Could not start a secure sign-in.")
        }
        return Data(bytes).base64URL
    }

    @MainActor static func authorize(previous: PlanProfile?) async throws -> PlanProfile {
        let state = try random(), nonce = try random(), verifier = try random()
        let hostKey = "chatGPTPlanHostID"
        let host = UserDefaults.standard.string(forKey: hostKey) ?? "urn:uuid:" + UUID().uuidString.lowercased()
        UserDefaults.standard.set(host, forKey: hostKey)
        let listener = try Loopback()
        var redirect = ""
        let callback = try await listener.wait(open: { port in
            redirect = "http://127.0.0.1:\(port)/auth/callback"
            var url = URLComponents(string: issuer + "/api/accounts/authorize")!
            var query = [
                "client_id": previous?.client ?? "dynamic_agent_client",
                "ext_agent_host_id": host, "response_type": "code", "redirect_uri": redirect,
                "scope": "openid profile email offline_access resource.invoke " + planScope,
                "resource": resource, "state": state, "nonce": nonce, "code_challenge_method": "S256",
                "code_challenge": Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
            ]
            if let previous { query["id_token_hint"] = previous.idToken }
            else { query["agent_name_hint"] = "StudySide" }
            url.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            return url.url.map { NSWorkspace.shared.open($0) } ?? false
        }, state: state)
        func value(_ key: String) -> String? {
            let values = callback.queryItems?.filter { $0.name == key } ?? []
            return values.count == 1 ? values.first?.value : nil
        }
        if value("error") != nil { throw AppError.message("ChatGPT plan access was not granted. You can reconnect in Settings.") }
        guard let code = value("code"), !code.isEmpty,
              let client = value("client_id") ?? previous?.client, client.hasPrefix("oaiapp_"),
              previous == nil || client == previous?.client
        else { throw AppError.message("The ChatGPT sign-in callback was incomplete or the account did not match.") }
        let tokens = try await exchange([
            "grant_type": "authorization_code", "client_id": client, "code": code,
            "code_verifier": verifier, "redirect_uri": redirect, "resource": resource
        ])
        guard tokens.scope?.split(separator: " ").contains(Substring(planScope)) == true, let idToken = tokens.id_token else {
            throw AppError.message("ChatGPT did not grant permission to use your plan.")
        }
        let identity = try await verify(idToken, client: client, nonce: nonce)
        guard previous == nil || previous?.subject == identity.subject else { throw AppError.message("The authorized ChatGPT account does not match the selected account.") }
        return PlanProfile(client: client, subject: identity.subject, email: identity.email,
                           idToken: idToken, access: tokens.access_token, refresh: tokens.refresh_token,
                           expires: Date().addingTimeInterval(tokens.expires_in))
    }

    static func refresh(_ profile: PlanProfile) async throws -> PlanProfile {
        guard let refresh = profile.refresh else { throw AppError.message("Your ChatGPT sign-in has expired. Reconnect your account.") }
        let tokens = try await exchange(["grant_type": "refresh_token", "client_id": profile.client, "refresh_token": refresh, "resource": resource])
        if let scope = tokens.scope, !scope.split(separator: " ").contains(Substring(planScope)) {
            throw AppError.message("ChatGPT plan access has expired. Reconnect your account.")
        }
        var replacement = profile
        replacement.access = tokens.access_token
        replacement.refresh = tokens.refresh_token ?? refresh
        replacement.expires = Date().addingTimeInterval(tokens.expires_in)
        return replacement
    }

    static func revoke(_ profile: PlanProfile) async throws {
        guard let token = profile.refresh else { return }
        let metadata = try await discovery()
        guard let endpoint = trustedAuthURL(metadata["revocation_endpoint"]) else { throw AppError.message("A trusted sign-out endpoint was not found.") }
        let (_, response) = try await session.data(for: form(endpoint, ["token": token, "token_type_hint": "refresh_token", "client_id": profile.client]))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AppError.message("Remote sign-out was not confirmed. Disconnect StudySide in ChatGPT Settings.") }
    }

    private static func form(_ url: URL, _ values: [String: String]) -> URLRequest {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(values.map { key, value in key + "=" + (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") }.joined(separator: "&").utf8)
        return request
    }

    private static func exchange(_ fields: [String: String]) async throws -> Tokens {
        let (data, response) = try await session.data(for: form(tokenURL, fields))
        guard (response as? HTTPURLResponse)?.statusCode == 200, let tokens = try? JSONDecoder().decode(Tokens.self, from: data),
              !tokens.access_token.isEmpty, tokens.expires_in > 0 else {
            throw AppError.message("ChatGPT sign-in or renewal failed. Reconnect your account.")
        }
        return tokens
    }

    private static func trustedAuthURL(_ value: Any?) -> URL? {
        guard let value = value as? String, let url = URL(string: value), url.scheme == "https",
              url.host == "auth.openai.com", url.user == nil, url.password == nil, url.port == nil else { return nil }
        return url
    }

    private static func object(_ data: Data) -> [String: Any]? { (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }

    private static func discovery() async throws -> [String: Any] {
        let (data, response) = try await session.data(from: URL(string: issuer + "/.well-known/openid-configuration")!)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let metadata = object(data), metadata["issuer"] as? String == issuer else {
            throw AppError.message("Could not verify the ChatGPT sign-in service.")
        }
        return metadata
    }

    private static func verify(_ token: String, client: String, nonce: String) async throws -> (subject: String, email: String) {
        let failure = AppError.message("Could not verify your ChatGPT identity. Reconnect your account.")
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let h = Data(base64URL: parts[0]), let header = object(h),
              header["alg"] as? String == "RS256", let kid = header["kid"] as? String,
              let claimsData = Data(base64URL: parts[1]), let claims = object(claimsData),
              let sig = Data(base64URL: parts[2])
        else { throw failure }
        let metadata = try await discovery()
        guard let jwks = trustedAuthURL(metadata["jwks_uri"]) else { throw failure }
        let (keysData, response) = try await session.data(from: jwks)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let keys = object(keysData)?["keys"] as? [[String: Any]],
              let key = keys.first(where: { $0["kid"] as? String == kid && $0["kty"] as? String == "RSA" }),
              let n = (key["n"] as? String).flatMap(Data.init(base64URL:)), !n.isEmpty,
              let e = (key["e"] as? String).flatMap(Data.init(base64URL:)), !e.isEmpty
        else { throw failure }
        let der = tlv(0x30, integer(n) + integer(e))
        let attributes = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic] as CFDictionary
        guard let publicKey = SecKeyCreateWithData(der as CFData, attributes, nil),
              SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256, Data((parts[0] + "." + parts[1]).utf8) as CFData, sig as CFData, nil),
              claims["iss"] as? String == issuer, claims["nonce"] as? String == nonce,
              let expiry = claims["exp"] as? Double, expiry > Date().timeIntervalSince1970,
              let sub = claims["sub"] as? String, !sub.isEmpty
        else { throw failure }
        let audience = (claims["aud"] as? [String]) ?? (claims["aud"] as? String).map { [$0] } ?? []
        guard audience.contains(client), audience.count == 1 || claims["azp"] as? String == client else { throw failure }
        return (sub, claims["email"] as? String ?? "ChatGPT Account")
    }

    private static func integer(_ data: Data) -> Data {
        var bytes = Data(data.drop(while: { $0 == 0 }))
        if bytes.isEmpty || bytes[0] >= 128 { bytes.insert(0, at: 0) }
        return tlv(0x02, bytes)
    }
    private static func tlv(_ tag: UInt8, _ data: Data) -> Data {
        var size = data.count
        if size < 128 { return Data([tag, UInt8(size)]) + data }
        var length: [UInt8] = []
        while size > 0 { length.insert(UInt8(size & 255), at: 0); size >>= 8 }
        return Data([tag, 0x80 | UInt8(length.count)] + length) + data
    }

    static func request(access: String, messages: [ChatMessage]) throws -> URLRequest {
        let history = Array(messages.suffix(16))
        let images = Set(history.filter { $0.role == "user" && $0.jpeg != nil }.suffix(3).map(\.id))
        let input: [[String: Any]] = history.map { message in
            if message.role == "user", let jpeg = message.jpeg, images.contains(message.id) {
                let parts: [[String: Any]] = [
                    ["type": "input_text", "text": message.text],
                    ["type": "input_image", "image_url": "data:image/jpeg;base64," + jpeg.base64EncodedString(), "detail": "auto"]
                ]
                return ["role": "user", "content": parts]
            }
            return ["role": message.role, "content": message.text]
        }
        var request = URLRequest(url: URL(string: resource + "/responses")!, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("Bearer " + access, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "input": input, "instructions": ChatAPI.instruction, "store": false, "stream": true
        ])
        return request
    }

    struct ReplyStream {
        private(set) var text = ""
        private(set) var completed = false
        mutating func consume(_ payload: String) throws -> Bool {
            guard let event = ChatGPTPlan.object(Data(payload.utf8)), let type = event["type"] as? String else { return false }
            switch type {
            case "response.output_text.delta":
                if let delta = event["delta"] as? String { text += delta; return true }
            case "response.completed": completed = true
            case "response.failed", "error":
                let response = event["response"] as? [String: Any]
                let error = response?["error"] as? [String: Any] ?? event
                throw ChatGPTPlan.replyError(error["code"] as? String)
            case "response.incomplete": throw AppError.message("ChatGPT could not finish its answer. Please try again.")
            default: break
            }
            return false
        }
        func finalText() throws -> String {
            guard completed, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppError.message("ChatGPT did not return a complete answer. Please try again.")
            }
            return text
        }
    }

    private static func replyError(_ code: String?, http: Int? = nil) -> AppError {
        switch code {
        case "subscription_sharing_usage_limit_exceeded": return .message("Your ChatGPT plan allowance is currently exhausted. Check Settings > Usage in ChatGPT.")
        case "subscription_sharing_usage_unavailable": return .message("ChatGPT plan usage is unavailable for this account or workspace.")
        case "model_not_found": return .message("GPT-6.1 Sol is unavailable to this ChatGPT account.")
        default:
            if http == 401 { return .message("Your ChatGPT sign-in has expired. Reconnect your account.") }
            if http == 403 { return .message("ChatGPT rejected this plan request. Check account authorization and plan eligibility.") }
            if http == 429 { return .message("ChatGPT requests are currently limited. Check your allowance or try again later.") }
            return .message("The ChatGPT plan request failed" + (http.map { "（HTTP \($0)）" } ?? "") + ". Please try again later.")
        }
    }

    static func reply(access: String, messages: [ChatMessage], progress: @MainActor (String) -> Void) async throws -> String {
        let (bytes, raw) = try await session.bytes(for: request(access: access, messages: messages))
        guard let response = raw as? HTTPURLResponse else { throw replyError(nil) }
        guard response.statusCode == 200 else {
            var body = Data()
            for try await byte in bytes { body.append(byte); if body.count >= 16384 { break } }
            let error = object(body)?["error"] as? [String: Any]
            throw replyError(error?["code"] as? String, http: response.statusCode)
        }
        var stream = ReplyStream()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if line.hasPrefix("data:"), try stream.consume(String(line.dropFirst(5))) { await progress(stream.text) }
            if stream.completed { return try stream.finalText() }
        }
        return try stream.finalText()
    }
}
