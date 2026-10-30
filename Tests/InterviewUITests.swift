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
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = "Jamie: I can send it Friday. Alex: We still need to review the proposal before deciding what to share with the project team."
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 790), styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        func make() -> InterviewWindow {
            InterviewWindow(source: source, context: "NOVA is the project.", provider: .codex, model: nil, apiKey: nil, workspaceID: nil, resources: root.appendingPathComponent("Resources"), codexExecutable: root.appendingPathComponent("Tests/mock-codex.sh"))
        }
        var finished: [Clarification]?
        let skipped = make()
        skipped.onFinish = { values, usage in finished = values; check(usage.tokens == nil && usage.complete, "Skip consumed tokens") }
        skipped.show(on: parent)
        button("Skip interview", in: parent.attachedSheet!).performClick(nil)
        check(finished?.isEmpty == true, "Skip did not go directly to summary")
        pump { parent.attachedSheet == nil }

        setenv("NF_TEST_MODE", "interview", 1)
        defer { unsetenv("NF_TEST_MODE") }
        let active = make()
        var totals: InterviewUsage?
        active.onFinish = { finished = $0; totals = $1 }
        active.show(on: parent)
        let panel = parent.attachedSheet!
        button("Start interview", in: panel).performClick(nil)
        pump { active.session.pending.count == 1 }
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
        let questionBounds = questionLabel.convert(questionLabel.bounds, to: panel.contentView!)
        let interviewScroll = views.compactMap { $0 as? NSScrollView }.first!
        let viewport = interviewScroll.convert(interviewScroll.bounds, to: panel.contentView!)
        check(viewport.maxY - questionBounds.maxY < 40, "Short interview questions were aligned at bottom of viewport")
        setenv("NF_TEST_MODE", "interview_followup", 1)
        button("Continue interview", in: panel).performClick(nil)
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
        clear.show(on: parent)
        button("Start interview", in: parent.attachedSheet!).performClick(nil)
        pump { finished != nil }
        check(finished!.isEmpty, "Clear input did not bypass questions")
        pump { parent.attachedSheet == nil }

        setenv("NF_TEST_MODE", "interview_three", 1)
        let three = make()
        three.show(on: parent)
        let threePanel = parent.attachedSheet!
        button("Start interview", in: threePanel).performClick(nil)
        pump { three.session.pending.count == 3 }
        threePanel.contentView!.layoutSubtreeIfNeeded()
        let threeViews = descendants(threePanel.contentView!)
        let threeFields = threeViews.compactMap { $0 as? NSTextView }
        check(threeFields.count == 3 && threeFields.allSatisfy { $0.frame.height >= 60 }, "Multiple answer fields collapsed")
        let threeScroll = threeViews.compactMap { $0 as? NSScrollView }.first!
        check(threeScroll.documentView!.frame.height > threeScroll.contentSize.height, "Long interview cannot scroll")
        button("Cancel", in: threePanel).performClick(nil)
        pump { parent.attachedSheet == nil }

        setenv("NF_TEST_MODE", "malformed", 1)
        let failed = make()
        failed.show(on: parent)
        let failedPanel = parent.attachedSheet!
        button("Start interview", in: failedPanel).performClick(nil)
        pump { descendants(failedPanel.contentView!).compactMap { $0 as? NSButton }.contains { $0.title == "Retry questions" } }
        var cancelled = false
        failed.onCancel = { cancelled = true }
        button("Cancel", in: failedPanel).performClick(nil)
        check(cancelled, "Error recovery could not cancel")
        pump { parent.attachedSheet == nil }

        setenv("NF_TEST_MODE", "hang", 1)
        let pending = make()
        finished = nil; totals = nil
        pending.onFinish = { finished = $0; totals = $1 }
        pending.show(on: parent)
        let pendingPanel = parent.attachedSheet!
        button("Start interview", in: pendingPanel).performClick(nil)
        button("Skip interview", in: pendingPanel).performClick(nil)
        check(finished?.isEmpty == true && totals?.complete == false, "Skip while loading failed or misreported usage")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        check(pending.session.pending.isEmpty, "Late result reopened skipped interview")
        print("Passed \(checks) interview UI checks. No real model calls or clipboard writes.")
    }
}
