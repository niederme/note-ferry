import AppKit

enum AppWindowSizing {
    static func contentSize(preferred: NSSize, visibleFrame: NSRect, styleMask: NSWindow.StyleMask) -> NSSize {
        let available = NSWindow.contentRect(forFrameRect: visibleFrame.insetBy(dx: 24, dy: 24), styleMask: styleMask)
        return NSSize(width: min(preferred.width, max(1, available.width)),
                      height: min(preferred.height, max(1, available.height)))
    }
}

private final class InterviewPanel: NSPanel {
    weak var primaryButton: NSButton?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // AppKit clears a default button's Return equivalent while a text view is editing.
        // Keep an explicit shortcut without intercepting ordinary multiline Return.
        if event.keyCode == 36,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command],
           let primaryButton, primaryButton.isEnabled {
            primaryButton.performClick(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class InterviewClipView: NSClipView {
    override var isFlipped: Bool { true }
}
private final class InterviewStackView: NSStackView {
    override var isFlipped: Bool { true }
}

/// A session-only sheet. No clipboard or preference writes happen during the interview.
final class InterviewWindow: NSObject, NSWindowDelegate {
    let source: String
    let context: String
    let provider: SummaryProvider
    let model: String?
    let codexExecutable: URL?
    let apiKey: String?
    let workspaceID: String?
    let resources: URL
    var onFinish: (([Clarification], InterviewUsage) -> Void)?
    var onCancel: (() -> Void)?
    var onPresent: (() -> Void)?
    var onInitialFailure: ((Error) -> Void)?
    private weak var parent: NSWindow?
    private var presented = false
    private(set) var session = InterviewSession()
    private(set) var usage = InterviewUsage()
    private let panel = InterviewPanel(contentRect: NSRect(x: 0, y: 0, width: 840, height: 760), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    private let heading = NSTextField(labelWithString: "Clarify before summarizing")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let content = InterviewStackView()
    private let scroll = NSScrollView()
    private let nextButton = NSButton(title: "Continue interview", target: nil, action: nil)
    private let finishButton = NSButton(title: "Skip interview", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private var answerFields: [NSTextView] = []
    private var busy = false
    private var closed = false
    private var generation = 0
    private var codex: CodexRunner?
    private var claude: ClaudeRunner?
    private var local: Task<Void, Never>?

    init(source: String, context: String, provider: SummaryProvider, model: String?, apiKey: String?, workspaceID: String?, resources: URL, codexExecutable: URL? = nil) {
        self.codexExecutable = codexExecutable
        self.source = source; self.context = context; self.provider = provider; self.model = model
        self.apiKey = apiKey; self.workspaceID = workspaceID; self.resources = resources
        super.init()
    }

    func start(on parent: NSWindow) {
        guard self.parent == nil, !closed else { return }
        self.parent = parent
        next()
    }

    private func makeWindow() {
        panel.isReleasedWhenClosed = false
        panel.title = "Clarification interview"
        panel.delegate = self
        if let screen = parent?.screen ?? NSScreen.main {
            let preferred = NSSize(width: min(840, (parent?.frame.width ?? 872) - 32), height: 760)
            panel.setContentSize(AppWindowSizing.contentSize(preferred: preferred, visibleFrame: screen.visibleFrame, styleMask: panel.styleMask))
        }
        panel.contentMinSize = NSSize(width: min(620, panel.contentLayoutRect.width), height: min(540, panel.contentLayoutRect.height))
        let root = NSStackView()
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 20, right: 24)
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            root.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor)
        ])
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        root.addArrangedSubview(heading)
        detail.font = .systemFont(ofSize: 13); detail.textColor = .secondaryLabelColor
        root.addArrangedSubview(detail)
        content.orientation = .vertical; content.alignment = .leading; content.spacing = 20
        content.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 12, right: 12)
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.contentView = InterviewClipView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = false; scroll.scrollerStyle = .legacy
        scroll.borderType = .noBorder
        scroll.drawsBackground = false; scroll.documentView = content
        content.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        root.addArrangedSubview(scroll)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor
        root.addArrangedSubview(status)
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [cancelButton, spinner, spacer, finishButton, nextButton])
        footer.orientation = .horizontal; footer.spacing = 10
        root.addArrangedSubview(footer)
        for view in [heading, detail, scroll, status, footer] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -48).isActive = true
        }
        for button in [nextButton, finishButton, cancelButton] { button.target = self; button.bezelStyle = .rounded }
        nextButton.action = #selector(next)
        panel.defaultButtonCell = nextButton.cell as? NSButtonCell
        panel.primaryButton = nextButton
        nextButton.bezelColor = .controlAccentColor
        nextButton.contentTintColor = .white
        nextButton.keyEquivalent = "\r"
        nextButton.keyEquivalentModifierMask = [.command]
        nextButton.toolTip = "Submit your answers and continue (⌘Return)."
        finishButton.action = #selector(finish)
        cancelButton.action = #selector(cancel)
        cancelButton.keyEquivalent = "\u{1b}"
    }

    private func presentQuestions() {
        if !presented { makeWindow() }
        renderQuestions()
        if !presented, let parent {
            presented = true
            parent.beginSheet(panel)
            onPresent?()
            if let first = answerFields.first { panel.makeFirstResponder(first) }
        }
    }

    @discardableResult
    private func addLabel(_ text: String, bold: Bool = false, secondary: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 14, weight: bold ? .semibold : .regular)
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        label.isSelectable = true
        content.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -12).isActive = true
        return label
    }

    private func clearContent() {
        for view in content.arrangedSubviews { content.removeArrangedSubview(view); view.removeFromSuperview() }
        answerFields = []
    }

    private func renderQuestions() {
        clearContent()
        heading.stringValue = "Let’s clarify a few things"
        detail.stringValue = "Round \(session.round) · Answer what you can. Correct any mistaken assumptions. Blank answers stay uncertain."
        for (index, item) in session.pending.enumerated() {
            let questionLabel = addLabel("\(index + 1). \(item.question.question)", bold: true)
            content.setCustomSpacing(item.question.excerpt.isEmpty ? 10 : 6, after: questionLabel)
            if !item.question.excerpt.isEmpty {
                let excerptLabel = addLabel("“\(item.question.excerpt)”", secondary: true)
                content.setCustomSpacing(12, after: excerptLabel)
            }
            if !item.question.options.isEmpty {
                let picker = NSPopUpButton(frame: .zero, pullsDown: false)
                picker.addItem(withTitle: "Choose a suggestion, or write below")
                for option in item.question.options { picker.addItem(withTitle: option) }
                picker.tag = index; picker.target = self; picker.action = #selector(optionChosen(_:))
                picker.setAccessibilityLabel("Suggested answers for question \(index + 1)")
                content.addArrangedSubview(picker)
                picker.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -12).isActive = true
            }
            let field = NSTextView(usingTextLayoutManager: false)
            field.isRichText = false; field.font = .systemFont(ofSize: 13)
            field.textContainerInset = NSSize(width: 8, height: 8)
            field.isVerticallyResizable = true; field.isHorizontallyResizable = false
            field.autoresizingMask = [.width]; field.textContainer?.widthTracksTextView = true
            field.allowsUndo = true
            field.setAccessibilityLabel("Your answer to question \(index + 1): \(item.question.question)")
            let fieldScroll = NSScrollView()
            fieldScroll.borderType = .bezelBorder; fieldScroll.hasVerticalScroller = true
            fieldScroll.autohidesScrollers = false; fieldScroll.scrollerStyle = .legacy
            fieldScroll.documentView = field
            content.addArrangedSubview(fieldScroll)
            fieldScroll.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -12).isActive = true
            fieldScroll.heightAnchor.constraint(equalToConstant: 76).isActive = true
            answerFields.append(field)
        }
        nextButton.title = "Continue interview"
        finishButton.title = "Finish & summarize"
        status.stringValue = "Answers stay in this session and go only to \(provider.displayName). Continue may make another model request."
        panel.contentView?.layoutSubtreeIfNeeded()
        content.layoutSubtreeIfNeeded()
        updateScrollHint()
        content.scroll(.zero)
        if let first = answerFields.first { panel.makeFirstResponder(first) }
    }

    private func updateScrollHint() {
        guard !session.pending.isEmpty else { return }
        detail.stringValue = "Round \(session.round) · Answer what you can. Correct any mistaken assumptions. Blank answers stay uncertain."
        if content.fittingSize.height > scroll.contentSize.height {
            detail.stringValue += " Scroll down for more questions."
        }
    }

    func windowDidResize(_ notification: Notification) {
        panel.contentView?.layoutSubtreeIfNeeded()
        updateScrollHint()
    }

    @objc private func optionChosen(_ picker: NSPopUpButton) {
        guard answerFields.indices.contains(picker.tag), picker.indexOfSelectedItem > 0 else { return }
        let field = answerFields[picker.tag]
        field.string = picker.titleOfSelectedItem ?? ""
        panel.makeFirstResponder(field)
    }

    private func collectAnswers() throws {
        guard !session.pending.isEmpty else { return }
        try session.answer(answerFields.map(\.string), provider: provider)
        for field in answerFields { field.isEditable = false }
        answerFields = []
    }

    @objc private func next() {
        guard !busy, !closed else { return }
        do { try collectAnswers() } catch { status.stringValue = error.localizedDescription; return }
        busy = true; nextButton.isEnabled = false
        spinner.startAnimation(nil)
        if presented {
            status.stringValue = ""
            finishButton.title = "Finish & summarize"
        }
        generation += 1
        let requestGeneration = generation
        let history = session.history
        if provider == .apple {
            if #available(macOS 26.0, *) {
                local = Task { @MainActor [weak self] in
                    guard let self else { return }
                    var tokens: TokenUsage?
                    do {
                        let batch = try await LocalSummarizer.interview(source, context: context, history: history, onUsage: { tokens = $0 })
                        received(.success(batch), tokens: tokens, generation: requestGeneration)
                    } catch { received(.failure(error), tokens: tokens, generation: requestGeneration) }
                }
            } else { received(.failure(AppError.message("Apple Intelligence requires macOS 26 or later.")), tokens: nil, generation: requestGeneration) }
        } else {
            let codexWorker = provider == .codex ? CodexRunner() : nil
            let claudeWorker = provider == .claude ? ClaudeRunner() : nil
            codex = codexWorker; claude = claudeWorker
            let source = source, context = context, resources = resources, model = model, apiKey = apiKey, workspaceID = workspaceID, executable = codexExecutable
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var tokens: TokenUsage?
                let result = Result<InterviewBatch, Error> {
                    if let codexWorker {
                        return try codexWorker.interview(transcript: source, context: context, history: history, resources: resources, executable: executable, model: model, onUsage: { tokens = $0 })
                    }
                    guard let claudeWorker, let apiKey else { throw AppError.message("Add your Claude API key in Settings.") }
                    return try claudeWorker.interview(transcript: source, context: context, history: history, resources: resources, apiKey: apiKey, workspaceID: workspaceID, onUsage: { tokens = $0 })
                }
                let reported = tokens
                DispatchQueue.main.async { self?.received(result, tokens: reported, generation: requestGeneration) }
            }
        }
    }

    private func received(_ result: Result<InterviewBatch, Error>, tokens: TokenUsage?, generation: Int) {
        guard !closed, generation == self.generation else { return }
        busy = false; codex = nil; claude = nil; local = nil
        spinner.stopAnimation(nil); nextButton.isEnabled = true
        usage.record(tokens)
        do {
            let batch = try result.get()
            try session.receive(batch, source: source)
            if session.pending.isEmpty { finish(); return }
            presentQuestions()
        } catch {
            if !presented {
                close()
                onInitialFailure?(error)
                return
            }
            clearContent()
            addLabel("The interview couldn’t continue", bold: true)
            addLabel(error.localizedDescription)
            addLabel("Your original text and any answers already submitted are still available. Retry, or continue to the summary.")
            status.stringValue = "Your clipboard is unchanged."
            nextButton.title = "Retry questions"
            finishButton.title = "Continue to summary"
        }
    }

    @objc private func finish() {
        guard !closed else { return }
        do { try collectAnswers() } catch { status.stringValue = error.localizedDescription; return }
        if busy { usage.record(nil) } // Cancelled requests may still have consumed tokens.
        close()
        onFinish?(session.history, usage)
    }
    @objc func cancel() {
        guard !closed else { return }
        close()
        onCancel?()
    }
    func stop() {
        guard !closed else { return }
        close()
    }
    private func close() {
        closed = true; generation += 1
        codex?.cancel(); claude?.cancel(); local?.cancel()
        panel.sheetParent?.endSheet(panel)
        panel.orderOut(nil)
    }
}
