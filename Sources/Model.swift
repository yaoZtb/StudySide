import SwiftUI
import AppKit
import ScreenCaptureKit
import Security

struct CourseWindow: Identifiable {
    let source: SCWindow
    var id: UInt32 { source.windowID }
    var app: String { source.owningApplication?.applicationName ?? "App" }
    var title: String { source.title?.isEmpty == false ? source.title! : "Untitled window" }
    var label: String { "\(app) · \(title)" }
}

enum KeyStore {
    static let service = "local.keban.study-assistant"
    static func load() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "api-key",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ key: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "api-key"]
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AppError.message("Could not remove the API key from Keychain.") }
            return
        }
        let data = Data(key.utf8)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw AppError.message("Could not update the API key in Keychain (\(update)).") }
        var insert = query
        insert[kSecValueData as String] = data
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw AppError.message("Could not save the API key to Keychain.") }
    }
}

@MainActor final class StudyModel: ObservableObject {
    @Published var themeID = UserDefaults.standard.string(forKey: "appearanceTheme") ?? StudyTheme.graphite.rawValue {
        didSet { UserDefaults.standard.set(themeID, forKey: "appearanceTheme") }
    }
    var theme: StudyTheme { StudyTheme(rawValue: themeID) ?? .graphite }

    @Published var localSubscriptionProvider = UserDefaults.standard.string(forKey: "localSubscriptionProvider") ?? "" {
        didSet { UserDefaults.standard.set(localSubscriptionProvider, forKey: "localSubscriptionProvider") }
    }
    @Published var geminiSubscriptionModel = UserDefaults.standard.string(forKey: "geminiSubscriptionModel") ?? "gemini-3.8-flash-medium" {
        didSet { UserDefaults.standard.set(geminiSubscriptionModel, forKey: "geminiSubscriptionModel") }
    }
    var backendSelection: String {
        get { LocalSubscription(rawValue: localSubscriptionProvider)?.rawValue ?? (useChatGPTPlan ? "chatgpt" : "api") }
        set {
            if LocalSubscription(rawValue: newValue) != nil { localSubscriptionProvider = newValue }
            else { localSubscriptionProvider = ""; useChatGPTPlan = newValue == "chatgpt" }
        }
    }
    var localSubscription: LocalSubscription? { LocalSubscription(rawValue: localSubscriptionProvider) }
    func openLocalLogin() {
        guard let provider = localSubscription else { return }
        do { try provider.openLogin(); error = nil }
        catch { self.error = error.localizedDescription }
    }

    @Published var useChatGPTPlan = UserDefaults.standard.object(forKey: "useChatGPTPlan") as? Bool ?? true {
        didSet { UserDefaults.standard.set(useChatGPTPlan, forKey: "useChatGPTPlan") }
    }
    #if PREVIEW
    @Published private(set) var planStore = PlanStore()
    #else
    @Published private(set) var planStore = PlanStore.load()
    #endif
    @Published private(set) var managingPlan = false
    @Published private(set) var streamingReply = ""
    @Published var planNotice: String?
    var activePlan: PlanProfile? { planStore.profiles.first { $0.id == planStore.active } }
    var planConnected: Bool { activePlan?.access != nil }

    private func savePlan(_ next: PlanStore) throws {
        try next.save()
        planStore = next
    }

    func connectPlan(_ previous: PlanProfile? = nil) async {
        guard !managingPlan, !busy else { return }
        managingPlan = true
        defer { managingPlan = false }
        error = nil
        do {
            let profile = try await ChatGPTPlan.authorize(previous: previous)
            var next = planStore
            if let index = next.profiles.firstIndex(where: { $0.id == profile.id }) {
                guard next.profiles[index].subject == profile.subject else { throw AppError.message("The signed-in account does not match the saved connection.") }
                next.profiles[index] = profile
            } else { next.profiles.append(profile) }
            next.active = profile.id
            try savePlan(next)
            useChatGPTPlan = true
            if !UserDefaults.standard.bool(forKey: "chatGPTPlanWelcomeShown") {
                planNotice = "Eligible questions will use your ChatGPT plan. Manage StudySide in ChatGPT Settings > Usage."
                UserDefaults.standard.set(true, forKey: "chatGPTPlanWelcomeShown")
            }
        } catch { self.error = error.localizedDescription }
    }

