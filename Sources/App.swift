import SwiftUI
import AppKit


final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

#if !PREVIEW
@main struct StudySideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = StudyModel()
    var body: some Scene {
        WindowGroup("StudySide") {
            ContentView(model: model)
                .frame(minWidth: 390, idealWidth: 440, minHeight: 620, idealHeight: 820)
                .environment(\.studyTheme, model.theme)
                .environment(\.locale, Locale(identifier: "en"))
                .preferredColorScheme(model.theme.colorScheme)
        }
        .defaultSize(width: 440, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Conversation") { model.clear() }.keyboardShortcut("n").disabled(model.busy)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Appearance…") { model.showAppearance = true }
                Divider()
                Button("Model Settings…") { model.loadKeyIfNeeded(); model.showSettings = true }.keyboardShortcut(",")
            }
        }
    }
}
#endif

final class WindowLevelView: NSView {
    var onWindow: ((NSWindow?) -> Void)?
    var pinned = false {
        didSet { applyWindowLevel() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWindowLevel()
        onWindow?(window)
    }

    private func applyWindowLevel() {
        window?.level = pinned ? .floating : .normal
    }
}

struct WindowLevel: NSViewRepresentable {
    let pinned: Bool
    var onWindow: (NSWindow?) -> Void = { _ in }
    func makeNSView(context: Context) -> WindowLevelView {
        let view = WindowLevelView()
        view.pinned = pinned
        view.onWindow = onWindow
        return view
    }
    func updateNSView(_ view: WindowLevelView, context: Context) {
        view.pinned = pinned
        view.onWindow = onWindow
    }
}

struct ContentView: View {
    @ObservedObject var model: StudyModel
    private var theme: StudyTheme { model.theme }
    private var ink: Color { theme.ink }
    private var accent: Color { theme.accent }
    private var paper: Color { theme.canvas }
    @State private var showWindows = false
    @State private var showPreview = false
    @State private var confirmClear = false
    @State private var inputFocusRequest = 0
    var body: some View {
        VStack(spacing: 0) {
            header
            sourceCard.padding(.horizontal, 18).padding(.bottom, 12)
            Divider().opacity(0.35)
            if let error = model.error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.foregroundStyle(Color(red: 0.58, green: 0.27, blue: 0.13))
                    .padding(12).background(Color.orange.opacity(0.09)).padding(.horizontal, 14).padding(.top, 8)
            }
            conversation
            composer
        }
        .background(ThemeBackdrop(theme: theme)).foregroundStyle(ink).tint(accent)
        .background(WindowLevel(pinned: model.pinned) { [weak model] window in model?.assistantWindow = window })
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.retryArrangementAfterSettings()
        }
        .sheet(isPresented: $model.showSettings) { SettingsView(model: model) }
        .sheet(isPresented: $showWindows) { windowPicker }
        .sheet(isPresented: $showPreview) { previewSheet }
        .sheet(isPresented: $model.showAppearance) { AppearanceView(model: model) }
        .confirmationDialog("Clear this conversation?", isPresented: $confirmClear) {
            Button("Clear Conversation", role: .destructive) { model.clear() }
        } message: { Text("This cannot be undone. Export your notes first if you want to keep them.") }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "book").font(.system(size: 24, weight: .light)).foregroundStyle(ink)
                .frame(width: 34, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("StudySide").font(.system(size: 20, weight: .semibold, design: theme.design))
                Text(theme.name + " / Study companion").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.pinned.toggle() } label: {
                Image(systemName: model.pinned ? "pin.fill" : "pin").foregroundStyle(model.pinned ? accent : .secondary)
                    .frame(width: 32, height: 32)
            }.help(model.pinned ? "Unpin to allow other windows to cover StudySide" : "Keep StudySide above other windows")
                .accessibilityLabel(model.pinned ? "Unpin Window" : "Pin Window")
            Menu {
                Button("Appearance…") { model.showAppearance = true }
                Divider()
                Button("Model Settings…") { model.loadKeyIfNeeded(); model.showSettings = true }
                Toggle("Arrange Automatically After Selection", isOn: $model.autoArrangeWindows)
                Button("Arrange Again") { model.arrangeWindows() }.disabled(!model.hasWindow || model.arrangingWindows)
                Divider()
                Button("Choose from Window List…") { showWindows = true }.disabled(model.busy || model.selectingWindow)
                Button("Export Study Notes…") { model.exportChat() }.disabled(model.messages.isEmpty)
                Button("New Conversation…") { confirmClear = true }.disabled(model.busy || model.messages.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 32, height: 32)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
        }.buttonStyle(.plain).padding(.horizontal, 22).padding(.top, 32).padding(.bottom, 22)
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Circle().fill(model.paused ? Color.orange : (model.hasWindow ? accent : Color.gray)).frame(width: 6, height: 6)
                Text(model.paused ? "Capture paused" : "Capture when you ask").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button { model.paused.toggle() } label: {
                    Image(systemName: model.paused ? "play.fill" : "pause.fill").font(.system(size: 11))
                }.buttonStyle(.plain).help(model.paused ? "Resume capture when sending" : "Pause capture; send text and existing context only")
                    .disabled(model.busy)
            }
            Button { model.chooseSystemWindow() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "macwindow").font(.system(size: 21)).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.systemWindowSelected ? "Course window selected" : model.selectedWindow?.app ?? "Select Course Window").font(.system(size: 13, weight: .semibold))
                        Text(model.systemWindowSelected ? "Click to change the shared window" : model.selectedWindow?.title ?? "Choose a window with the macOS picker")
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down").font(.system(size: 10)).foregroundStyle(.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(model.busy || model.selectingWindow)
            if model.hasWindow {
                HStack {
                    Button("Preview Capture") { Task { await model.previewWindow(); if model.preview != nil { showPreview = true } } }
                        .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(accent).disabled(model.busy)
                    Spacer()
                    Button(model.arrangingWindows ? "Arranging…" : "Arrange Again") { model.arrangeWindows() }
                        .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(accent)
                        .disabled(model.arrangingWindows)
                }
            }
            if let notice = model.arrangementNotice {
                VStack(alignment: .leading, spacing: 6) {
                    Text(notice).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.arrangementNeedsPermission {
                        Button("Open Accessibility Settings") { WindowArrangement.openSettings() }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent)
                    }
                }
            }
        }.padding(14).background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius))
            .overlay(RoundedRectangle(cornerRadius: theme.radius).strokeBorder(theme.border))
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if model.messages.isEmpty { welcome }
                    ForEach(model.messages) { message in
                        MessageView(message: message).id(message.id)
                    }
                    if !model.streamingReply.isEmpty {
                        MessageView(message: ChatMessage(role: "assistant", text: model.streamingReply))
                    } else if model.busy {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(model.status).font(.system(size: 12)).foregroundStyle(.secondary) }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(20)
            }.onChange(of: model.messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: model.busy) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            if theme == .iridescent {
                IridescentSculpture().frame(height: 128).frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            } else {
                Spacer().frame(height: 12)
                Image(systemName: "sparkles").font(.system(size: 27, weight: .light)).foregroundStyle(accent)
            }
            Text("Understand this page.\nTake the next step.").font(.system(size: 28, weight: theme == .iridescent ? .light : .medium, design: theme.design)).lineSpacing(5)
            Text("Choose your course window, then ask away.\nEach question includes the current page.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
            VStack(alignment: .leading, spacing: 9) {
                quickQuestion("Explain this page simply", symbol: "text.bubble")
                quickQuestion("How is this formula derived?", symbol: "function")
                quickQuestion("Give me an example for this page", symbol: "lightbulb")
            }.padding(.top, 8)
            if model.localSubscription != nil ? model.localSubscription?.executable == nil : (model.useChatGPTPlan ? !model.planConnected : model.settings.baseURL.isEmpty) {
                Button("Connect an AI model →") { model.loadKeyIfNeeded(); model.showSettings = true }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(accent)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quickQuestion(_ text: String, symbol: String) -> some View {
        Button { model.draft = text; inputFocusRequest += 1 } label: {
            HStack(spacing: 10) { Image(systemName: symbol).frame(width: 15); Text(text); Spacer(); Image(systemName: "arrow.up.left").font(.system(size: 9)) }
                .font(.system(size: 12)).foregroundStyle(ink.opacity(0.8)).padding(12)
                .background(theme.surface, in: BeveledCard(cut: theme == .iridescent ? 10 : 0, radius: theme == .iridescent ? 0 : theme.radius))
                .overlay(BeveledCard(cut: theme == .iridescent ? 10 : 0, radius: theme == .iridescent ? 0 : theme.radius).strokeBorder(theme.border))
        }.buttonStyle(.plain)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            VStack(spacing: 6) {
                MessageInput(text: $model.draft, focusRequest: inputFocusRequest) {
                    model.loadKeyIfNeeded()
                    model.send()
                }
                .overlay(alignment: .topLeading) {
                    if model.draft.isEmpty {
                        Text("What would you like to understand?").font(.system(size: 13)).foregroundStyle(.tertiary)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 3).padding(.top, 4)
                HStack {
                    Text(model.paused ? "Text only · Includes prior context" : "Current page attached when you send")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    if model.busy {
                        Button { model.stop() } label: { Image(systemName: "stop.fill").frame(width: 29, height: 29) }
                            .buttonStyle(.plain).background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9)).help("Stop Response")
                    } else {
                        Button { model.loadKeyIfNeeded(); model.send() } label: {
                            Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.onAccent)
                                .frame(width: 29, height: 29).background(accent, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).keyboardShortcut(.return, modifiers: .command)
                            .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).help("Send (Return)")
                    }
                }
            }.padding(14).background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius + 2))
                .overlay(RoundedRectangle(cornerRadius: theme.radius + 2).strokeBorder(theme == .iridescent ? Color.white.opacity(0.65) : accent.opacity(0.18)))

        }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 14)
    }

    private var windowPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Select Course Window").font(.title3.bold())
                    Text("Open your PDF or slides, then choose a window below.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { showWindows = false }.keyboardShortcut(.cancelAction)
            }
            if model.loadingWindows { ProgressView("Finding available windows…").frame(maxWidth: .infinity) }
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(model.windows) { window in
                        Button {
                            model.chooseListedWindow(window.id)
                            showWindows = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "macwindow").foregroundStyle(accent)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(window.app).font(.system(size: 12, weight: .semibold))
                                    Text(window.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                if window.id == model.selectedID { Image(systemName: "checkmark.circle.fill").foregroundStyle(accent) }
                            }.padding(12).contentShape(Rectangle()).background(theme.surface, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain)
                    }
                }
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Refresh List") { Task { await model.refreshWindows() } }.disabled(model.loadingWindows)
                Spacer()
                Button("Choose with System Picker") { showWindows = false; model.chooseSystemWindow() }
            }.font(.caption)
            Text("Only the window list is loaded here. Screenshots are taken on demand. Reselect if the window closes or is minimized.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(22).frame(width: 460, height: 480).background(paper)
            .task { await model.refreshWindows() }
    }

    private var previewSheet: some View {
        VStack(spacing: 14) {
            HStack { Text("Capture Preview").font(.headline); Spacer(); Button("Close") { showPreview = false }.keyboardShortcut(.cancelAction) }
            if let preview = model.preview { Image(nsImage: preview).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
            if let date = model.previewDate { Text("Captured at \(date.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(Locale(identifier: "en_GB")))) · This preview was not sent to AI").font(.caption).foregroundStyle(.secondary) }
        }.padding(20).frame(width: 620, height: 470).background(paper)
    }
}

