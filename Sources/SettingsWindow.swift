import AppKit

private final class SettingsContentView: NSView {
    override var isFlipped: Bool { true }
}

protocol ClaudeCredentialStore {
    func hasClaudeAPIKey() throws -> Bool
    func loadClaudeAPIKey() throws -> String?
    func saveClaudeAPIKey(_ key: String, workspaceID: String) throws
    func deleteClaudeAPIKey() throws
}

extension ProviderSettings: ClaudeCredentialStore {}

final class ProviderSettingsWindow: NSObject, NSWindowDelegate {
    var onChange: (() -> Void)?
    private let settings: ProviderSettings
    private let credentials: ClaudeCredentialStore
    private let keyVerifier: ClaudeKeyVerifier
    init(settings: ProviderSettings = .shared, credentials: ClaudeCredentialStore? = nil,
         keyVerifier: ClaudeKeyVerifier = ClaudeKeyVerifier()) {
        self.settings = settings
        self.credentials = credentials ?? settings
        self.keyVerifier = keyVerifier
        super.init()
    }
    private var window: NSWindow?
    private var onboarding = false
    private var choosingProvider = false
    private let root = NSStackView()
    private let settingsBody = NSStackView()
    private let codexSection = NSStackView()
    private let claudeSection = NSStackView()
    private let scroll = NSScrollView()
    private let interviewToggle = NSButton(checkboxWithTitle: "Ask clarifying questions before summarizing", target: nil, action: nil)
    private let picker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let providerDetail = NSTextField(wrappingLabelWithString: "")
    private let connectionDetail = NSTextField(wrappingLabelWithString: "")
    private let codexModelField = NSTextField()
    private let saveCodexModelButton = NSButton(title: "Save model", target: nil, action: nil)
    private let advancedButton = NSButton(title: "Model options", target: nil, action: nil)
    private var advancedExpanded = false
    private let secureKeyField = NSSecureTextField()
    private let visibleKeyField = NSTextField()
    private let revealKeyButton = NSButton(checkboxWithTitle: "Show key", target: nil, action: nil)
    private let keyFields = NSStackView()
    private var keyField: NSTextField { revealKeyButton.state == .on ? visibleKeyField : secureKeyField }
    private let workspaceLabel = NSTextField(labelWithString: "Workspace ID")
    private let workspaceField = NSTextField()
    private let workspaceHelpButton = NSButton(title: "Find workspace ID ↗", target: nil, action: nil)
    private let changeWorkspaceButton = NSButton(title: "Change workspace…", target: nil, action: nil)
    private let pasteKeyButton = NSButton(title: "Paste & connect", target: nil, action: nil)
    private let saveKeyButton = NSButton(title: "Connect", target: nil, action: nil)
    private let removeKeyButton = NSButton(title: "Remove key", target: nil, action: nil)
    private let getKeyButton = NSButton(title: "Get an API key ↗", target: nil, action: nil)
    private let keyStatus = NSTextField(wrappingLabelWithString: "")
    private let keyInstructions = NSTextField(wrappingLabelWithString: "")
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)
    private let setupButton = NSButton(title: "Run Setup Again…", target: nil, action: nil)
    private let formatOnlyButton = NSButton(title: "Use Format Only", target: nil, action: nil)
    private let backButton = NSButton(title: "Back", target: nil, action: nil)
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private let heading = NSTextField(labelWithString: "")
    private let welcomeBrand = NSStackView()
    private let intro = NSTextField(wrappingLabelWithString: "")
    private var keyCheckGeneration = 0
    private var workspaceRequired = false
    private var pendingKeyForVerification: String?
    private var checkingKey = false
    private var connectionFailed = false

    func show(onboarding: Bool = false) {
        self.onboarding = onboarding
        choosingProvider = !onboarding
        if window == nil { makeWindow() }
        keyCheckGeneration += 1
        workspaceRequired = settings.claudeNeedsWorkspaceID
        pendingKeyForVerification = nil
        checkingKey = false; connectionFailed = false
        clearKeyFields()
        revealKeyButton.state = .off
        visibleKeyField.isHidden = true; secureKeyField.isHidden = false
        codexModelField.stringValue = settings.codexModel ?? ""
        workspaceField.stringValue = settings.claudeWorkspaceID ?? ""
        showFeedback("")
        picker.selectItem(withTag: SummaryProvider.allCases.firstIndex(of: settings.defaultProvider) ?? 0)
        interviewToggle.state = settings.clarificationInterviewEnabled ? .on : .off
        refresh()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(onboarding ? doneButton : picker)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configure(_ stack: NSStackView, spacing: CGFloat = 12) {
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing
    }
    private func label(_ text: String, in stack: NSStackView, secondary: Bool = false) {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 13)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        stack.addArrangedSubview(field)
        field.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func makeWindow() {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 550, height: 460), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.delegate = self
        let document = SettingsContentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView!.addSubview(scroll)
        configure(root, spacing: 16)
        root.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(root)
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            root.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -28),
            root.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            root.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20)
        ])
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        let ferryIcon = NSImageView()
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            ferryIcon.image = NSImage(contentsOf: url)
        }
        ferryIcon.imageScaling = .scaleProportionallyUpOrDown
        ferryIcon.setAccessibilityElement(false)
        NSLayoutConstraint.activate([
            ferryIcon.widthAnchor.constraint(equalToConstant: 72),
            ferryIcon.heightAnchor.constraint(equalToConstant: 72)
        ])
        let welcomeTitle = NSTextField(labelWithString: "Welcome to Note Ferry")
        welcomeTitle.font = .systemFont(ofSize: 22, weight: .semibold)
        let welcomeTagline = NSTextField(labelWithString: "A smooth crossing from text to notes.")
        welcomeTagline.font = .systemFont(ofSize: 14)
        welcomeTagline.textColor = .secondaryLabelColor
        let welcomeText = NSStackView(views: [welcomeTitle, welcomeTagline])
        configure(welcomeText, spacing: 4)
        welcomeBrand.orientation = .horizontal
        welcomeBrand.alignment = .centerY
        welcomeBrand.spacing = 18
        welcomeBrand.addArrangedSubview(ferryIcon)
        welcomeBrand.addArrangedSubview(welcomeText)
        root.addArrangedSubview(welcomeBrand)
        root.addArrangedSubview(heading)
        intro.font = .systemFont(ofSize: 13); intro.textColor = .secondaryLabelColor
        root.addArrangedSubview(intro)
        intro.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        configure(settingsBody)
        root.addArrangedSubview(settingsBody)
        settingsBody.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        label("Default summarizer", in: settingsBody)
        for provider in SummaryProvider.allCases {
            picker.addItem(withTitle: provider.displayName)
            picker.lastItem?.tag = SummaryProvider.allCases.firstIndex(of: provider) ?? 0
        }
        picker.target = self; picker.action = #selector(providerChanged)
        picker.setAccessibilityLabel("Default summarizer")
        settingsBody.addArrangedSubview(picker)
        providerDetail.font = .systemFont(ofSize: 13); providerDetail.textColor = .secondaryLabelColor
        settingsBody.addArrangedSubview(providerDetail)
        providerDetail.widthAnchor.constraint(equalTo: settingsBody.widthAnchor).isActive = true
        connectionDetail.font = .systemFont(ofSize: 12); connectionDetail.textColor = .secondaryLabelColor
        settingsBody.addArrangedSubview(connectionDetail)
        connectionDetail.widthAnchor.constraint(equalTo: settingsBody.widthAnchor).isActive = true
        advancedButton.isBordered = false; advancedButton.target = self; advancedButton.action = #selector(toggleAdvanced)
        settingsBody.addArrangedSubview(advancedButton)
        configure(codexSection, spacing: 8)
        settingsBody.addArrangedSubview(codexSection)
        codexSection.widthAnchor.constraint(equalTo: settingsBody.widthAnchor).isActive = true
        codexModelField.placeholderString = "Codex default"
        codexModelField.setAccessibilityLabel("Codex model ID")
        codexModelField.isAutomaticTextCompletionEnabled = false
        codexModelField.target = self; codexModelField.action = #selector(saveCodexModel)
        saveCodexModelButton.target = self; saveCodexModelButton.action = #selector(saveCodexModel)
        saveCodexModelButton.bezelStyle = .rounded
        let modelRow = NSStackView(views: [codexModelField, saveCodexModelButton])
        modelRow.spacing = 8
        codexSection.addArrangedSubview(modelRow)
        modelRow.widthAnchor.constraint(equalTo: codexSection.widthAnchor).isActive = true
        label("Leave blank for Codex’s default, or enter a model ID available to your account.", in: codexSection, secondary: true)
        configure(claudeSection, spacing: 10)
        settingsBody.addArrangedSubview(claudeSection)
        claudeSection.widthAnchor.constraint(equalTo: settingsBody.widthAnchor).isActive = true
        keyStatus.font = .systemFont(ofSize: 13, weight: .medium)
        claudeSection.addArrangedSubview(keyStatus)
        keyInstructions.font = .systemFont(ofSize: 12); keyInstructions.textColor = .secondaryLabelColor
        claudeSection.addArrangedSubview(keyInstructions)
        keyInstructions.widthAnchor.constraint(equalTo: claudeSection.widthAnchor).isActive = true
        for field in [secureKeyField, visibleKeyField] {
            field.placeholderString = "Claude API key"
            field.setAccessibilityLabel("Claude API key")
            field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            field.isAutomaticTextCompletionEnabled = false
            field.contentType = NSTextContentType(rawValue: "APIKey")
            field.target = self; field.action = #selector(saveKey)
            keyFields.addArrangedSubview(field)
        }
        revealKeyButton.target = self; revealKeyButton.action = #selector(revealKey)
        keyFields.addArrangedSubview(revealKeyButton); keyFields.spacing = 8
        claudeSection.addArrangedSubview(keyFields)
        keyFields.widthAnchor.constraint(equalTo: claudeSection.widthAnchor).isActive = true
        visibleKeyField.isHidden = true
        claudeSection.addArrangedSubview(workspaceLabel)
        workspaceField.placeholderString = "wrkspc_…"
        workspaceField.setAccessibilityLabel("Claude workspace ID")
        workspaceField.target = self; workspaceField.action = #selector(saveKey)
        claudeSection.addArrangedSubview(workspaceField)
        workspaceField.widthAnchor.constraint(equalTo: claudeSection.widthAnchor).isActive = true
        for button in [workspaceHelpButton, changeWorkspaceButton, removeKeyButton, getKeyButton] {
            button.isBordered = false; button.target = self; claudeSection.addArrangedSubview(button)
        }
        workspaceHelpButton.action = #selector(openClaudeWorkspaces)
        changeWorkspaceButton.action = #selector(changeWorkspace)
        removeKeyButton.action = #selector(removeKey); getKeyButton.action = #selector(openClaudeConsole)
        let keyActions = NSStackView(views: [pasteKeyButton, saveKeyButton]); keyActions.spacing = 8
        claudeSection.addArrangedSubview(keyActions)
        pasteKeyButton.target = self; pasteKeyButton.action = #selector(pasteKey)
        saveKeyButton.target = self; saveKeyButton.action = #selector(saveKey)
        pasteKeyButton.bezelStyle = .rounded; saveKeyButton.bezelStyle = .rounded
        label("Stored in Mac Keychain. Connecting checks your key with Anthropic; no notes are sent.", in: claudeSection, secondary: true)
        let separator = NSBox(); separator.boxType = .separator
        settingsBody.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: settingsBody.widthAnchor).isActive = true
        interviewToggle.target = self; interviewToggle.action = #selector(interviewChanged)
        settingsBody.addArrangedSubview(interviewToggle)
        label("Adds time and model usage. You can skip questions when they appear.", in: settingsBody, secondary: true)
        feedback.font = .systemFont(ofSize: 12); feedback.isHidden = true
        root.addArrangedSubview(feedback)
        feedback.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [setupButton, backButton, formatOnlyButton, spacer, doneButton])
        footer.orientation = .horizontal; footer.spacing = 10; footer.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView!.addSubview(footer)
        for button in [setupButton, backButton, formatOnlyButton, doneButton] { button.target = self; button.bezelStyle = .rounded }
        setupButton.action = #selector(runSetup); backButton.action = #selector(back)
        formatOnlyButton.action = #selector(useFormatOnly); doneButton.action = #selector(done)
        doneButton.keyEquivalent = "\r"; panel.defaultButtonCell = doneButton.cell as? NSButtonCell
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            footer.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 28),
            footer.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -28),
            footer.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor, constant: -20)
        ])
        window = panel
    }

    private func refresh() {
        let welcome = onboarding && !choosingProvider
        window?.title = onboarding ? "Set Up Note Ferry" : "Note Ferry Settings"
        heading.stringValue = welcome ? "Welcome to Note Ferry" : (onboarding ? "Choose a summarizer" : "Settings")
        welcomeBrand.isHidden = !welcome
        heading.isHidden = welcome
        intro.stringValue = welcome
            ? "Bring your writing, transcripts, or rough ideas. Note Ferry turns them into tidy notes, ready for Apple Notes.\n\nStart with formatting on your Mac, or connect a summarizer to find the essentials."
            : "Choose how your text is processed. You can change this for each text."
        intro.isHidden = !onboarding
        settingsBody.isHidden = welcome
        setupButton.isHidden = onboarding
        backButton.isHidden = !onboarding || welcome
        formatOnlyButton.isHidden = !onboarding
        doneButton.title = welcome ? "Set Up Summaries" : (onboarding ? "Get Started" : "Done")
        let chosen = SummaryProvider.allCases[max(0, picker.indexOfSelectedItem)]
        doneButton.isEnabled = true
        switch chosen {
        case .apple:
            providerDetail.stringValue = LocalModelAvailability.message ?? "Summarizes on this Mac. No text leaves your device."
            if onboarding && !welcome { doneButton.isEnabled = LocalModelAvailability.message == nil }
        case .codex:
            providerDetail.stringValue = "Text, context, and answers are sent to OpenAI using your Codex account."
        case .claude:
            providerDetail.stringValue = "Text, context, and answers are sent to Anthropic. API use is billed separately."
        }
        connectionDetail.isHidden = true
        if chosen == .codex {
            do { _ = try CodexDiscovery().resolve() }
            catch {
                connectionDetail.isHidden = false; connectionDetail.stringValue = error.localizedDescription
                if onboarding && !welcome { doneButton.isEnabled = false }
            }
        }
        advancedButton.isHidden = chosen != .codex
        advancedButton.title = advancedExpanded ? "Hide model options" : "Model options"
        codexSection.isHidden = chosen != .codex || !advancedExpanded
        claudeSection.isHidden = chosen != .claude
        if chosen == .claude {
            let hasKey = (try? credentials.hasClaudeAPIKey()) ?? false
            keyStatus.stringValue = hasKey ? "Key saved" : "Connect Claude"
            if let name = settings.claudeWorkspaceName, hasKey { keyStatus.stringValue += " · \(name) workspace" }
            keyInstructions.stringValue = "Enter the Default workspace ID. Your key is already saved."
            keyInstructions.isHidden = !workspaceRequired || !hasKey
            keyFields.isHidden = workspaceRequired && hasKey
            pasteKeyButton.isHidden = workspaceRequired && hasKey
            saveKeyButton.title = workspaceRequired && hasKey ? "Connect workspace" : (hasKey ? (connectionFailed ? "Retry connection" : "Update connection") : "Connect")
            removeKeyButton.isHidden = !hasKey; getKeyButton.isHidden = hasKey
            workspaceLabel.isHidden = !workspaceRequired; workspaceField.isHidden = !workspaceRequired
            workspaceHelpButton.isHidden = !workspaceRequired
            changeWorkspaceButton.title = settings.claudeWorkspaceID == nil ? "Add workspace…" : "Change workspace…"
            changeWorkspaceButton.isHidden = workspaceRequired || !hasKey
            if onboarding && !welcome { doneButton.isEnabled = hasKey && !workspaceRequired && !checkingKey && !connectionFailed }
        }
        root.layoutSubtreeIfNeeded()
        let preferred = NSSize(width: 550, height: max(welcome ? 220 : 320, root.fittingSize.height + 118))
        if let window, let screen = window.screen ?? NSScreen.main {
            window.setContentSize(AppWindowSizing.contentSize(preferred: preferred, visibleFrame: screen.visibleFrame, styleMask: window.styleMask))
        }
    }
    private func clearKeyFields() { secureKeyField.stringValue = ""; visibleKeyField.stringValue = "" }
    @objc private func revealKey() {
        let previous = revealKeyButton.state == .on ? secureKeyField : visibleKeyField
        let value = previous.stringValue; previous.stringValue = ""
        secureKeyField.isHidden = revealKeyButton.state == .on
        visibleKeyField.isHidden = revealKeyButton.state != .on
        keyField.stringValue = value
        window?.makeFirstResponder(keyField)
    }
    @objc private func toggleAdvanced() { advancedExpanded.toggle(); refresh() }
    @objc private func runSetup() { show(onboarding: true) }
    @objc private func back() { choosingProvider = false; clearKeyFields(); showFeedback(""); refresh() }
    @objc private func useFormatOnly() { completeSetup() }
    private func completeSetup() {
        keyCheckGeneration += 1
        clearKeyFields(); pendingKeyForVerification = nil
        settings.hasCompletedOnboarding = true
        window?.orderOut(nil); onChange?()
    }
    @objc private func interviewChanged() {
        settings.clarificationInterviewEnabled = interviewToggle.state == .on
        onChange?()
    }

    @objc private func providerChanged() {
        let index = picker.indexOfSelectedItem
        guard SummaryProvider.allCases.indices.contains(index) else { return }
        settings.defaultProvider = SummaryProvider.allCases[index]
        showFeedback("")
        refresh()
        onChange?()
    }

    @objc private func saveCodexModel() {
        do {
            try settings.saveCodexModel(codexModelField.stringValue)
            codexModelField.stringValue = settings.codexModel ?? ""
            showFeedback(settings.codexModel == nil ? "Codex will choose its default model." : "Codex model saved.")
            onChange?()
        } catch { showFeedback(error.localizedDescription, isError: true) }
    }

    @objc private func pasteKey() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            showFeedback("The clipboard has no text. Copy an API key first.", isError: true)
            return
        }
        keyField.stringValue = text
        saveKey()
    }

    @objc private func saveKey() {
        do {
            if workspaceRequired && workspaceField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw AppError.message("Enter a workspace ID beginning with wrkspc_.")
            }
            let enteredKey = keyField.stringValue
            let replacingKey = !enteredKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let candidateWorkspaceID = workspaceRequired
                ? try ProviderSettings.validatedClaudeWorkspaceID(workspaceField.stringValue)
                : nil
            let keyForVerification: String?
            if replacingKey {
                keyForVerification = try ProviderSettings.validatedClaudeAPIKey(enteredKey)
                try credentials.saveClaudeAPIKey(enteredKey, workspaceID: "")
                if workspaceRequired { settings.claudeNeedsWorkspaceID = true }
                pendingKeyForVerification = keyForVerification
            } else {
                keyForVerification = pendingKeyForVerification
                guard try credentials.hasClaudeAPIKey() else {
                    throw AppError.message("Paste a Claude API key to continue.")
                }
            }
            keyCheckGeneration += 1
            clearKeyFields()
            refresh()
            onChange?()
            checkSavedKey(key: keyForVerification, workspaceID: candidateWorkspaceID,
                          savedMessage: replacingKey ? "Saved in Keychain." : nil)
        } catch { showFeedback(error.localizedDescription, isError: true) }
    }

    private func checkSavedKey(key suppliedKey: String? = nil, workspaceID candidateWorkspaceID: String? = nil,
                               savedMessage: String? = nil) {
        do {
            guard let key = try suppliedKey ?? credentials.loadClaudeAPIKey() else {
                showFeedback("Save a Claude API key first.", isError: true)
                refresh()
                return
            }
            let workspaceID = candidateWorkspaceID ?? settings.claudeWorkspaceID
            keyCheckGeneration += 1
            let generation = keyCheckGeneration
            checkingKey = true; connectionFailed = false
            refresh()
            showFeedback((savedMessage.map { "\($0) " } ?? "") + "Checking with Anthropic…")
            keyVerifier.verify(key, workspaceID: workspaceID) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self, self.keyCheckGeneration == generation else { return }
                    self.checkingKey = false
                    switch result {
                    case .success(let verification):
                        if case .defaultWorkspace(let id) = verification {
                            do {
                                try self.settings.saveClaudeWorkspaceID(id, name: "Default")
                                self.workspaceField.stringValue = id
                                self.workspaceRequired = false
                                self.settings.claudeNeedsWorkspaceID = false
                                self.pendingKeyForVerification = nil
                                self.refresh()
                                self.showFeedback("Connected to Default workspace.")
                            } catch {
                                self.showFeedback(error.localizedDescription, isError: true)
                            }
                        } else {
                            do {
                                if let candidateWorkspaceID {
                                    try self.settings.saveClaudeWorkspaceID(candidateWorkspaceID)
                                }
                                self.workspaceRequired = false
                                self.settings.claudeNeedsWorkspaceID = false
                                self.pendingKeyForVerification = nil
                                self.refresh()
                                self.showFeedback("Connected.")
                            } catch {
                                self.showFeedback(error.localizedDescription, isError: true)
                            }
                        }
                    case .failure(let error):
                        self.connectionFailed = true
                        if let verificationError = error as? ClaudeKeyVerificationError,
                           case .workspaceRequired = verificationError {
                            self.workspaceRequired = true
                            self.settings.claudeNeedsWorkspaceID = true
                            self.refresh()
                            self.window?.makeFirstResponder(self.workspaceField)
                            self.showFeedback("")
                            return
                        }
                        self.refresh()
                        self.showFeedback(error.localizedDescription, isError: true)
                    }
                }
            }
        } catch { showFeedback(error.localizedDescription, isError: true) }
    }

    @objc private func removeKey() {
        do {
            try credentials.deleteClaudeAPIKey()
            keyCheckGeneration += 1
            clearKeyFields()
            workspaceField.stringValue = ""
            pendingKeyForVerification = nil
            workspaceRequired = false
            showFeedback("Claude API key removed from Keychain.")
            refresh()
            onChange?()
        } catch { showFeedback(error.localizedDescription, isError: true) }
    }

    @objc private func openClaudeConsole() {
        guard let url = URL(string: "https://platform.claude.com/settings/keys") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openClaudeWorkspaces() {
        guard let url = URL(string: "https://platform.claude.com/settings/workspaces") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func changeWorkspace() {
        workspaceRequired = true
        if settings.claudeWorkspaceID == nil {
            settings.claudeNeedsWorkspaceID = true
        }
        refresh()
        window?.makeFirstResponder(workspaceField)
    }

    @objc private func done() {
        if onboarding && !choosingProvider {
            choosingProvider = true; refresh(); window?.makeFirstResponder(picker); return
        }
        if picker.indexOfSelectedItem == SummaryProvider.allCases.firstIndex(of: .codex) {
            do { try settings.saveCodexModel(codexModelField.stringValue) }
            catch { showFeedback(error.localizedDescription, isError: true); return }
        }
        completeSetup()
    }

    func windowWillClose(_ notification: Notification) {
        keyCheckGeneration += 1
        clearKeyFields()
        pendingKeyForVerification = nil
    }

    private func showFeedback(_ message: String, isError: Bool = false) {
        feedback.stringValue = message
        feedback.isHidden = message.isEmpty
        feedback.textColor = isError ? .systemRed : .secondaryLabelColor
    }
}
