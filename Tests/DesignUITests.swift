// AppKit interaction checks appended to an isolated copy of main.swift by test-design-ui.sh.
final class DesignTestCredentials: ClaudeCredentialStore {
    var value: String?
    var saveCount = 0
    var loadCount = 0
    func hasClaudeAPIKey() throws -> Bool { value != nil }
    func loadClaudeAPIKey() throws -> String? { loadCount += 1; return value }
    func saveClaudeAPIKey(_ key: String, workspaceID: String) throws { saveCount += 1; value = key }
    func deleteClaudeAPIKey() throws { value = nil }
}
final class DesignVerificationProtocol: URLProtocol {
    static var statusCode = 503
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
var designChecks = 0
func verify(_ condition: @autoclosure () -> Bool, _ message: String) {
    designChecks += 1
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
func button(_ title: String, in window: NSWindow) -> NSButton {
    descendants(window.contentView!).compactMap { $0 as? NSButton }.first { $0.title == title }!
}
func visible(_ view: NSView) -> Bool {
    !view.isHidden && (view.superview.map(visible) ?? true)
}
func waitForDesignState(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(3)
    while !condition() && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    verify(condition(), "The mocked connection check did not finish")
}
func capture(_ window: NSWindow, _ name: String) throws {
    window.contentView!.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    let view = window.contentView!.superview!
    if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/design-ui/\(name).png"))
    }
}

let testApplication = NSApplication.shared
testApplication.setActivationPolicy(.prohibited)
UserDefaults.standard.register(defaults: ["hasCompletedProviderOnboarding": true])
let controller = AppDelegate()
controller.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
controller.window.setContentSize(NSSize(width: 840, height: 720))
controller.preview.string = "Jamie: The NOVA proposal is ready for one last review. Alex will review pricing tomorrow. Casey can send it after the review. October 30 is a target, not a firm commitment."
controller.contextEditor.string = "NOVA is our scheduling project."
controller.selectedProvider = .codex
controller.showInputControls()
verify(controller.preview.isEditable, "Input is not editable")
verify(controller.primaryButton.isEnabled == true, "Summarize is unavailable with input")
let commandOrder = controller.commandBar.arrangedSubviews.map(ObjectIdentifier.init)
let formatItem = NSMenuItem(title: "Format Only", action: #selector(AppDelegate.formatInput), keyEquivalent: "")
verify(controller.validateMenuItem(formatItem), "Format menu unavailable with input")
try capture(controller.window, "input")
controller.operation = .codex
controller.mode = .processing
controller.showProcessing(.codex, text: controller.preview.string)
verify(controller.primaryButton.isEnabled == false, "Processing allows a second request")
verify(!controller.validateMenuItem(formatItem), "Processing allows Format from menu")
controller.stopInterviewProgress()
controller.showInputControls()
controller.showError(AppError.message("Couldn’t connect. Your text and clipboard were kept."))
verify(!controller.retryButton.isHidden && !controller.recoverySettingsButton.isHidden, "Error has no recovery commands")
try capture(controller.window, "error")
controller.showInputControls()
verify(controller.retryButton.isHidden, "Stale retry remains after returning to input")
controller.operation = .codex
controller.resultContext = "NOVA is our scheduling project.\n\nClarifications\nOctober 30 is a flexible target."
let summary = try JSONDecoder().decode(Summary.self, from: Data(contentsOf: URL(fileURLWithPath: "Tests/fixture.json")))
controller.display(summary)
controller.detail.stringValue = "Previous clipboard restored."
verify(!controller.preview.isEditable, "Result became editable despite preserved product behavior")
verify(controller.commandBar.arrangedSubviews.map(ObjectIdentifier.init) == commandOrder, "Bottom commands moved after generation")
verify(!controller.contextExpanded, "Result forces secondary context open")
verify(!controller.validateMenuItem(formatItem), "Format menu operates on read-only result")
verify(controller.primaryButton.title == "Copy summary", "Result primary action is not Copy")
try capture(controller.window, "result")
controller.window.setContentSize(NSSize(width: 620, height: 560))
try capture(controller.window, "result-compact")
verify(controller.preview.enclosingScrollView!.frame.height >= 100, "Compact window collapsed the note")
verify(controller.commandBar.convert(controller.commandBar.bounds, to: controller.window.contentView).minY >= 16, "Bottom commands extend outside the compact window")
verify(controller.commandBar.convert(controller.commandBar.bounds, to: controller.window.contentView).maxX <= controller.window.contentView!.bounds.maxX - 16, "Bottom commands overflow the compact window")
controller.window.orderOut(nil)

let suite = "me.nieder.note-ferry.design-tests.\(UUID().uuidString)"
let preferences = UserDefaults(suiteName: suite)!
defer { preferences.removePersistentDomain(forName: suite) }
let settings = ProviderSettings(defaults: preferences, bundleIdentifier: suite)
settings.defaultProvider = .codex
try settings.saveCodexModel("example-model")
settings.clarificationInterviewEnabled = false
let testCredentials = DesignTestCredentials()
let verificationConfig = URLSessionConfiguration.ephemeral
verificationConfig.protocolClasses = [DesignVerificationProtocol.self]
let verificationSession = URLSession(configuration: verificationConfig)
defer { verificationSession.invalidateAndCancel() }
let settingsController = ProviderSettingsWindow(settings: settings, credentials: testCredentials,
    keyVerifier: ClaudeKeyVerifier(session: verificationSession))
settingsController.show(onboarding: true)
let setup = NSApp.windows.first { $0.title == "Set Up Note Ferry" }!
try capture(setup, "setup-welcome")
verify(!visible(button("Paste & connect", in: setup)), "Welcome exposes credential fields")
button("Set Up Summaries", in: setup).performClick(nil)
verify(!visible(button("Paste & connect", in: setup)), "Codex setup exposes Claude credentials")
try capture(setup, "setup-codex")
button("Use Format Only", in: setup).performClick(nil)
verify(settings.hasCompletedOnboarding, "Format-only path did not complete onboarding")
verify(settings.defaultProvider == .codex && settings.codexModel == "example-model", "Setup discarded saved provider preferences")
verify(!settings.clarificationInterviewEnabled, "Setup reset the interview preference")
settingsController.show()
button("Run Setup Again…", in: setup).performClick(nil)
verify(setup.title == "Set Up Note Ferry" && visible(button("Set Up Summaries", in: setup)), "Settings cannot rerun the welcome flow")
verify(settings.codexModel == "example-model", "Rerunning setup discarded the saved model")
button("Set Up Summaries", in: setup).performClick(nil)
let provider = descendants(setup.contentView!).compactMap { $0 as? NSPopUpButton }.first!
provider.selectItem(withTitle: "Claude")
NSApp.sendAction(provider.action!, to: provider.target, from: provider)
verify(visible(button("Paste & connect", in: setup)), "Claude connection controls are unavailable")
let secure = descendants(setup.contentView!).compactMap { $0 as? NSSecureTextField }.first!
verify(visible(secure), "API key is not masked by default")
verify(!button("Get Started", in: setup).isEnabled, "Setup completes without a Claude connection")
try capture(setup, "setup-claude")
setup.setContentSize(NSSize(width: 550, height: 460))
setup.contentView!.layoutSubtreeIfNeeded()
let footerButton = button("Get Started", in: setup)
verify(setup.contentView!.bounds.contains(footerButton.convert(footerButton.bounds, to: setup.contentView)), "Setup primary action is outside a short window")
let settingsScroll = descendants(setup.contentView!).compactMap { $0 as? NSScrollView }.first!
verify(settingsScroll.documentView!.frame.height > settingsScroll.contentSize.height, "Long setup cannot scroll")
try capture(setup, "setup-compact")
testCredentials.value = "synthetic-test-key"
settingsController.show(onboarding: true)
button("Set Up Summaries", in: setup).performClick(nil)
button("Update connection", in: setup).performClick(nil)
waitForDesignState {
    descendants(setup.contentView!).compactMap { $0 as? NSButton }.contains { $0.title == "Retry connection" }
}
verify(!button("Get Started", in: setup).isEnabled, "Failed verification allows onboarding to finish")
verify(secure.stringValue.isEmpty, "Saved-key verification exposed the key in the entry field")
DesignVerificationProtocol.statusCode = 200
button("Retry connection", in: setup).performClick(nil)
waitForDesignState { button("Get Started", in: setup).isEnabled }
verify(DesignVerificationProtocol.requests == 2 && testCredentials.loadCount == 2, "Retry did not recheck the saved key")
verify(testCredentials.saveCount == 0, "Retry unexpectedly replaced the saved credential")
setup.orderOut(nil)
print("Passed \(designChecks) design UI checks. No network, Keychain writes, model requests, or general clipboard writes.")
