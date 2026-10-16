import AppKit

final class ProviderSettingsWindow: NSObject, NSWindowDelegate {
    var onChange: (() -> Void)?
    private var window: NSWindow?
    private var onboarding = false
    private let picker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let providerDetail = NSTextField(wrappingLabelWithString: "")
    private let connectionDetail = NSTextField(wrappingLabelWithString: "")
    private let keyField = NSTextField()
    private let workspaceLabel = NSTextField(labelWithString: "Workspace ID")
    private let workspaceField = NSTextField()
    private let workspaceHelpButton = NSButton(title: "Find workspace ID ↗", target: nil, action: nil)
    private let changeWorkspaceButton = NSButton(title: "Change workspace…", target: nil, action: nil)
    private let pasteKeyButton = NSButton(title: "Paste from clipboard", target: nil, action: nil)
    private let saveKeyButton = NSButton(title: "Save key", target: nil, action: nil)
    private let removeKeyButton = NSButton(title: "Remove key", target: nil, action: nil)
    private let getKeyButton = NSButton(title: "Get a key (choose Default workspace) ↗", target: nil, action: nil)
    private let keyStatus = NSTextField(wrappingLabelWithString: "")
    private let keyInstructions = NSTextField(wrappingLabelWithString: "")
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private let heading = NSTextField(labelWithString: "")
    private let intro = NSTextField(wrappingLabelWithString: "")
    private let keyVerifier = ClaudeKeyVerifier()
    private var keyCheckGeneration = 0
    private var workspaceRequired = false
    private var pendingKeyForVerification: String?

