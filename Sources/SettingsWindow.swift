import AppKit

final class ProviderSettingsWindow: NSObject, NSWindowDelegate {
    var onChange: (() -> Void)?
    private var window: NSWindow?
    private var onboarding = false
    private let picker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let providerDetail = NSTextField(wrappingLabelWithString: "")
    private let connectionDetail = NSTextField(wrappingLabelWithString: "")
    private let keyField = NSSecureTextField()
    private let saveKeyButton = NSButton(title: "Save key", target: nil, action: nil)
    private let removeKeyButton = NSButton(title: "Remove key", target: nil, action: nil)
    private let getKeyButton = NSButton(title: "Get an API key…", target: nil, action: nil)
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private let heading = NSTextField(labelWithString: "")
    private let intro = NSTextField(wrappingLabelWithString: "")

    func show(onboarding: Bool = false) {
        self.onboarding = onboarding
        if window == nil { makeWindow() }
        window?.title = onboarding ? "Choose a summarizer" : "Note Ferry Settings"
        heading.stringValue = onboarding ? "Choose a summarizer" : "Summarizer settings"
        intro.stringValue = onboarding
            ? (LocalModelAvailability.message == nil
                ? "Apple Intelligence is selected to start. You can choose a different default now or change it any time. Formatting text never uses AI."
                : "Apple Intelligence is not available on this Mac. Choose Codex or Claude to summarize; Format only remains available.")
            : "Choose the default for Summarize & format. You can switch providers for one transcript in the main window."
        feedback.stringValue = ""
        picker.selectItem(withTag: SummaryProvider.allCases.firstIndex(of: ProviderSettings.shared.defaultProvider) ?? 0)
        refresh()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 550, height: 490),
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
        let connectionHeading = NSTextField(labelWithString: "Connections")
        connectionHeading.font = .systemFont(ofSize: 14, weight: .semibold)
        root.addArrangedSubview(connectionHeading)
        connectionDetail.font = .systemFont(ofSize: 12)
        connectionDetail.textColor = .secondaryLabelColor
        root.addArrangedSubview(connectionDetail)
        let keyLabel = NSTextField(labelWithString: "Claude API key")
        keyLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        root.addArrangedSubview(keyLabel)
        keyField.placeholderString = "Paste your Anthropic API key"
        keyField.setAccessibilityLabel("Claude API key")
        root.addArrangedSubview(keyField)
        keyField.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56).isActive = true
        let keyActions = NSStackView(views: [saveKeyButton, removeKeyButton, getKeyButton])
        keyActions.orientation = .horizontal
        keyActions.spacing = 8
        root.addArrangedSubview(keyActions)
        for button in [saveKeyButton, removeKeyButton, getKeyButton, doneButton] { button.bezelStyle = .rounded; button.target = self }
        saveKeyButton.action = #selector(saveKey)
        removeKeyButton.action = #selector(removeKey)
        getKeyButton.action = #selector(openClaudeConsole)
        let billing = NSTextField(wrappingLabelWithString: "Claude API use is billed separately by Anthropic. Your key is stored in this Mac’s Keychain. Note Ferry never reads Claude Code’s login.")
        billing.font = .systemFont(ofSize: 11)
        billing.textColor = .secondaryLabelColor
        root.addArrangedSubview(billing)
        feedback.font = .systemFont(ofSize: 12)
        feedback.textColor = .secondaryLabelColor
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
        doneButton.keyEquivalent = "\r"
        for view in [intro, providerDetail, separator, connectionDetail, billing, feedback, footer] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56).isActive = true
        }
        window = panel
    }

    private func refresh() {
        let chosen = SummaryProvider.allCases[picker.indexOfSelectedItem >= 0 ? picker.indexOfSelectedItem : 0]
        switch chosen {
        case .apple:
            providerDetail.stringValue = "On-device and experimental. Review names, attribution, and action items carefully. " + (LocalModelAvailability.message ?? "Available on this Mac.")
        case .codex:
            providerDetail.stringValue = "Uses your Codex account through the installed Codex CLI. Your text goes to OpenAI when you summarize."
        case .claude:
            providerDetail.stringValue = "Uses your own Anthropic API key. Your text goes to Anthropic when you summarize; API usage is billed separately from a Claude subscription."
        }
        let codex = CodexRunner.executable() == nil ? "Codex CLI was not found. Install it and run ‘codex login’ in Terminal." : "Codex CLI is installed. If prompted to sign in, run ‘codex login’ in Terminal."
        let claude: String
        do {
            claude = try ProviderSettings.shared.loadClaudeAPIKey() == nil ? "Claude API key not saved." : "Claude API key saved in Keychain."
        } catch { claude = "Claude Keychain status unavailable: \(error.localizedDescription)" }
        connectionDetail.stringValue = codex + "\n" + claude
        removeKeyButton.isEnabled = (try? ProviderSettings.shared.loadClaudeAPIKey()) != nil
    }

    @objc private func providerChanged() {
        let index = picker.indexOfSelectedItem
        guard SummaryProvider.allCases.indices.contains(index) else { return }
        ProviderSettings.shared.defaultProvider = SummaryProvider.allCases[index]
        refresh()
        onChange?()
    }

    @objc private func saveKey() {
        do {
            try ProviderSettings.shared.saveClaudeAPIKey(keyField.stringValue)
            keyField.stringValue = ""
            feedback.stringValue = "Claude API key saved."
            refresh()
            onChange?()
        } catch { feedback.stringValue = error.localizedDescription }
    }

    @objc private func removeKey() {
        do {
            try ProviderSettings.shared.deleteClaudeAPIKey()
            keyField.stringValue = ""
            feedback.stringValue = "Claude API key removed."
            refresh()
            onChange?()
        } catch { feedback.stringValue = error.localizedDescription }
    }

    @objc private func openClaudeConsole() {
        guard let url = URL(string: "https://platform.claude.com/settings/keys") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func done() {
        ProviderSettings.shared.hasCompletedOnboarding = true
        window?.orderOut(nil)
        onChange?()
    }
}
