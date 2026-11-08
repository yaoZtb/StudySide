import AppKit

enum LocalSubscription: String, CaseIterable {
    case claude, gemini
    var name: String { self == .claude ? "Claude" : "Gemini" }
    var command: String { self == .claude ? "claude" : "agy" }
    var documentation: URL {
        URL(string: self == .claude ? "https://code.claude.com/docs/en/setup" : "https://antigravity.google/docs/cli/install")!
    }
    var executable: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Library/Application Support/课伴/Tools/" + command),
            home.appendingPathComponent(".local/bin/" + command),
            URL(fileURLWithPath: "/opt/homebrew/bin/" + command),
            URL(fileURLWithPath: "/usr/local/bin/" + command)
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    @MainActor func openLogin() throws {
        guard let executable else { throw AppError.message("The official \(name) client is not installed. Open the setup guide first.") }
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/课伴")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let script = folder.appendingPathComponent("Login-" + command + ".command")
        let quoted = "'" + executable.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let arguments = self == .claude ? " auth login" : ""
        let text = "#!/bin/zsh\nexec " + quoted + arguments + "\n"
        try text.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        guard NSWorkspace.shared.open(script) else { throw AppError.message("Could not open the official sign-in flow.") }
    }

    static func claudeInput(messages: [ChatMessage]) throws -> Data {
        let recent = Array(messages.suffix(16))
        let images = Set(recent.filter { $0.role == "user" && $0.jpeg != nil }.suffix(3).map(\.id))
        var blocks: [[String: Any]] = [["type": "text", "text": ChatAPI.instruction + "\nThe following is the conversation so far. Answer the last user message."]]
        for message in recent {
            blocks.append(["type": "text", "text": "\n[\(message.role)]\n\(message.text)"])
            if images.contains(message.id), let jpeg = message.jpeg {
                blocks.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]])
            }
        }
        return try JSONSerialization.data(withJSONObject: ["type": "user", "message": ["role": "user", "content": blocks]]) + Data([10])
    }

    static func parseClaude(_ data: Data) throws -> String {
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n").reversed() {
            guard let event = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any], event["type"] as? String == "result" else { continue }
            guard event["is_error"] as? Bool == false, event["subtype"] as? String == "success",
                  let result = event["result"] as? String, !result.isEmpty else {
                throw AppError.message("Claude did not finish its answer. Check your plan usage and sign-in status in the official client.")
            }
            return result
        }
        throw AppError.message("No complete answer was received from Claude. Update the official Claude Code client and try again.")
    }

    static func parseGemini(_ data: Data, requiredImage: String?) throws -> String {
        var sawCurrentImage = requiredImage == nil
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let event = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            if event["event"] as? String == "step_update",
               let step = event["step_update"] as? [String: Any], step["step_type"] as? String == "tool",
               step["state"] as? String == "DONE", let info = step["tool_info"] as? [String: Any], info["error"] == nil,
               let image = requiredImage, String(describing: info["parameters"]).contains(image) {
                sawCurrentImage = true
            }
            if event["event"] as? String == "result", let result = event["result"] as? [String: Any] {
                guard result["status"] as? String == "SUCCESS", let answer = result["response"] as? String, !answer.isEmpty else {
                    throw AppError.message("Gemini did not finish its answer. Check sign-in and plan usage in the official Antigravity CLI.")
                }
                guard sawCurrentImage else {
                    throw AppError.message("Gemini did not confirm that it read the current screenshot. Check the official client's image permissions, or pause capture to ask a text-only question.")
                }
                return answer
            }
        }
        throw AppError.message("No complete answer was received from Gemini. Check the official Antigravity CLI.")
    }

    func reply(messages: [ChatMessage], geminiModel: String) async throws -> String {
        guard let executable else { throw AppError.message("The official \(name) client was not found. Install it and sign in from Model Settings.") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("keban-\(command)-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let input: Data
        let arguments: [String]
        var latestImage: String?
        if self == .claude {
            let authentication = try await CLIJob.run(executable: executable, arguments: ["auth", "status", "--json"], input: Data(), folder: folder, timeout: 15)
            guard let state = (try? JSONSerialization.jsonObject(with: authentication.data)) as? [String: Any],
                  state["loggedIn"] as? Bool == true, state["authMethod"] as? String == "claude.ai",
                  state["apiProvider"] as? String == "firstParty",
                  ["pro", "max", "ultra", "team", "enterprise"].contains((state["subscriptionType"] as? String ?? "").lowercased())
            else { throw AppError.message("Sign in to the official Claude Code client with a subscribed Claude account. An active subscription sign-in could not be confirmed.") }
            input = try Self.claudeInput(messages: messages)
            arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--model", "sonnet",
                         "--tools", "", "--no-session-persistence", "--setting-sources", "", "--strict-mcp-config",
                         "--disable-slash-commands", "--settings", "{\"disableAllHooks\":true}"]
        } else {
            let recent = Array(messages.suffix(16))
            let imageIDs = Set(recent.filter { $0.role == "user" && $0.jpeg != nil }.suffix(3).map(\.id))
            var prompt = ChatAPI.instruction + "\nAnswer study questions only. Do not modify files, execute commands, browse the web, or use other tools. For messages with screenshots, read the associated JPG image first; do not guess from its filename. Say clearly if you cannot read it.\n"
            for (index, message) in recent.enumerated() {
                prompt += "\n[\(message.role)]\n" + message.text
                if imageIDs.contains(message.id), let jpeg = message.jpeg {
                    let filename = "slide_\(index).jpg"
                    try jpeg.write(to: folder.appendingPathComponent(filename), options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: folder.appendingPathComponent(filename).path)
                    prompt += "\nScreenshot file for this message: " + filename
                    latestImage = filename
                }
            }
            let settings: [String: Any] = [
                "modelProvider": "", "useG1Credits": false, "toolPermission": "strict", "allowNonWorkspaceAccess": false,
                "permissions": ["deny": ["write_file(*)", "command(*)", "mcp(*)", "read_url(*)", "execute_url(*)"]]
            ]
            let config = String(decoding: try JSONSerialization.data(withJSONObject: settings), as: UTF8.self)
            input = try JSONSerialization.data(withJSONObject: ["event": "user", "message": ["content": prompt]]) + Data([10])
            arguments = ["--input-format", "stream-json", "--output-format", "stream-json", "--disable-slash-commands",
                         "--model", geminiModel, "--settings", config, "--print-timeout", "180s"]
        }
        let output = try await CLIJob.run(executable: executable, arguments: arguments, input: input, folder: folder, timeout: 210)
        guard output.status == 0 else {
            throw AppError.message("The official \(name) client did not complete the request. Open its sign-in flow in Model Settings and check your account, plan usage, and model access. StudySide will not switch to API billing.")
        }
        return try self == .claude ? Self.parseClaude(output.data) : Self.parseGemini(output.data, requiredImage: latestImage)
    }
}

