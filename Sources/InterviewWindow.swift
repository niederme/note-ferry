import AppKit

/// A quiet editing surface. The text system still owns selection, focus and scrolling.
final class EditorScrollView: NSScrollView {
    var showsEditingBackground = true { didSet { updateSurface() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        borderType = .noBorder
        hasVerticalScroller = true
        autohidesScrollers = true
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        updateSurface()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSurface()
    }
    private func updateSurface() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            backgroundColor = showsEditingBackground
                ? (NSColor.textBackgroundColor.blended(withFraction: 0.035, of: .labelColor) ?? .textBackgroundColor)
                : .textBackgroundColor
            drawsBackground = true
            contentView.backgroundColor = backgroundColor
            (documentView as? NSTextView)?.drawsBackground = false
        }
    }
}

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

private final class InterviewAnswerTextView: NSTextView {
    var moveFocus: ((Bool) -> Void)?

    override func insertTab(_ sender: Any?) { moveFocus?(true) }
    override func insertBacktab(_ sender: Any?) { moveFocus?(false) }
}

private final class InterviewChoiceButton: NSButton {
    var moveFocus: ((Bool) -> Void)?
    var moveChoice: ((Int) -> Void)?
    override var acceptsFirstResponder: Bool { isEnabled }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 {
            moveFocus?(!event.modifierFlags.contains(.shift))
            return
        }
        if [123, 126].contains(event.keyCode) { moveChoice?(-1); return }
        if [124, 125].contains(event.keyCode) { moveChoice?(1); return }
        super.keyDown(with: event)
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
    private let historyButton = NSButton(title: "Answers…", target: nil, action: nil)
    private let historyPopover = NSPopover()
    private let spinner = NSProgressIndicator()
    private var answerFields: [NSTextView] = []
    private var choiceButtons: [[NSButton]] = []
    private var choiceHeights: [[NSLayoutConstraint]] = []
    private var selectedOptions: [Int?] = []
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
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false; scroll.documentView = content
        content.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        root.addArrangedSubview(scroll)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor
        root.addArrangedSubview(status)
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [cancelButton, historyButton, spinner, spacer, finishButton, nextButton])
        footer.orientation = .horizontal; footer.spacing = 10
        root.addArrangedSubview(footer)
        for view in [heading, detail, scroll, status, footer] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -48).isActive = true
        }
        for button in [nextButton, finishButton, cancelButton] { button.target = self; button.bezelStyle = .rounded }
        nextButton.action = #selector(next)
        panel.defaultButtonCell = nextButton.cell as? NSButtonCell
        panel.primaryButton = nextButton
        nextButton.keyEquivalent = "\r"
        nextButton.keyEquivalentModifierMask = [.command]
        nextButton.toolTip = "Submit your answers and continue (⌘Return)."
        finishButton.action = #selector(finish)
        cancelButton.action = #selector(cancel)
        cancelButton.keyEquivalent = "\u{1b}"
        historyButton.target = self; historyButton.action = #selector(reviewAnswers)
        historyButton.bezelStyle = .rounded
        historyButton.toolTip = "Review answers already submitted in this interview"
        historyPopover.behavior = .transient
    }

    private func presentQuestions() {
        if !presented { makeWindow() }
        renderQuestions()
        if !presented, let parent {
            presented = true
            parent.beginSheet(panel)
            onPresent?()
            focusQuestion(0)
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
        choiceButtons = []; choiceHeights = []; selectedOptions = []
    }

    private func renderQuestions() {
        clearContent()
        historyButton.isHidden = session.history.isEmpty
        heading.stringValue = "Let’s clarify a few things"
        detail.stringValue = "Round \(session.round) · Answer what you can. Correct any mistaken assumptions. Blank answers stay uncertain."
        for (index, item) in session.pending.enumerated() {
            let questionLabel = addLabel("\(index + 1). \(item.question.question)", bold: true)
            content.setCustomSpacing(item.question.excerpt.isEmpty ? 10 : 6, after: questionLabel)
            if !item.question.excerpt.isEmpty {
                let excerptLabel = addLabel("“\(item.question.excerpt)”", secondary: true)
                content.setCustomSpacing(12, after: excerptLabel)
            }
            var buttons: [NSButton] = []
            var heights: [NSLayoutConstraint] = []
            if !item.question.options.isEmpty {
                let choices = NSStackView()
                choices.orientation = .vertical; choices.alignment = .leading; choices.spacing = 6
                choices.setAccessibilityLabel("Suggested answers for question \(index + 1)")
                content.addArrangedSubview(choices)
                choices.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -12).isActive = true
                content.setCustomSpacing(10, after: choices)
                for title in item.question.options + ["Something else"] {
                    let button = InterviewChoiceButton(title: title, target: self, action: #selector(optionChosen(_:)))
                    button.setButtonType(.radio)
                    button.font = .systemFont(ofSize: 14)
                    button.alignment = .left
                    button.cell?.wraps = true
                    button.cell?.isScrollable = false
                    button.cell?.lineBreakMode = .byWordWrapping
                    button.state = .off
                    button.moveFocus = { [weak self] forward in
                        guard let self, !self.busy else { return }
                        if forward, self.selectedOptions[index] == item.question.options.count {
                            self.focusQuestion(index)
                        } else { self.focusQuestion(index + (forward ? 1 : -1)) }
                    }
                    let optionIndex = buttons.count
                    button.moveChoice = { [weak self] direction in
                        guard let self, !self.busy else { return }
                        let group = self.choiceButtons[index]
                        group[(optionIndex + direction + group.count) % group.count].performClick(nil)
                    }
                    choices.addArrangedSubview(button)
                    button.widthAnchor.constraint(equalTo: choices.widthAnchor).isActive = true
                    let height = button.heightAnchor.constraint(equalToConstant: 22)
                    height.isActive = true
                    buttons.append(button); heights.append(height)
                }
            }
            choiceButtons.append(buttons); choiceHeights.append(heights); selectedOptions.append(nil)
            let field = InterviewAnswerTextView(usingTextLayoutManager: false)
            field.moveFocus = { [weak self, weak field] forward in
                guard let self, let field else { return }
                self.moveAnswerFocus(from: field, forward: forward)
            }
            field.isRichText = false; field.font = .systemFont(ofSize: 13)
            field.textContainerInset = NSSize(width: 8, height: 8)
            field.isVerticallyResizable = true; field.isHorizontallyResizable = false
            field.autoresizingMask = [.width]; field.textContainer?.widthTracksTextView = true
            field.allowsUndo = true
            field.setAccessibilityLabel("Your answer to question \(index + 1): \(item.question.question)")
            let fieldScroll = EditorScrollView()
            field.drawsBackground = false
            fieldScroll.documentView = field
            fieldScroll.isHidden = !item.question.options.isEmpty
            content.addArrangedSubview(fieldScroll)
            fieldScroll.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -12).isActive = true
            fieldScroll.heightAnchor.constraint(equalToConstant: 76).isActive = true
            answerFields.append(field)
        }
        updateKeyLoop()
        nextButton.title = "Continue interview"
        finishButton.title = "Finish & summarize"
        status.stringValue = "Answers stay in this session and go only to \(provider.displayName). Continue may make another model request."
        panel.contentView?.layoutSubtreeIfNeeded()
        layoutChoices()
        content.layoutSubtreeIfNeeded()
        updateScrollHint()
        content.scroll(.zero)
        focusQuestion(0)
    }

    private func moveAnswerFocus(from field: NSTextView, forward: Bool) {
        guard !busy, let index = answerFields.firstIndex(where: { $0 === field }) else { return }
        if !forward, !choiceButtons[index].isEmpty {
            let selected = choiceButtons[index][selectedOptions[index] ?? 0]
            content.scrollToVisible(selected.convert(selected.bounds, to: content))
            panel.makeFirstResponder(selected)
            return
        }
        focusQuestion(index + (forward ? 1 : -1))
    }

    private func focusQuestion(_ index: Int) {
        guard answerFields.indices.contains(index) else {
            panel.makeFirstResponder(index < 0 ? cancelButton : nextButton)
            return
        }
        let field = answerFields[index]
        let target: NSView
        if field.enclosingScrollView?.isHidden == false {
            target = field
        } else {
            target = choiceButtons[index][selectedOptions[index] ?? 0]
        }
        let visibleTarget = (target as? NSTextView)?.enclosingScrollView ?? target
        content.scrollToVisible(visibleTarget.convert(visibleTarget.bounds, to: content))
        panel.makeFirstResponder(target)
    }

    private func updateKeyLoop() {
        var controls: [NSView] = []
        for (index, field) in answerFields.enumerated() {
            controls += choiceButtons[index]
            if field.enclosingScrollView?.isHidden == false { controls.append(field) }
        }
        controls += [nextButton, finishButton, cancelButton]
        if !historyButton.isHidden { controls.append(historyButton) }
        for (index, control) in controls.enumerated() {
            control.nextKeyView = controls[(index + 1) % controls.count]
        }
    }

    private func layoutChoices() {
        let width = max(100, content.bounds.width - 36)
        for (buttons, heights) in zip(choiceButtons, choiceHeights) {
            for (button, height) in zip(buttons, heights) {
                let title = NSAttributedString(string: button.title, attributes: [.font: button.font!])
                let bounds = title.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
                height.constant = max(22, ceil(bounds.height) + 4)
            }
        }
        panel.contentView?.layoutSubtreeIfNeeded()
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
        layoutChoices()
        updateScrollHint()
    }

    @objc private func optionChosen(_ sender: NSButton) {
        guard !busy, let index = choiceButtons.firstIndex(where: { $0.contains(where: { $0 === sender }) }),
              session.pending.indices.contains(index),
              let option = choiceButtons[index].firstIndex(where: { $0 === sender }) else { return }
        selectedOptions[index] = option
        for button in choiceButtons[index] { button.state = button === sender ? .on : .off }
        let custom = option == session.pending[index].question.options.count
        answerFields[index].enclosingScrollView?.isHidden = !custom
        updateKeyLoop()
        panel.contentView?.layoutSubtreeIfNeeded()
        updateScrollHint()
        focusQuestion(index)
    }

    private func collectAnswers() throws {
        guard !session.pending.isEmpty else { return }
        let answers = session.pending.enumerated().map { index, item -> String in
            guard !item.question.options.isEmpty else { return answerFields[index].string }
            guard let selected = selectedOptions[index] else { return "" }
            return selected < item.question.options.count ? item.question.options[selected] : answerFields[index].string
        }
        try session.answer(answers, provider: provider)
        historyButton.isHidden = session.history.isEmpty
        for field in answerFields { field.isEditable = false }
        for button in choiceButtons.flatMap({ $0 }) { button.isEnabled = false }
        answerFields = []
    }

    @objc private func next() {
        guard !busy, !closed else { return }
        do { try collectAnswers() } catch { status.stringValue = error.localizedDescription; return }
        busy = true; nextButton.isEnabled = false
        spinner.startAnimation(nil)
        if presented {
            status.stringValue = "Checking for follow-up questions…"
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
            updateKeyLoop()
        }
    }

    @objc func finish() {
        guard !closed else { return }
        do { try collectAnswers() } catch { status.stringValue = error.localizedDescription; return }
        if busy { usage.record(nil) } // Cancelled requests may still have consumed tokens.
        close()
        onFinish?(session.history, usage)
    }
    @objc private func reviewAnswers() {
        if historyPopover.isShown { historyPopover.close(); return }
        let text = NSTextView()
        text.isEditable = false; text.isSelectable = true; text.isRichText = false
        text.font = .systemFont(ofSize: 13)
        text.textContainerInset = NSSize(width: 14, height: 14)
        text.string = session.history.enumerated().map { index, answer in
            "\(index + 1). \(answer.question.question)\n\(answer.answer.isEmpty ? "Unanswered" : answer.answer)"
        }.joined(separator: "\n\n")
        text.setAccessibilityLabel("Submitted clarification answers, read only")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 280))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        text.isVerticallyResizable = true; text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text
        let controller = NSViewController(); controller.view = scroll
        historyPopover.contentViewController = controller
        historyPopover.show(relativeTo: historyButton.bounds, of: historyButton, preferredEdge: .maxY)
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
        historyPopover.close()
        codex?.cancel(); claude?.cancel(); local?.cancel()
        panel.sheetParent?.endSheet(panel)
        panel.orderOut(nil)
    }
}
