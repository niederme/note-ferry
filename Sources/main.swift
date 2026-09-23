import AppKit

// Headless verification uses the exact same backend and renderer as the app.
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    let status = NSTextField(labelWithString: "Copy a transcript. Come back with a summary.")
    let detail = NSTextField(wrappingLabelWithString: "")
    let privacy = NSTextField(wrappingLabelWithString: "Uses your Codex account to process the transcript with OpenAI. Formatting happens on your Mac.")
    let preview = NSTextView()
    let spinner = NSProgressIndicator()
    let primary = NSButton(title: "Summarize clipboard", target: nil, action: nil)
    let copyButton = NSButton(title: "Copy summary", target: nil, action: nil)
    let restoreButton = NSButton(title: "Restore transcript", target: nil, action: nil)
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    var runner: CodexRunner?
    var raw: String?
    var snapshot: ClipboardSnapshot?
    var rich: NSAttributedString?
    var lastWrite: Int?
    var jobID: UUID?
    var timer: Timer?
    var started = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        makeMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 790), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Summary Notes"
        window.minSize = NSSize(width: 620, height: 560)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 25, left: 28, bottom: 22, right: 28)
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor), root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor), root.topAnchor.constraint(equalTo: window.contentView!.topAnchor), root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor)])
        let eyebrow = NSTextField(labelWithString: "TRANSCRIPT → NOTES")
        eyebrow.font = .systemFont(ofSize: 11, weight: .semibold)
        eyebrow.textColor = .secondaryLabelColor
        root.addArrangedSubview(eyebrow)
        status.font = .systemFont(ofSize: 24, weight: .semibold)
        status.lineBreakMode = .byWordWrapping
        status.maximumNumberOfLines = 2
        root.addArrangedSubview(status)
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabelColor
        root.addArrangedSubview(detail)
        spinner.style = .bar
        spinner.isIndeterminate = true
        spinner.isHidden = true
        root.addArrangedSubview(spinner)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        preview.isEditable = false
        preview.isSelectable = true
        preview.isRichText = true
        preview.isAutomaticLinkDetectionEnabled = false
        preview.textContainerInset = NSSize(width: 24, height: 25)
        preview.isVerticallyResizable = true
        preview.isHorizontallyResizable = false
        preview.autoresizingMask = [.width]
        preview.textContainer?.widthTracksTextView = true
        preview.textContainer?.containerSize = NSSize(width: 680, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = preview
        root.addArrangedSubview(scroll)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
        privacy.font = .systemFont(ofSize: 11)
        privacy.textColor = .secondaryLabelColor
        root.addArrangedSubview(privacy)
        let buttons = NSStackView(views: [primary, copyButton, restoreButton, cancelButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        root.addArrangedSubview(buttons)
        for button in [primary, copyButton, restoreButton, cancelButton] { button.bezelStyle = .rounded; button.target = self }
        primary.action = #selector(startFromClipboard)
        primary.keyEquivalent = "\r"
        copyButton.action = #selector(copySummary)
        restoreButton.action = #selector(restoreTranscript)
        cancelButton.action = #selector(cancel)
        cancelButton.keyEquivalent = "\u{1b}"
        copyButton.isHidden = true; restoreButton.isHidden = true; cancelButton.isHidden = true
        for view in [status, detail, spinner, scroll, privacy] { view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56).isActive = true }
        showInstructions()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let index = arguments.firstIndex(of: "--preview"), arguments.count > index + 1 {
            do {
                let note = try JSONDecoder().decode(Summary.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[index + 1])))
                try note.validate()
                display(note)
                status.stringValue = "Your summary, with room to breathe."
                detail.stringValue = "Example preview. Copy summary when you’re ready to paste into Apple Notes."
            } catch { showError(error) }
        } else if !arguments.contains("--welcome") { startFromClipboard() }
    }

    func makeMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Summary Notes", action: #selector(about), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Summarize Clipboard", action: #selector(startFromClipboard), keyEquivalent: "n").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Summary Notes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu; menu.addItem(editItem)
        NSApp.mainMenu = menu
    }
    @objc func about() {
        let alert = NSAlert()
        alert.messageText = "Summary Notes"
        alert.informativeText = "Copy a transcript, launch this app, then paste into Apple Notes with ⌘V.\n\nUses your signed-in Codex CLI. Calls count against your account’s usage. The app keeps the source and preview in memory, uses a temporary result file during processing, and removes that file afterward. Codex runs with session history disabled.\n\nNo note is created or edited."
        alert.runModal()
    }
    func showInstructions() {
        detail.stringValue = "Detailed takeaways, action items, and topic notes. Ready for ⌘V in Apple Notes."
        let text = "1. Copy the raw transcript\n\nPlain text or Markdown from Nook, Granola, or another recorder.\n\n\n2. Launch Summary Notes\n\nUse Spotlight or Raycast. The app summarizes your clipboard automatically.\n\n\n3. Paste into Apple Notes\n\nWait for “Ready to paste,” then press ⌘V in the note you choose. Headings, native bullets, and real blank lines are included."
        preview.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.secondaryLabelColor]))
    }
    @objc func startFromClipboard() {
        guard runner == nil else { return }
        let board = NSPasteboard.general
        if board.types?.contains(ClipboardOutput.marker) == true {
            status.stringValue = "Your clipboard already has a summary."
            detail.stringValue = "Paste it into Apple Notes with ⌘V, or copy a new transcript first."
            return
        }
        guard let text = board.string(forType: .string) else {
            status.stringValue = "Copy a transcript to get started."
            detail.stringValue = "The clipboard doesn’t contain plain text. Copy your transcript, then choose Summarize clipboard."
            return
        }
        do { try Transcript.validate(text) } catch { showError(error); return }
        snapshot = ClipboardSnapshot(board)
        raw = text
        rich = nil; lastWrite = nil
        copyButton.isHidden = true; restoreButton.isHidden = true
        begin(text)
    }
    func begin(_ text: String) {
        let worker = CodexRunner()
        runner = worker
        let token = UUID(); jobID = token
        started = Date()
        status.stringValue = "Making room for the important details…"
        let words = text.split(whereSeparator: \.isWhitespace).count
        detail.stringValue = "Reading \(words.formatted()) words with Codex. Your clipboard stays intact until the summary is ready."
        preview.string = "Reading the conversation, organizing the topics, and checking the follow-ups.\n\nYou can keep working while this runs. If you copy something else, the summary will wait here."
        preview.font = .systemFont(ofSize: 15)
        spinner.isHidden = false; spinner.startAnimation(nil)
        primary.isHidden = true; copyButton.isHidden = true; restoreButton.isHidden = true; cancelButton.isHidden = false
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let elapsed = Int(Date().timeIntervalSince(self.started))
            self.detail.stringValue = "\(words.formatted()) source words · \(elapsed / 60):\(String(format: "%02d", elapsed % 60)) elapsed · Processing with Codex"
        }
        let resources = Bundle.main.resourceURL!
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try worker.run(transcript: text, resources: resources) }
            DispatchQueue.main.async {
                guard let self, self.jobID == token else { return }
                self.finishBusy()
                switch result {
                case .success(let note):
                    self.display(note)
                    do {
                        let copied = try ClipboardOutput.write(self.rich!, to: .general, expectedChange: self.snapshot?.changeCount)
                        if copied {
                            self.lastWrite = NSPasteboard.general.changeCount
                            self.restoreButton.isHidden = false
                            self.status.stringValue = "Ready to paste."
                            self.detail.stringValue = "Summary copied. Press ⌘V in Apple Notes. Your original transcript can be restored below."
                        } else {
                            self.status.stringValue = "Summary ready. Clipboard left alone."
                            self.detail.stringValue = "You copied something else while I worked. Choose Copy summary when you’re ready."
                        }
                        NSSound(named: "Glass")?.play()
                        NSApp.requestUserAttention(.informationalRequest)
                    } catch { self.showError(error) }
                case .failure(let error):
                    if error is CancellationError { self.status.stringValue = "Cancelled. Clipboard unchanged."; self.detail.stringValue = "You can retry the same transcript or copy a new one." }
                    else { self.showError(error) }
                    self.primary.title = "Retry transcript"
                    self.primary.action = #selector(self.retry)
                }
            }
        }
    }
    func finishBusy() {
        timer?.invalidate(); timer = nil; runner = nil; jobID = nil
        spinner.stopAnimation(nil); spinner.isHidden = true
        primary.isHidden = false; cancelButton.isHidden = true
        cancelButton.isEnabled = true
        primary.title = "Summarize clipboard"; primary.action = #selector(startFromClipboard)
    }
    func display(_ note: Summary) {
        rich = NoteRenderer.render(note)
        let screen = NSMutableAttributedString(attributedString: rich!)
        screen.addAttribute(.foregroundColor, value: NSColor.textColor, range: NSRange(location: 0, length: screen.length))
        preview.textStorage?.setAttributedString(screen)
        preview.setSelectedRange(NSRange(location: 0, length: 0))
        preview.scrollToBeginningOfDocument(nil)
        copyButton.isHidden = false
    }
    func showError(_ error: Error) {
        status.stringValue = "Couldn't make the summary."
        detail.stringValue = error.localizedDescription
    }
    @objc func retry() { if let raw, runner == nil { begin(raw) } }
    @objc func cancel() { runner?.cancel(); cancelButton.isEnabled = false; detail.stringValue = "Cancelling…" }
    @objc func copySummary() {
        guard let rich else { return }
        do {
            _ = try ClipboardOutput.write(rich, to: .general)
            lastWrite = NSPasteboard.general.changeCount
            restoreButton.isHidden = snapshot == nil
            status.stringValue = "Ready to paste."
            detail.stringValue = "Summary copied. Press ⌘V in Apple Notes."
        } catch { showError(error) }
    }
    @objc func restoreTranscript() {
        guard let snapshot else { return }
        guard lastWrite == NSPasteboard.general.changeCount else {
            detail.stringValue = "Your clipboard has changed since the summary was copied, so it was left alone."
            return
        }
        if snapshot.restore(to: .general) {
            lastWrite = nil; restoreButton.isHidden = true
            status.stringValue = "Original transcript restored."
            detail.stringValue = "The summary stays here. Use Copy summary to get it back."
        } else { detail.stringValue = "Couldn't restore the clipboard. Your transcript remains in memory for retry." }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        if runner == nil { startFromClipboard() }
        return true
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Keep an in-flight request and its original clipboard alive when the window closes.
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