struct MessageView: View {
    @Environment(\.studyTheme) private var theme
    private var accent: Color { theme.accent }
    let message: ChatMessage
    @State private var expandImage = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: message.role == "user" ? "person.crop.circle" : "sparkles")
                Text(message.role == "user" ? "You" : "StudySide").fontWeight(.semibold)
                Spacer()
                if message.role == "assistant" {
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(AnswerFormatting.plainText(message.text), forType: .string) }
                    label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).help("Copy Answer")
                }
            }.font(.system(size: 11)).foregroundStyle(.secondary)
            if message.role == "assistant" {
                FormattedAnswer(source: message.text).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(message.text).font(.system(size: 13, design: theme.design)).lineSpacing(5).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let data = message.jpeg, let image = NSImage(data: data) {
                Button { expandImage.toggle() } label: {
                    HStack(spacing: 7) {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 44, height: 30).clipShape(RoundedRectangle(cornerRadius: 4))
                        Text("Screenshot attached · \(message.time.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "en_GB"))))").font(.system(size: 10))
                        Spacer(); Image(systemName: expandImage ? "chevron.up" : "chevron.down").font(.system(size: 9))
                    }.foregroundStyle(.secondary)
                }.buttonStyle(.plain)
                if expandImage { Image(nsImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 7)) }
            }
        }.padding(14).background(message.role == "user" ? accent.opacity(0.065) : theme.surface, in: RoundedRectangle(cornerRadius: theme.radius))
            .overlay(RoundedRectangle(cornerRadius: theme.radius).strokeBorder(theme == .iridescent ? Color.white.opacity(0.45) : .clear, lineWidth: 0.7))
            .shadow(color: .black.opacity(theme == .iridescent ? 0.025 : 0), radius: 12, y: 4)
    }
}