final class CLIJob: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var stopped = false
    private var timedOut = false

    private func stop(timeout: Bool = false) {
        lock.lock()
        stopped = true
        timedOut = timeout
        if process.isRunning { process.terminate() }
        lock.unlock()
    }

    static func run(executable: URL, arguments: [String], input: Data, folder: URL, timeout: Double) async throws -> (data: Data, status: Int32) {
        let job = CLIJob()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let outputURL = folder.appendingPathComponent(UUID().uuidString + ".out")
                        let inputURL = folder.appendingPathComponent(UUID().uuidString + ".in")
                        try input.write(to: inputURL, options: .atomic)
                        FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: inputURL.path)
                        let source = try FileHandle(forReadingFrom: inputURL)
                        let destination = try FileHandle(forWritingTo: outputURL)
                        defer { try? source.close(); try? destination.close() }
                        job.process.executableURL = executable
                        job.process.arguments = arguments
                        job.process.currentDirectoryURL = folder
                        var env = ProcessInfo.processInfo.environment
                        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL", "CLAUDE_CODE_OAUTH_TOKEN",
                                    "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY", "CLAUDECODE",
                                    "GEMINI_API_KEY", "GOOGLE_API_KEY", "AGY_ADC_AUTH"] { env.removeValue(forKey: key) }
                        env["PATH"] = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                        job.process.environment = env
                        job.process.standardInput = source
                        job.process.standardOutput = destination
                        job.process.standardError = FileHandle.nullDevice
                        job.lock.lock()
                        if job.stopped { job.lock.unlock(); throw CancellationError() }
                        do { try job.process.run(); job.lock.unlock() }
                        catch { job.lock.unlock(); throw error }
                        let timer = DispatchWorkItem { job.stop(timeout: true) }
                        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                        defer { timer.cancel() }
                        job.process.waitUntilExit()
                        job.lock.lock()
                        let stopped = job.stopped, timedOut = job.timedOut
                        job.lock.unlock()
                        if stopped { throw timedOut ? AppError.message("The official model client timed out. Please try again.") : CancellationError() }
                        let reader = try FileHandle(forReadingFrom: outputURL)
                        defer { try? reader.close() }
                        let data = try reader.read(upToCount: 8 * 1024 * 1024 + 1) ?? Data()
                        guard data.count <= 8 * 1024 * 1024 else { throw AppError.message("The model output is too large. Try a shorter question.") }
                        continuation.resume(returning: (data, job.process.terminationStatus))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { job.stop() }
    }
}