    func show(onboarding: Bool = false) {
        self.onboarding = onboarding
        if window == nil { makeWindow() }
        window?.title = onboarding ? "Choose a summarizer" : "Note Ferry Settings"
        heading.stringValue = onboarding ? "Choose a summarizer" : "Settings"
        intro.stringValue = onboarding
            ? "Choose how Note Ferry summarizes. You can change this later."
            : ""
        intro.isHidden = !onboarding
        keyCheckGeneration += 1
        workspaceRequired = ProviderSettings.shared.claudeNeedsWorkspaceID
        pendingKeyForVerification = nil
        keyField.stringValue = ""
        workspaceField.stringValue = ProviderSettings.shared.claudeWorkspaceID ?? ""
        showFeedback("")
        picker.selectItem(withTag: SummaryProvider.allCases.firstIndex(of: ProviderSettings.shared.defaultProvider) ?? 0)
        refresh()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(picker)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 550, height: 460),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.title = "Note Ferry Settings"
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 25, left: 28, bottom: 24, right: 28)
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            root.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor)
        ])
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        intro.font = .systemFont(ofSize: 13)
        intro.textColor = .secondaryLabelColor
        root.addArrangedSubview(heading)
        root.addArrangedSubview(intro)
        let defaultLabel = NSTextField(labelWithString: "Default summarizer")
        defaultLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        root.addArrangedSubview(defaultLabel)
        for provider in SummaryProvider.allCases {
            picker.addItem(withTitle: provider.displayName)
            picker.lastItem?.tag = SummaryProvider.allCases.firstIndex(of: provider) ?? 0
        }
        picker.target = self
        picker.action = #selector(providerChanged)
        picker.setAccessibilityLabel("Default summarizer")
        root.addArrangedSubview(picker)
        providerDetail.font = .systemFont(ofSize: 12)
        providerDetail.textColor = .secondaryLabelColor
        root.addArrangedSubview(providerDetail)
        let separator = NSBox()
        separator.boxType = .separator
        root.addArrangedSubview(separator)
        connectionDetail.font = .systemFont(ofSize: 12)
        connectionDetail.textColor = .secondaryLabelColor
        root.addArrangedSubview(connectionDetail)
        let keyLabel = NSTextField(labelWithString: "Claude API key")
        keyLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        root.addArrangedSubview(keyLabel)
        keyStatus.font = .systemFont(ofSize: 12, weight: .medium)
        root.addArrangedSubview(keyStatus)
        keyInstructions.font = .systemFont(ofSize: 12)
        keyInstructions.textColor = .secondaryLabelColor
        root.addArrangedSubview(keyInstructions)
        keyInstructions.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56).isActive = true
        keyField.placeholderString = "Paste your Claude API key"
        keyField.setAccessibilityLabel("Claude API key")
        keyField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        keyField.isAutomaticTextCompletionEnabled = false
        keyField.contentType = NSTextContentType(rawValue: "APIKey")
        keyField.target = self
        keyField.action = #selector(saveKey)
        root.addArrangedSubview(keyField)
        keyField.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56).isActive = true
        workspaceLabel.font = .systemFont(ofSize: 12, weight: .medium)
        root.addArrangedSubview(workspaceLabel)
        workspaceField.placeholderString = "wrkspc_…"
        workspaceField.setAccessibilityLabel("Claude workspace ID")
        workspaceField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        workspaceField.isAutomaticTextCompletionEnabled = false
        workspaceField.target = self
        workspaceField.action = #selector(saveKey)
        root.addArrangedSubview(workspaceField)
        workspaceField.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56).isActive = true
        workspaceHelpButton.isBordered = false
        workspaceHelpButton.target = self
        workspaceHelpButton.action = #selector(openClaudeWorkspaces)
        root.addArrangedSubview(workspaceHelpButton)
        changeWorkspaceButton.isBordered = false
        changeWorkspaceButton.target = self
        changeWorkspaceButton.action = #selector(changeWorkspace)
        root.addArrangedSubview(changeWorkspaceButton)
        let keyActions = NSStackView(views: [pasteKeyButton, saveKeyButton])
        keyActions.orientation = .horizontal
        keyActions.spacing = 8
        root.addArrangedSubview(keyActions)
        for button in [pasteKeyButton, saveKeyButton, removeKeyButton, getKeyButton, doneButton] { button.bezelStyle = .rounded; button.target = self }
        getKeyButton.isBordered = false
        removeKeyButton.isBordered = false
        root.addArrangedSubview(removeKeyButton)
        root.addArrangedSubview(getKeyButton)
        pasteKeyButton.action = #selector(pasteKey)
        saveKeyButton.action = #selector(saveKey)
        saveKeyButton.keyEquivalent = "\r"
        removeKeyButton.action = #selector(removeKey)
        getKeyButton.action = #selector(openClaudeConsole)
        let billing = NSTextField(wrappingLabelWithString: "Claude API use is billed by Anthropic. Keys are stored in Mac Keychain.")
        billing.font = .systemFont(ofSize: 11)
        billing.textColor = .secondaryLabelColor
        root.addArrangedSubview(billing)
        feedback.font = .systemFont(ofSize: 12)
        feedback.textColor = .secondaryLabelColor
        feedback.isHidden = true
        root.addArrangedSubview(feedback)
        let flexible = NSView()
        flexible.setContentHuggingPriority(.defaultLow, for: .vertical)
        root.addArrangedSubview(flexible)
        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [footerSpacer, doneButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        root.addArrangedSubview(footer)
        doneButton.action = #selector(done)
        for view in [intro, providerDetail, separator, connectionDetail, billing, feedback, footer] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56).isActive = true
        }
        window = panel
    }

    private func refresh() {
        let chosen = SummaryProvider.allCases[picker.indexOfSelectedItem >= 0 ? picker.indexOfSelectedItem : 0]
        switch chosen {
        case .apple:
            providerDetail.stringValue = LocalModelAvailability.message ?? "On this Mac. Review summaries before using them."
        case .codex:
            providerDetail.stringValue = "Uses your Codex account. Summaries go to OpenAI."
        case .claude:
            providerDetail.stringValue = "Uses your API key. Summaries go to Anthropic."
        }
        connectionDetail.isHidden = chosen != .codex || CodexRunner.executable() != nil
        connectionDetail.stringValue = "Codex CLI not found. Install it to use Codex."
        let claude: String
        let hasKey: Bool
        do {
            hasKey = try ProviderSettings.shared.hasClaudeAPIKey()
            if hasKey, let workspaceName = ProviderSettings.shared.claudeWorkspaceName {
                claude = "Key saved · \(workspaceName) workspace"
            } else {
                claude = hasKey ? "Key saved" : "No key saved"
            }
        } catch {
            hasKey = false
            claude = error.localizedDescription
        }
        keyStatus.stringValue = claude
        keyInstructions.stringValue = "Enter the Default workspace ID. Your key is already saved."
        keyInstructions.isHidden = !workspaceRequired || !hasKey
        keyField.isHidden = workspaceRequired && hasKey
        pasteKeyButton.isHidden = workspaceRequired && hasKey
        saveKeyButton.title = workspaceRequired && hasKey ? "Save workspace" : (hasKey ? "Save changes" : "Save key")
        removeKeyButton.isHidden = !hasKey
        getKeyButton.isHidden = hasKey
        let showWorkspace = workspaceRequired
        workspaceLabel.isHidden = !showWorkspace
        workspaceField.isHidden = !showWorkspace
        workspaceHelpButton.isHidden = !showWorkspace
        changeWorkspaceButton.title = ProviderSettings.shared.claudeWorkspaceID == nil ? "Add workspace…" : "Change workspace…"
        changeWorkspaceButton.isHidden = showWorkspace || !hasKey
        window?.setContentSize(NSSize(width: 550, height: showWorkspace ? 565 : 460))
    }

    @objc private func providerChanged() {
        let index = picker.indexOfSelectedItem
        guard SummaryProvider.allCases.indices.contains(index) else { return }
        ProviderSettings.shared.defaultProvider = SummaryProvider.allCases[index]
        showFeedback("")
        refresh()
        onChange?()
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
                try ProviderSettings.shared.saveClaudeAPIKey(enteredKey)
                if workspaceRequired { ProviderSettings.shared.claudeNeedsWorkspaceID = true }
                pendingKeyForVerification = keyForVerification
            } else {
                keyForVerification = pendingKeyForVerification
                guard try ProviderSettings.shared.hasClaudeAPIKey() else {
                    throw AppError.message("Paste a Claude API key to continue.")
                }
                guard workspaceRequired else {
                    throw AppError.message("Paste a new key to replace the saved one.")
                }
            }
            keyCheckGeneration += 1
            keyField.stringValue = ""
            refresh()
            onChange?()
            checkSavedKey(key: keyForVerification, workspaceID: candidateWorkspaceID,
                          savedMessage: replacingKey ? "Saved in Keychain." : nil)
        } catch { showFeedback(error.localizedDescription, isError: true) }
    }

    private func checkSavedKey(key suppliedKey: String? = nil, workspaceID candidateWorkspaceID: String? = nil,
                               savedMessage: String? = nil) {
        do {
            guard let key = try suppliedKey ?? ProviderSettings.shared.loadClaudeAPIKey() else {
                showFeedback("Save a Claude API key first.", isError: true)
                refresh()
                return
            }
            let workspaceID = candidateWorkspaceID ?? ProviderSettings.shared.claudeWorkspaceID
            keyCheckGeneration += 1
            let generation = keyCheckGeneration
            showFeedback((savedMessage.map { "\($0) " } ?? "") + "Checking with Anthropic…")
            keyVerifier.verify(key, workspaceID: workspaceID) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self, self.keyCheckGeneration == generation else { return }
                    switch result {
                    case .success(let verification):
                        if case .defaultWorkspace(let id) = verification {
                            do {
                                try ProviderSettings.shared.saveClaudeWorkspaceID(id, name: "Default")
                                self.workspaceField.stringValue = id
                                self.workspaceRequired = false
                                ProviderSettings.shared.claudeNeedsWorkspaceID = false
                                self.pendingKeyForVerification = nil
                                self.refresh()
                                self.showFeedback("Connected to Default workspace.")
                            } catch {
                                self.showFeedback(error.localizedDescription, isError: true)
                            }
                        } else {
                            do {
                                if let candidateWorkspaceID {
                                    try ProviderSettings.shared.saveClaudeWorkspaceID(candidateWorkspaceID)
                                }
                                self.workspaceRequired = false
                                ProviderSettings.shared.claudeNeedsWorkspaceID = false
                                self.pendingKeyForVerification = nil
                                self.refresh()
                                self.showFeedback("Connected.")
                            } catch {
                                self.showFeedback(error.localizedDescription, isError: true)
                            }
                        }
                    case .failure(let error):
                        if let verificationError = error as? ClaudeKeyVerificationError,
                           case .workspaceRequired = verificationError {
                            self.workspaceRequired = true
                            ProviderSettings.shared.claudeNeedsWorkspaceID = true
                            self.refresh()
                            self.window?.makeFirstResponder(self.workspaceField)
                            self.showFeedback("")
                            return
                        }
                        self.showFeedback(error.localizedDescription, isError: true)
                    }
                }
            }
        } catch { showFeedback(error.localizedDescription, isError: true) }
    }

    @objc private func removeKey() {
        do {
            try ProviderSettings.shared.deleteClaudeAPIKey()
            keyCheckGeneration += 1
            keyField.stringValue = ""
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
        if ProviderSettings.shared.claudeWorkspaceID == nil {
            ProviderSettings.shared.claudeNeedsWorkspaceID = true
        }
        refresh()
        window?.makeFirstResponder(workspaceField)
    }

    @objc private func done() {
        keyCheckGeneration += 1
        keyField.stringValue = ""
        pendingKeyForVerification = nil
        ProviderSettings.shared.hasCompletedOnboarding = true
        window?.orderOut(nil)
        onChange?()
    }

    func windowWillClose(_ notification: Notification) {
        keyCheckGeneration += 1
        keyField.stringValue = ""
        pendingKeyForVerification = nil
    }

    private func showFeedback(_ message: String, isError: Bool = false) {
        feedback.stringValue = message
        feedback.isHidden = message.isEmpty
        feedback.textColor = isError ? .systemRed : .secondaryLabelColor
    }
}