struct SettingsView: View {
    @Environment(\.studyTheme) private var theme
    private var paper: Color { theme.canvas }
    private var accent: Color { theme.accent }
    @ObservedObject var model: StudyModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Connect an AI Model").font(.title3.bold()); Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
            Picker("Provider", selection: Binding(get: { model.backendSelection }, set: { model.backendSelection = $0 })) {
                Text("ChatGPT").tag("chatgpt")
                Text("Claude").tag("claude")
                Text("Gemini").tag("gemini")
                Text("API Key").tag("api")
            }.pickerStyle(.segmented).disabled(model.busy || model.managingPlan)
            if let provider = model.localSubscription {
                localSubscriptionSettings(provider)
            } else if model.useChatGPTPlan {
                planSettings
            } else {
            Text("Connect a model service with image input and Chat Completions support.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            field("API Base URL") { TextField("https://your-provider.example/v1", text: $model.settings.baseURL) }
            field("Model ID") { TextField("Vision model ID from your provider", text: $model.settings.model) }
            field("API Key") { SecureField("Optional for local services", text: $model.apiKey) }
            Toggle("Save API Key in Keychain", isOn: $model.rememberKey).font(.system(size: 12))
            Text("Without Keychain storage, the key lasts only for this session. The base URL and model ID are saved locally. Your questions and screenshots are sent to this provider.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Text("API usage is billed separately.").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Save Settings") { model.saveSettings() }.buttonStyle(.borderedProminent).tint(accent).keyboardShortcut(.defaultAction)
            }
            }
        }.padding(24).frame(width: 470).background(paper).tint(accent)
            .onAppear { model.loadKeyIfNeeded() }
            .onChange(of: model.backendSelection) { _, _ in model.error = nil; model.loadKeyIfNeeded() }
            .alert("ChatGPT Plan Connected", isPresented: Binding(
                get: { model.planNotice != nil }, set: { if !$0 { model.planNotice = nil } }
            )) { Button("Got It") { model.planNotice = nil } } message: { Text(model.planNotice ?? "") }
    }

    private func localSubscriptionSettings(_ provider: LocalSubscription) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(provider.name + " · Official Client")
                .font(.system(size: 16, weight: .semibold))
            Text(provider == .claude
                 ? "StudySide runs the official Claude Code client on this Mac. Sign in with your subscribed account through its official flow. StudySide does not read or store Claude sign-in tokens."
                 : "StudySide runs the official Antigravity CLI using the Gemini allowance available to your Google account. No token or API key is needed in StudySide.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Label(provider.executable == nil ? "Official client not found" : "Official client detected", systemImage: provider.executable == nil ? "exclamationmark.circle" : "checkmark.circle")
                .font(.caption)
            if provider == .gemini {
                field("Gemini Model") { TextField("gemini-3.8-flash-medium", text: $model.geminiSubscriptionModel) }
                Text("Complete the official sign-in flow first. Choose a model available to your Google account. StudySide will not enable extra AI credits or switch to API billing.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Uses Sonnet. StudySide checks the official client's subscription sign-in before sending. It reports an error if your allowance is exhausted.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Open Official Sign-In") { model.openLocalLogin() }
                    .buttonStyle(.borderedProminent).disabled(provider.executable == nil || model.busy)
                Link("Setup Guide", destination: provider.documentation)
            }
            Text("The official client manages sign-in and processes screenshots. Its own history and data settings apply.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var planSettings: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Sign in with ChatGPT. Eligible requests use your plan allowance. StudySide will not switch to paid API usage if you reach your limit.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if let profile = model.activePlan, model.planConnected {
                Label(profile.email, systemImage: "checkmark.circle")
                    .font(.system(size: 13, weight: .semibold))
                Text("GPT-6.1 Sol · Image input supported")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.managingPlan {
                ProgressView("Waiting for ChatGPT…").controlSize(.small)
            } else {
                HStack {
                    Button(model.planConnected ? "Reconnect" : "Continue with ChatGPT") {
                        Task { await model.connectPlan(model.activePlan) }
                    }.buttonStyle(.borderedProminent)
                    if model.planConnected {
                        Button("Sign Out") { Task { await model.disconnectPlan() } }
                    }
                    if !model.planStore.profiles.isEmpty {
                        Menu("Accounts") {
                            ForEach(model.planStore.profiles) { profile in
                                Button("\(profile.email) · \(profile.id.suffix(6))") { Task { await model.selectPlan(profile) } }
                            }
                            Button("Add Account…") { Task { await model.connectPlan() } }
                        }
                    }
                }.disabled(model.busy)
            }
            Link("Manage ChatGPT Usage", destination: URL(string: "https://chatgpt.com/#settings/Usage")!)
                .font(.caption)
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            content().textFieldStyle(.roundedBorder).font(.system(size: 12))
        }
    }
}
