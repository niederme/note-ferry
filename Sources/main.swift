import AppKit

let arguments = CommandLine.arguments
if arguments.count == 4 && arguments[1] == "--summarize-file" {
    do {
        let source = try String(contentsOfFile: arguments[2], encoding: .utf8)
        let summary = try CodexRunner().run(transcript: source, resources: Bundle.main.resourceURL!)
        let base = URL(fileURLWithPath: arguments[3])
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(summary).write(to: base.appendingPathComponent("summary.json"), options: .atomic)
        let rendered = NoteRenderer.render(summary)
        try NoteRenderer.rtf(rendered).write(to: base.appendingPathComponent("summary.rtf"), options: .atomic)
        try NoteRenderer.plainText(rendered).write(to: base.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
        print("Summary, rich text, and plain text saved. Clipboard untouched.")
        exit(0)
    } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
}

final class TranscriptTextView: NSTextView {
    var allowsTranscriptPaste = true
    var prepareForPaste: (() -> Void)?
    override func paste(_ sender: Any?) {
        guard allowsTranscriptPaste else { return }
        prepareForPaste?()
        super.pasteAsPlainText(sender)
    }
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(NSText.paste(_:)) {
            return allowsTranscriptPaste && NSPasteboard.general.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.string.rawValue])
        }
        return super.validateUserInterfaceItem(item)
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            ("Paste a transcript here (⌘V)." as NSString).draw(
                at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height),
                withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.placeholderTextColor])
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextViewDelegate {
    enum Mode { case input, processing, result }
    var mode: Mode = .input
    var updatingText = false
    var window: NSWindow!
    let heading = NSTextField(labelWithString: "Summary Notes")
    let detail = NSTextField(wrappingLabelWithString: "")
    let privacy = NSTextField(wrappingLabelWithString: "Uses your Codex account to process the transcript with OpenAI. Formatting happens on your Mac.")
    let preview = TranscriptTextView(usingTextLayoutManager: true)
    let spinner = NSProgressIndicator()
    let progress = NSTextField(labelWithString: "")
    let summarizeButton = NSButton(title: "Summarize", target: nil, action: nil)
    let copyButton = NSButton(title: "Copy summary", target: nil, action: nil)
    let newButton = NSButton(title: "Clear", target: nil, action: nil)
    let restoreButton = NSButton(title: "Restore clipboard", target: nil, action: nil)
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    var runner: CodexRunner?
    var raw: String?
    var snapshot: ClipboardSnapshot?
    var rich: NSAttributedString?
    var lastWrite: Int?
    var jobID: UUID?
    var timer: Timer?
    var started = Date()

    var inputAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.textColor, .paragraphStyle: NSParagraphStyle.default]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        makeMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 790), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Summary Notes"
        window.minSize = NSSize(width: 620, height: 560)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        let root = NSStackView()
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 20
        root.edgeInsets = NSEdgeInsets(top: 25, left: 28, bottom: 22, right: 28)
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor), root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor), root.topAnchor.constraint(equalTo: window.contentView!.topAnchor), root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor)])
        let headerText = NSStackView(views: [heading, detail])
        headerText.orientation = .vertical; headerText.alignment = .leading; headerText.spacing = 6
        let icon = NSImageView()
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            icon.image = NSImage(contentsOf: iconURL)
            NSApp.applicationIconImage = icon.image
        }
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel("Summary Notes app icon")
        icon.widthAnchor.constraint(equalToConstant: 52).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 52).isActive = true
        let header = NSStackView(views: [icon, headerText])
        header.orientation = .horizontal; header.alignment = .centerY; header.spacing = 14
        heading.font = .systemFont(ofSize: 24, weight: .semibold)
        detail.font = .systemFont(ofSize: 13); detail.textColor = .secondaryLabelColor
        root.addArrangedSubview(header)
        headerText.widthAnchor.constraint(equalTo: header.widthAnchor, constant: -66).isActive = true
        detail.widthAnchor.constraint(equalTo: headerText.widthAnchor).isActive = true
        progress.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        progress.textColor = .secondaryLabelColor; progress.isHidden = true
        root.addArrangedSubview(progress)
        spinner.style = .bar; spinner.isIndeterminate = true; spinner.isHidden = true
        root.addArrangedSubview(spinner)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        preview.delegate = self
        preview.prepareForPaste = { [weak self] in
            guard let self, self.mode == .result else { return }
            self.preview.isEditable = true
            self.preview.selectAll(nil)
            self.preview.typingAttributes = self.inputAttributes
        }
        preview.isEditable = true; preview.isSelectable = true; preview.isRichText = true
        preview.allowsUndo = true
        preview.isAutomaticLinkDetectionEnabled = false
        preview.isAutomaticQuoteSubstitutionEnabled = false
        preview.isAutomaticDashSubstitutionEnabled = false
        preview.textContainerInset = NSSize(width: 24, height: 25)
        preview.isVerticallyResizable = true; preview.isHorizontallyResizable = false
        preview.autoresizingMask = [.width]
        preview.textContainer?.widthTracksTextView = true
        preview.textContainer?.containerSize = NSSize(width: 680, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = preview
        root.addArrangedSubview(scroll)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
        privacy.font = .systemFont(ofSize: 11); privacy.textColor = .secondaryLabelColor
        root.addArrangedSubview(privacy)
        let buttons = NSStackView(views: [copyButton, summarizeButton, newButton, restoreButton, cancelButton])
        buttons.orientation = .horizontal; buttons.spacing = 10
        root.addArrangedSubview(buttons)
        for button in [summarizeButton, copyButton, newButton, restoreButton, cancelButton] { button.bezelStyle = .rounded; button.target = self }
        summarizeButton.action = #selector(summarizeInput)
        summarizeButton.toolTip = "Summarize the transcript in this window."
        copyButton.action = #selector(copySummary)
        copyButton.toolTip = "Copy the formatted summary to your clipboard again."
        newButton.action = #selector(newTranscript)
        newButton.toolTip = "Clear this window so you can paste another transcript."
        restoreButton.action = #selector(restoreClipboard)
        cancelButton.action = #selector(cancel); cancelButton.keyEquivalent = "\u{1b}"
        for view in [header, progress, spinner, scroll, privacy] { view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56).isActive = true }
        newTranscript()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let index = arguments.firstIndex(of: "--preview"), arguments.count > index + 1 {
            do {
                let note = try JSONDecoder().decode(Summary.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[index + 1])))
                try note.validate()
                display(note)
                detail.stringValue = "Detailed summaries from your transcripts, formatted for pasting into Apple Notes."
            } catch { showError(error) }
        }
        // Opening, reopening, and clipboard changes never start a model request.
    }

    func makeMenu() {
        let menu = NSMenu(), appItem = NSMenuItem(), appMenu = NSMenu()
        menu.addItem(appItem)
        appMenu.addItem(withTitle: "About Summary Notes", action: #selector(about), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Clear", action: #selector(newTranscript), keyEquivalent: "n").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Summary Notes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""), editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu; menu.addItem(editItem); NSApp.mainMenu = menu
    }
    @objc func about() {
        let alert = NSAlert()
        alert.messageText = "Summary Notes"
        alert.informativeText = "Paste a transcript and choose Summarize. The result is copied automatically for pasting into Apple Notes.\n\nUses your signed-in Codex CLI and account allowance. Source text stays in memory; the model’s temporary result file is removed when processing finishes. Codex session history is disabled.\n\nNo note is created or edited."
        alert.runModal()
    }
    @objc func newTranscript() {
        guard runner == nil else { return }
        updatingText = true
        preview.textStorage?.setAttributedString(NSAttributedString(string: "", attributes: inputAttributes))
        preview.typingAttributes = inputAttributes
        preview.undoManager?.removeAllActions()
        updatingText = false
        raw = nil; rich = nil; snapshot = nil; lastWrite = nil
        showInputControls()
        window?.makeFirstResponder(preview)
    }
    func showInputControls() {
        mode = .input
        preview.isEditable = true; preview.allowsTranscriptPaste = true; preview.needsDisplay = true
        detail.stringValue = "Detailed summaries from your transcripts, formatted for pasting into Apple Notes."
        summarizeButton.isHidden = false; summarizeButton.keyEquivalent = "\r"
        summarizeButton.isEnabled = !preview.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        copyButton.isHidden = true; copyButton.keyEquivalent = ""
        newButton.isHidden = true; restoreButton.isHidden = true; cancelButton.isHidden = true
    }
    func textDidChange(_ notification: Notification) {
        guard !updatingText, mode != .processing else { return }
        if mode == .result {
            updatingText = true
            preview.textStorage?.setAttributes(inputAttributes, range: NSRange(location: 0, length: preview.textStorage?.length ?? 0))
            preview.typingAttributes = inputAttributes
            updatingText = false
            rich = nil
        }
        showInputControls()
    }
    @objc func summarizeInput() {
        guard runner == nil, mode == .input else { return }
        let text = preview.string
        do { try Transcript.validate(text) } catch { showError(error); return }
        snapshot = ClipboardSnapshot(.general)
        raw = text; rich = nil; lastWrite = nil
        let worker = CodexRunner(); runner = worker
        let token = UUID(); jobID = token
        mode = .processing; preview.isEditable = false; preview.allowsTranscriptPaste = false
        started = Date()
        let words = text.split(whereSeparator: \.isWhitespace).count
        detail.stringValue = "Summarizing your transcript with Codex. Your clipboard will update when it’s ready."
        progress.stringValue = "\(words.formatted()) words · 0:00 elapsed"; progress.isHidden = false
        spinner.isHidden = false; spinner.startAnimation(nil)
        summarizeButton.isHidden = true; copyButton.isHidden = true; newButton.isHidden = true; restoreButton.isHidden = true
        cancelButton.isHidden = false; cancelButton.isEnabled = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let elapsed = Int(Date().timeIntervalSince(self.started))
            self.progress.stringValue = "\(words.formatted()) words · \(elapsed / 60):\(String(format: "%02d", elapsed % 60)) elapsed"
        }
        let resources = Bundle.main.resourceURL!
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try worker.run(transcript: text, resources: resources) }
            DispatchQueue.main.async {
                guard let self, self.jobID == token else { return }
                self.timer?.invalidate(); self.timer = nil; self.runner = nil; self.jobID = nil
                self.spinner.stopAnimation(nil); self.spinner.isHidden = true; self.progress.isHidden = true
                self.cancelButton.isHidden = true
                switch result {
                case .success(let note):
                    self.display(note)
                    do {
                        let copied = try ClipboardOutput.write(self.rich!, to: .general, expectedChange: self.snapshot?.changeCount)
                        if copied {
                            self.lastWrite = NSPasteboard.general.changeCount; self.restoreButton.isHidden = false
                            self.detail.stringValue = "Your summary is on the clipboard. Paste it into Apple Notes with ⌘V."
                        } else {
                            self.detail.stringValue = "Your summary is ready. You copied something else, so choose Copy summary when you’re ready to paste."
                        }
                        NSSound(named: "Glass")?.play(); NSApp.requestUserAttention(.informationalRequest)
                    } catch { self.showError(error) }
                case .failure(let error):
                    self.showInputControls()
                    if error is CancellationError { self.detail.stringValue = "Cancelled. Your transcript is still here and your clipboard is unchanged." }
                    else { self.showError(error) }
                }
            }
        }
    }
    func display(_ note: Summary) {
        preview.isEditable = false
        rich = NoteRenderer.render(note)
        let screen = NSMutableAttributedString(attributedString: rich!)
        screen.addAttribute(.foregroundColor, value: NSColor.textColor, range: NSRange(location: 0, length: screen.length))
        updatingText = true
        preview.textStorage?.setAttributedString(screen)
        preview.setSelectedRange(NSRange(location: 0, length: 0))
        preview.scrollToBeginningOfDocument(nil)
        preview.undoManager?.removeAllActions()
        updatingText = false
        mode = .result; preview.isEditable = false; preview.allowsTranscriptPaste = true
        copyButton.isHidden = false; copyButton.keyEquivalent = "\r"
        summarizeButton.isHidden = true; summarizeButton.keyEquivalent = ""
        newButton.isHidden = false
    }
    func showError(_ error: Error) { detail.stringValue = error.localizedDescription }
    @objc func cancel() { runner?.cancel(); cancelButton.isEnabled = false; detail.stringValue = "Cancelling…" }
    @objc func copySummary() {
        guard mode == .result, let rich else { return }
        do {
            _ = try ClipboardOutput.write(rich, to: .general)
            lastWrite = NSPasteboard.general.changeCount; restoreButton.isHidden = snapshot == nil
            detail.stringValue = "Your summary is on the clipboard. Paste it into Apple Notes with ⌘V."
        } catch { showError(error) }
    }
    @objc func restoreClipboard() {
        guard let snapshot else { return }
        guard lastWrite == NSPasteboard.general.changeCount else {
            detail.stringValue = "Your clipboard has changed since the summary was copied, so it was left alone."
            return
        }
        if snapshot.restore(to: .general) {
            lastWrite = nil; restoreButton.isHidden = true
            detail.stringValue = "Previous clipboard restored. Choose Copy summary to copy the formatted result again."
        } else { detail.stringValue = "Couldn't restore the clipboard. The summary is still available here." }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
    func applicationWillTerminate(_ notification: Notification) { runner?.cancel() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
