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
        check(primary.contentTintColor == nil, "Primary action overrides the system text color")
        let views = descendants(panel.contentView!)
        check(!views.contains { $0 is NSPopUpButton }, "Multiple-choice questions still use dropdowns")
        let field = views.compactMap { $0 as? NSTextView }.first!
        check(field.enclosingScrollView!.isHidden, "Choice question showed free text before Something else")
        let proposal = button("The proposal", in: panel)
        let schedule = button("The schedule", in: panel)
        let custom = button("Something else", in: panel)
        check([proposal, schedule, custom].allSatisfy { $0.state == .off }, "A factual answer was preselected")
        proposal.performClick(nil)
        check(proposal.state == .on && schedule.state == .off && field.enclosingScrollView!.isHidden, "Preset selection revealed free text or selected multiple answers")
        schedule.performClick(nil)
        check(proposal.state == .off && schedule.state == .on, "Radio choices are not mutually exclusive")
        custom.performClick(nil)
        check(!field.enclosingScrollView!.isHidden && panel.firstResponder === field, "Something else did not reveal and focus the text field")
        field.string = "The proposal, but this was an offer, not a commitment."
        proposal.performClick(nil)
        check(field.enclosingScrollView!.isHidden, "Choosing a preset did not hide custom text")
        custom.performClick(nil)
        check(field.string.contains("offer"), "Switching choices discarded the custom draft")
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
        check(!button("Answers…", in: panel).isHidden, "Earlier answers cannot be reviewed")
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
        check(threeFields[0].enclosingScrollView!.isHidden && !threeFields[1].enclosingScrollView!.isHidden && threeFields[2].enclosingScrollView!.isHidden, "Free-text-only question is hidden or multiple-choice field is exposed")
        let firstChoice = button("The proposal", in: threePanel)
        firstChoice.performClick(nil)
        check(threePanel.firstResponder === firstChoice, "Selected radio choice cannot receive keyboard focus")
        press(firstChoice, keyCode: 125, characters: "\u{f701}")
        check(button("The schedule", in: threePanel).state == .on && firstChoice.state == .off, "Arrow key did not change the radio selection")
        press(button("The schedule", in: threePanel), keyCode: 48, characters: "\t")
        check(threePanel.firstResponder === threeFields[1], "Tab from a radio group did not reach the next question")
        let longChoice = threeViews.compactMap { $0 as? NSButton }.first { $0.title.count > 100 }!
        check(longChoice.frame.height > 22 && longChoice.cell?.wraps == true, "Long radio label is clipped instead of wrapping")
        let customChoices = threeViews.compactMap { $0 as? NSButton }.filter { $0.title == "Something else" }
        for choice in customChoices { choice.performClick(nil) }
        check(customChoices.allSatisfy { $0.state == .on }, "Selecting one question changed another question's radio group")
        threePanel.contentView!.layoutSubtreeIfNeeded()
        check(threeFields.count == 3 && threeFields.allSatisfy { $0.frame.height >= 60 }, "Multiple answer fields collapsed")
        let threeScroll = threeViews.compactMap { $0 as? NSScrollView }.first!
        check(threeScroll.documentView!.frame.height > threeScroll.contentSize.height, "Long interview cannot scroll")
        check(threeScroll.hasVerticalScroller, "Question scrolling is unavailable")
        check(threeFields.allSatisfy { $0.enclosingScrollView?.hasVerticalScroller == true }, "Answer scrolling is unavailable")
        check(threeViews.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("Scroll down for more questions") }, "Long interview has no scrolling hint")
        func press(_ field: NSResponder, keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = []) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: threePanel.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
            field.keyDown(with: event)
        }
        threePanel.makeFirstResponder(threeFields[0])
        press(threeFields[0], keyCode: 48, characters: "\u{19}", modifiers: [.shift])
        check(threePanel.firstResponder === customChoices[0], "Custom answer cannot return to its radio choices with Shift-Tab")
        press(customChoices[0], keyCode: 126, characters: "\u{f700}")
        check(threeFields[0].enclosingScrollView!.isHidden, "Arrowing from Something else did not hide custom input")
        customChoices[0].performClick(nil)
        threeFields[0].string = "First answer"
        threePanel.makeFirstResponder(threeFields[0])
        press(threeFields[0], keyCode: 48, characters: "\t")
        check(threePanel.firstResponder === threeFields[1], "Tab did not focus the next answer")
        check(threeFields[0].string == "First answer", "Tab inserted text into the answer")
        press(threeFields[1], keyCode: 48, characters: "\u{19}", modifiers: [.shift])
        check(threePanel.firstResponder === threeFields[0], "Shift-Tab did not return to the previous answer")
        threeFields[0].setSelectedRange(NSRange(location: threeFields[0].string.utf16.count, length: 0))
        press(threeFields[0], keyCode: 36, characters: "\r")
        check(threeFields[0].string == "First answer\n" && threePanel.firstResponder === threeFields[0], "Return no longer inserts a newline")
        threePanel.makeFirstResponder(threeFields[1])
        press(threeFields[1], keyCode: 48, characters: "\t")
        check(threePanel.firstResponder === threeFields[2], "Tab did not reach the last answer")
        let lastAnswerFrame = threeFields[2].enclosingScrollView!.convert(threeFields[2].enclosingScrollView!.bounds, to: threeScroll.documentView!)
        check(threeScroll.documentVisibleRect.intersects(lastAnswerFrame), "Tab left the focused answer outside the scroll viewport")
        press(threeFields[2], keyCode: 48, characters: "\t")
        check(threePanel.firstResponder === button("Continue interview", in: threePanel), "Tab from last answer did not reach the primary action")
        threePanel.selectPreviousKeyView(nil)
        check(threePanel.firstResponder === threeFields[2], "Backtab from the primary action did not return to the last answer")
        button("Cancel", in: threePanel).performClick(nil)
        pump { parent.attachedSheet == nil }

        setenv("NF_TEST_MODE", "interview", 1)
        let preset = make()
        finished = nil
        preset.onFinish = { values, _ in finished = values }
        preset.start(on: parent)
        pump { preset.session.pending.count == 1 }
        button("The proposal", in: parent.attachedSheet!).performClick(nil)
        button("Finish & summarize", in: parent.attachedSheet!).performClick(nil)
        check(finished?.first?.answer == "The proposal", "Selected radio answer was not submitted")
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

        setenv("NF_TEST_MODE", "hang", 1)
        let earlyFinish = make()
        finished = nil
        earlyFinish.onFinish = { finished = $0; totals = $1 }
        earlyFinish.start(on: parent)
        earlyFinish.finish()
        check(finished != nil && finished!.isEmpty, "Summarize now did not bypass the initial question check")
        check(totals?.tokens == nil, "Cancelled question check reported complete token usage")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        check(parent.attachedSheet == nil, "A late question appeared after Summarize now")

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
        let historyButton = button("Answers…", in: followupPanel)
        check(!historyButton.isHidden, "Follow-up failure hides the answers already submitted")
        check(historyButton.previousKeyView === button("Cancel", in: followupPanel), "Answer review is missing from the recovery keyboard loop")
        button("Cancel", in: followupPanel).performClick(nil)
        pump { parent.attachedSheet == nil }
        print("Passed \(checks) interview UI checks. No real model calls or clipboard writes.")
    }
}
