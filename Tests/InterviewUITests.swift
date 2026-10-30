import AppKit

@main struct InterviewUITests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fatalError(message) }
    }
    static func pump(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(8)
        while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        check(condition(), "UI request did not finish")
    }
    static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    static func button(_ title: String, in panel: NSWindow) -> NSButton {
        descendants(panel.contentView!).compactMap { $0 as? NSButton }.first { $0.title == title }!
    }
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        for screenSize in [NSSize(width: 1280, height: 720), NSSize(width: 1440, height: 825), NSSize(width: 2560, height: 1400)] {
            let screen = NSRect(origin: .zero, size: screenSize)
            let size = AppWindowSizing.contentSize(preferred: NSSize(width: 980, height: 880), visibleFrame: screen, styleMask: [.titled, .resizable])
            let frame = NSWindow.frameRect(forContentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable])
            check(frame.width <= screen.width - 48 && frame.height <= screen.height - 48, "Window exceeds available laptop screen area")
            if screen.width == 2560 { check(size == NSSize(width: 980, height: 880), "Larger display did not get larger default window") }
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = "Jamie: I can send it Friday. Alex: We still need to review the proposal before deciding what to share with the project team."
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 790), styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        func make() -> InterviewWindow {
            InterviewWindow(source: source, context: "NOVA is the project.", provider: .codex, model: nil, apiKey: nil, workspaceID: nil, resources: root.appendingPathComponent("Resources"), codexExecutable: root.appendingPathComponent("Tests/mock-codex.sh"))
        }
        var finished: [Clarification]?
        setenv("NF_TEST_MODE", "interview", 1)
        defer { unsetenv("NF_TEST_MODE") }
        let active = make()
        var totals: InterviewUsage?
        active.onFinish = { finished = $0; totals = $1 }
        active.start(on: parent)
        check(parent.attachedSheet == nil, "Interview appeared before any model questions")
        pump { active.session.pending.count == 1 }
        let panel = parent.attachedSheet!
        check(panel.styleMask.contains(.resizable), "Interview cannot be resized")
        let primary = button("Continue interview", in: panel)
        check(panel.defaultButtonCell === primary.cell, "Interview has no native primary action")
        check(primary.bezelColor == NSColor.controlAccentColor, "Primary action loses accent treatment while editing")
        let views = descendants(panel.contentView!)
        let picker = views.compactMap { $0 as? NSPopUpButton }.first!
        picker.selectItem(at: 1)
        NSApp.sendAction(picker.action!, to: picker.target, from: picker)
        let field = views.compactMap { $0 as? NSTextView }.first!
        check(field.string == "The proposal", "Suggestion did not populate editable answer")
        field.string = "The proposal, but this was an offer, not a commitment."
        panel.contentView!.layoutSubtreeIfNeeded()
        if let bitmap = panel.contentView!.bitmapImageRepForCachingDisplay(in: panel.contentView!.bounds) {
            panel.contentView!.cacheDisplay(in: panel.contentView!.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(".build/interview-ui.png"))
        }
        check(field.frame.width > 400 && field.frame.height > 30, "Answer field collapsed")
        let questionLabel = views.compactMap { $0 as? NSTextField }.first { $0.stringValue.hasPrefix("1. ") }!
        let excerptLabel = views.compactMap { $0 as? NSTextField }.first { $0.stringValue.hasPrefix("“Jamie:") }!
        check(excerptLabel.font?.pointSize == questionLabel.font?.pointSize, "Excerpt font size differs from question")
        check(!NSFontManager.shared.traits(of: excerptLabel.font!).contains(.boldFontMask), "Excerpt became bold")
        let questionStack = questionLabel.superview as! NSStackView
        check(questionStack.customSpacing(after: questionLabel) == 6, "Question and excerpt gap was not tightened")
        let questionBounds = questionLabel.convert(questionLabel.bounds, to: panel.contentView!)
        let interviewScroll = views.compactMap { $0 as? NSScrollView }.first!
        let viewport = interviewScroll.convert(interviewScroll.bounds, to: panel.contentView!)
        check(viewport.maxY - questionBounds.maxY < 40, "Short interview questions were aligned at bottom of viewport")
        setenv("NF_TEST_MODE", "interview_followup", 1)
        let continueKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        check(panel.performKeyEquivalent(with: continueKey), "Command-Return did not activate primary action while editing")
        pump { active.session.round == 2 }
        check(active.session.history.count == 1 && active.session.history[0].answer.contains("offer"), "Follow-up lost earlier answer")
        button("Finish & summarize", in: panel).performClick(nil)
        check(finished?.count == 2 && finished?.last?.answer == "", "Finish did not retain answered and unanswered history")
        check(totals?.tokens == TokenUsage(input: 200, output: 40), "UI token total omitted a round")
        pump { parent.attachedSheet == nil }

        setenv("NF_TEST_MODE", "interview_empty", 1)
        let clear = make()
        finished = nil
        clear.onFinish = { values, _ in finished = values }
        var clearPresented = false
        clear.onPresent = { clearPresented = true }
        clear.start(on: parent)
        check(parent.attachedSheet == nil, "Clear input showed a preflight screen")
        pump { finished != nil }
        check(finished!.isEmpty && !clearPresented, "Clear input did not bypass the interview entirely")
        pump { parent.attachedSheet == nil }

        setenv("NF_TEST_MODE", "interview_three", 1)
        let three = make()
        three.start(on: parent)
        pump { three.session.pending.count == 3 }
        let threePanel = parent.attachedSheet!
        threePanel.setContentSize(NSSize(width: 620, height: 560))
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        threePanel.contentView!.layoutSubtreeIfNeeded()
        let threeViews = descendants(threePanel.contentView!)
        let threeFields = threeViews.compactMap { $0 as? NSTextView }
        check(threeFields.count == 3 && threeFields.allSatisfy { $0.frame.height >= 60 }, "Multiple answer fields collapsed")
        let threeScroll = threeViews.compactMap { $0 as? NSScrollView }.first!
        check(threeScroll.documentView!.frame.height > threeScroll.contentSize.height, "Long interview cannot scroll")
        check(threeScroll.scrollerStyle == .legacy && !threeScroll.autohidesScrollers, "Question scrolling has no persistent scrollbar")
        check(threeFields.allSatisfy { $0.enclosingScrollView?.scrollerStyle == .legacy && $0.enclosingScrollView?.autohidesScrollers == false }, "Answer scrolling has no persistent scrollbar")
        check(threeViews.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("Scroll down for more questions") }, "Long interview has no scrolling hint")
        button("Cancel", in: threePanel).performClick(nil)
        pump { parent.attachedSheet == nil }

        setenv("NF_TEST_MODE", "malformed", 1)
        let failed = make()
        var failure: Error?
        failed.onInitialFailure = { failure = $0 }
        failed.start(on: parent)
        pump { failure != nil }
        check(parent.attachedSheet == nil, "Initial failure opened an interview without questions")

        setenv("NF_TEST_MODE", "hang", 1)
        let pending = make()
        finished = nil
        var cancelled = false
        var pendingPresented = false
        pending.onFinish = { finished = $0; totals = $1 }
        pending.onPresent = { pendingPresented = true }
        pending.onCancel = { cancelled = true }
        pending.start(on: parent)
        check(parent.attachedSheet == nil, "Background assessment presented a loading screen")
        pending.cancel()
        check(cancelled && finished == nil, "Cancellation started an unwanted summary")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        check(pending.session.pending.isEmpty && !pendingPresented, "Late result opened cancelled interview")

        setenv("NF_TEST_MODE", "interview", 1)
        let skipped = make()
        skipped.onFinish = { values, _ in finished = values }
        skipped.start(on: parent)
        pump { skipped.session.pending.count == 1 }
        button("Finish & summarize", in: parent.attachedSheet!).performClick(nil)
        check(finished?.count == 1 && finished?.first?.answer.isEmpty == true, "Skipping questions did not proceed without answers")
        pump { parent.attachedSheet == nil }

        let followup = make()
        followup.start(on: parent)
        pump { followup.session.pending.count == 1 }
        let followupPanel = parent.attachedSheet!
        setenv("NF_TEST_MODE", "malformed", 1)
        button("Continue interview", in: followupPanel).performClick(nil)
        pump { descendants(followupPanel.contentView!).compactMap { $0 as? NSButton }.contains { $0.title == "Retry questions" } }
        button("Cancel", in: followupPanel).performClick(nil)
        pump { parent.attachedSheet == nil }
        print("Passed \(checks) interview UI checks. No real model calls or clipboard writes.")
    }
}