    func selectPlan(_ profile: PlanProfile) async {
        guard !managingPlan, !busy else { return }
        if profile.access == nil { await connectPlan(profile); return }
        do {
            var next = planStore
            next.active = profile.id
            try savePlan(next)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func disconnectPlan() async {
        guard let profile = activePlan, !busy, !managingPlan else { return }
        managingPlan = true
        defer { managingPlan = false }
        var warning: String?
        do { try await ChatGPTPlan.revoke(profile) }
        catch { warning = "Remote sign-out was not confirmed. You can disconnect StudySide in ChatGPT Settings." }
        var next = planStore
        if let index = next.profiles.firstIndex(where: { $0.id == profile.id }) {
            next.profiles[index].access = nil
            next.profiles[index].refresh = nil
            next.profiles[index].idToken = nil
        }
        do { try savePlan(next); error = warning }
        catch { self.error = error.localizedDescription }
    }

    private func planAccess() async throws -> String {
        guard let profile = activePlan, let access = profile.access else { throw AppError.message("Connect your ChatGPT account first.") }
        if profile.expires.timeIntervalSinceNow > 60 { return access }
        let updated = try await ChatGPTPlan.refresh(profile)
        var next = planStore
        guard let index = next.profiles.firstIndex(where: { $0.id == updated.id }), let access = updated.access else {
            throw AppError.message("Your ChatGPT sign-in has expired. Reconnect your account.")
        }
        next.profiles[index] = updated
        try savePlan(next)
        return access
    }

    @Published var settings: AISettings
    @Published var apiKey = ""
    @Published var rememberKey = false
    @Published var windows: [CourseWindow] = []
    @Published var selectedID: UInt32?
    @Published private(set) var systemWindowSelected = false
    @Published private(set) var selectingWindow = false
    @Published var messages: [ChatMessage] = []
    @Published var draft = ""
    @Published var paused = false
    @Published var busy = false
    @Published var loadingWindows = false
    @Published var status = "Select a course window to get started"
    @Published var error: String?
    @Published var preview: NSImage?
    @Published var previewDate: Date?
    @Published var showSettings = false
    @Published var showAppearance = false
    @Published var pinned = UserDefaults.standard.bool(forKey: "windowPinned") {
        didSet { UserDefaults.standard.set(pinned, forKey: "windowPinned") }
    }
    @Published var autoArrangeWindows = UserDefaults.standard.object(forKey: "autoArrangeWindows") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoArrangeWindows, forKey: "autoArrangeWindows") }
    }
    @Published private(set) var arrangingWindows = false
    @Published private(set) var arrangementNotice: String?
    weak var assistantWindow: NSWindow?
    private var sharedTarget: SharedWindowTarget?
    private var arrangementTask: Task<Void, Never>?
    @Published private(set) var arrangementNeedsPermission = false

    func retryArrangementAfterSettings() {
        guard arrangementNeedsPermission, !arrangingWindows,
              WindowArrangement.trusted(prompt: false) else { return }
        arrangeWindows()
    }

    func arrangeWindows() {
        let previousArrangement = arrangementTask
        previousArrangement?.cancel()
        guard let target = sharedTarget else {
            arrangementNotice = "Select the course window again. On older macOS versions, use the window list to enable automatic arrangement."
            return
        }
        guard let assistant = assistantWindow else {
            arrangementNotice = "StudySide's window is not ready. Click Arrange Again in a moment."
            return
        }
        arrangingWindows = true
        arrangementNotice = nil
        arrangementNeedsPermission = false
        arrangementTask = Task {
            await previousArrangement?.value
            guard !Task.isCancelled else { return }
            do {
                try await WindowArrangement.arrange(target: target, assistant: assistant)
                guard !Task.isCancelled else { return }
                arrangementNotice = nil
                arrangingWindows = false
            } catch {
                guard !Task.isCancelled else { return }
                arrangementNotice = error.localizedDescription
                if case WindowArrangement.Failure.permissionRequired = error {
                    arrangementNeedsPermission = true
                }
                arrangingWindows = false
            }
        }
    }

    private func updateSharedTarget(_ source: SCWindow?) {
        arrangementTask?.cancel()
        arrangingWindows = false
        arrangementNotice = nil
        arrangementNeedsPermission = false
        sharedTarget = source.flatMap { source in
            guard let pid = source.owningApplication?.processID else { return nil }
            return SharedWindowTarget(processID: pid, title: source.title ?? "", frame: source.frame)
        }
        if autoArrangeWindows { arrangeWindows() }
    }

    private var keyLoaded = false
    private var systemPicker: SystemWindowPicker?
    private var pickedWindow: PickedWindow?
    private var capturing = false
    private var requestTask: Task<Void, Never>?
    private var requestToken: UUID?
    var selectedWindow: CourseWindow? { windows.first { $0.id == selectedID } }
    var hasWindow: Bool { systemWindowSelected || selectedID != nil }

    func chooseSystemWindow() {
        guard !busy, !capturing, !selectingWindow else { return }
        selectingWindow = true
        error = nil
        let picker = SystemWindowPicker { [weak self] result in
            guard let self else { return }
            self.selectingWindow = false
            self.systemPicker = nil
            switch result {
            case .success(let filter?):
                self.pickedWindow = PickedWindow(filter: filter)
                self.systemWindowSelected = true
                self.selectedID = nil
                self.preview = nil
                self.previewDate = nil
                self.paused = false
                if #available(macOS 15.2, *) {
                    self.updateSharedTarget(filter.includedWindows.first)
                } else {
                    self.updateSharedTarget(nil)
                }
            case .success(nil): break
            case .failure(let error):
                self.error = "The system picker could not open: \(error.localizedDescription). You can also use StudySide's window list in the top-right menu."
            }
        }
        systemPicker = picker
        picker.present()
    }

    func chooseListedWindow(_ id: UInt32) {
        guard !busy, !capturing, !selectingWindow else { return }
        pickedWindow = nil
        systemWindowSelected = false
        selectedID = id
        preview = nil
        previewDate = nil
        paused = false
        error = nil
        updateSharedTarget(windows.first { $0.id == id }?.source)
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "settings"), let saved = try? JSONDecoder().decode(AISettings.self, from: data) { settings = saved }
        else { settings = AISettings() }
        rememberKey = UserDefaults.standard.bool(forKey: "rememberKey")
    }

    func loadKeyIfNeeded() {
        guard localSubscription == nil, !useChatGPTPlan, !keyLoaded else { return }
        keyLoaded = true
        if rememberKey { apiKey = KeyStore.load() }
    }

    func saveSettings() {
        do {
            _ = try settings.endpoint()
            try KeyStore.save(rememberKey ? apiKey.trimmingCharacters(in: .whitespacesAndNewlines) : "")
            UserDefaults.standard.set(try JSONEncoder().encode(settings), forKey: "settings")
            UserDefaults.standard.set(rememberKey, forKey: "rememberKey")
            showSettings = false
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func refreshWindows() async {
        guard !loadingWindows else { return }
        loadingWindows = true
        defer { loadingWindows = false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let ownPID = ProcessInfo.processInfo.processIdentifier
            windows = content.windows.filter {
                $0.owningApplication?.processID != ownPID && $0.windowLayer == 0 &&
                $0.frame.width > 180 && $0.frame.height > 120 && !($0.title ?? "").isEmpty
            }.map { CourseWindow(source: $0) }.sorted { $0.label.localizedCompare($1.label) == .orderedAscending }
            if let selectedID, !windows.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
                preview = nil
                previewDate = nil
            }
            if windows.isEmpty { error = "No course windows were found. Open your PDF or slides. If needed, allow Screen Recording in System Settings, then restart StudySide." }
            else { error = nil }
        } catch {
            let reason = error as NSError
            self.error = "Could not read the window list (\(reason.domain) \(reason.code)). Use Choose with System Picker to share a specific window."
        }
    }

    func capture() async throws -> (Data, String) {
        guard !capturing else { throw AppError.message("Capturing the course window. Please wait.") }
        capturing = true
        defer { capturing = false }
        if let pickedWindow {
            do {
                return try prepareCapture(try await pickedWindow.image(), name: "Shared course window")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                self.pickedWindow = nil
                systemWindowSelected = false
                preview = nil
                previewDate = nil
                throw AppError.message("Could not capture the selected window. Keep it open, then click Select Course Window and choose it again.\n\(error.localizedDescription)")
            }
        }
        guard let id = selectedID else { throw AppError.message("Select a course window first.") }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == id }) else {
            selectedID = nil
            throw AppError.message("The course window is closed, minimized, or unavailable. Select it again.")
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let width = max(1, window.frame.width), height = max(1, window.frame.height)
        let scale = min(2, 2200 / max(width, height))
        config.width = max(1, Int(width * scale))
        config.height = max(1, Int(height * scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return try prepareCapture(image, name: CourseWindow(source: window).label)
    }

    private func prepareCapture(_ image: CGImage, name: String) throws -> (Data, String) {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.88]) else {
            throw AppError.message("Could not create the screenshot. Please try again.")
        }
        preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        previewDate = Date()
        return (jpeg, name)
    }

    func previewWindow() async {
        guard !busy, !arrangingWindows else { return }
        do { _ = try await capture(); error = nil }
        catch { self.error = error.localizedDescription }
    }

    func send(_ prompt: String? = nil) {
        let question = (prompt ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !capturing, !selectingWindow, !arrangingWindows, !managingPlan, !question.isEmpty else { return }
        let nativeProvider = localSubscription
        let usePlan = nativeProvider == nil && useChatGPTPlan
        let nativeGeminiModel = geminiSubscriptionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if let nativeProvider {
            guard nativeProvider.executable != nil else {
                error = "Install and sign in to the official " + nativeProvider.name + " client first."; showSettings = true; return
            }
            if nativeProvider == .gemini && !nativeGeminiModel.hasPrefix("gemini-") {
                error = "Enter a Gemini model ID, such as gemini-3.8-flash-medium."; showSettings = true; return
            }
        } else if usePlan {
            guard planConnected else { error = "Connect your ChatGPT account and allow plan usage first."; showSettings = true; return }
        } else {
            do { _ = try settings.endpoint() }
            catch { self.error = error.localizedDescription; showSettings = true; return }
        }
        if !paused && !hasWindow { error = "Click Select Course Window first, or pause capture to send text only."; return }
        busy = true
        error = nil
        let token = UUID()
        requestToken = token
        let inputDraft = draft
        let requestSettings = settings
        let requestKey = apiKey
        requestTask = Task {
            var pendingMessageID: UUID?
            defer {
                if requestToken == token { streamingReply = ""; busy = false; requestToken = nil; requestTask = nil }
            }
            do {
                var picture: Data?
                var name: String?
                if !paused {
                    status = "Capturing the course window…"
                    let result = try await capture()
                    picture = result.0
                    name = result.1
                }
                try Task.checkCancellation()
                let userMessage = ChatMessage(role: "user", text: question, jpeg: picture, windowName: name)
                let responseHistory = messages + [userMessage]
                messages.append(userMessage)
                pendingMessageID = userMessage.id
                if draft == inputDraft { draft = "" }
                status = "Thinking…"
                let answer: String
                if let nativeProvider {
                    status = "Waiting for " + nativeProvider.name + " via the official client…"
                    answer = try await nativeProvider.reply(messages: responseHistory, geminiModel: nativeGeminiModel)
                } else if usePlan {
                    let access = try await planAccess()
                    try Task.checkCancellation()
                    answer = try await ChatGPTPlan.reply(access: access, messages: responseHistory) { [weak self] text in
                        self?.streamingReply = text
                    }
                } else {
                    answer = try await ChatAPI.reply(settings: requestSettings, key: requestKey, messages: responseHistory)
                }
                try Task.checkCancellation()
                messages.append(ChatMessage(role: "assistant", text: answer))
                if messages.count > 40 { messages.removeFirst(messages.count - 40) }
                status = "Ready for your next question"
            } catch {
                if let pendingMessageID { messages.removeAll { $0.id == pendingMessageID } }
                if draft.isEmpty { draft = question }
                if Task.isCancelled { status = "Stopped. You can ask again." }
                else {
                    self.error = error.localizedDescription
                    status = "Message not completed"
                    if draft.isEmpty { draft = question }
                }
            }
        }
    }

    func stop() { requestTask?.cancel() }
    func clear() {
        guard !busy else { return }
        messages.removeAll(); preview = nil; previewDate = nil; error = nil
        status = "New conversation ready"
    }
    func permissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }
    func exportChat() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "StudySide Notes.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = "StudySide Study Notes\n\n" + messages.map {
            let body = $0.role == "assistant" ? AnswerFormatting.plainText($0.text) : $0.text
            return "\($0.role == "user" ? "You" : "StudySide")\n\n\(body)" + ($0.windowName.map { "\n\nCourse window: \($0)" } ?? "")
        }.joined(separator: "\n\n")
        do { try text.write(to: url, atomically: true, encoding: .utf8) }
        catch { self.error = "Export failed: \(error.localizedDescription)" }
    }
}
