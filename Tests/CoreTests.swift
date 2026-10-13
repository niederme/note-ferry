import AppKit

final class MockClaudeURLProtocol: URLProtocol {
    static var status = 200
    static var payload = Data()
    static var observedRequest: URLRequest?
    static var observedBody = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.observedRequest = request
        if Self.status == -1 { return } // No response until cancelled or timed out.
        Self.observedBody = request.httpBody ?? Data()
        if Self.observedBody.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                Self.observedBody.append(contentsOf: buffer.prefix(count))
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct CoreTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError(message) }
    }
    static func rejects(_ body: () throws -> Void, _ message: String) {
        do { try body(); fatalError(message) } catch { checks += 1 }
    }
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let preferencesSuite = "me.nieder.note-ferry.tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: preferencesSuite)!
        defer { preferences.removePersistentDomain(forName: preferencesSuite) }
        let providerSettings = ProviderSettings(defaults: preferences, bundleIdentifier: preferencesSuite)
        check(providerSettings.defaultProvider == .apple, "New installs did not start with Apple Intelligence selected")
        check(!providerSettings.hasCompletedOnboarding, "New installs skipped provider onboarding")
        providerSettings.defaultProvider = .codex
        providerSettings.hasCompletedOnboarding = true
        let restoredSettings = ProviderSettings(defaults: preferences, bundleIdentifier: preferencesSuite)
        check(restoredSettings.defaultProvider == .codex && restoredSettings.hasCompletedOnboarding,
              "Provider choice and onboarding state did not persist")
        rejects({ try providerSettings.saveClaudeAPIKey("not-a-claude-api-key") },
                "Non-API clipboard text was accepted as a Claude key")
        let hasTestKey = try providerSettings.hasClaudeAPIKey()
        check(!hasTestKey, "A fresh test Keychain unexpectedly has a Claude key")
        if #available(macOS 26.0, *) {
            let actions = LocalSummarizer.unique([
                NoteItem(label: "FAQ drafting", text: "Sam will draft the updated FAQ by Thursday."),
                NoteItem(label: "FAQ drafting", text: "Sam offered to draft an updated FAQ by Thursday."),
                NoteItem(label: "FAQ drafting", text: "Priya will draft the marketing FAQ by Monday.")
            ])
            check(actions.count == 2 && actions[0].text.hasPrefix("Sam") && actions[1].text.hasPrefix("Priya"),
                  "On-device action consolidation lost a distinct action or kept a repeated one")
        }
        let resources = root.appendingPathComponent("Resources")
        let fixture = try Data(contentsOf: root.appendingPathComponent("Tests/fixture.json"))
        let note = try JSONDecoder().decode(Summary.self, from: fixture)
        try note.validate()
        let rendered = NoteRenderer.render(note)
        let rtf = try NoteRenderer.rtf(rendered)
        let decoded = try NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        // Modern AppKit moves typed bullet markers into native list metadata on import.
        check(decoded.string.replacingOccurrences(of: "\t•\t", with: "") == rendered.string.replacingOccurrences(of: "\t•\t", with: ""), "RTF round trip changed paragraph breaks or Unicode")
        check(decoded.string.contains("José’s café") && decoded.string.contains("🧭"), "Unicode lost")
        check(decoded.string.contains("\n\n\nAction items\n\n"), "Missing two blank paragraphs before a section and one after")
        check(!decoded.string.contains("Transcription notes"), "Empty sections should be omitted")
        check(decoded.string.contains("deferred.\u{2028}\nEvidence:"), "Soft return between bullets did not survive RTF round trip")
        check(!decoded.string.contains("claimed.\u{2028}"), "Last bullet should retain the existing section spacing")
        let heading = (decoded.string as NSString).range(of: "Action items")
        let font = decoded.attribute(.font, at: heading.location, effectiveRange: nil) as! NSFont
        check(NSFontManager.shared.traits(of: font).contains(.boldFontMask), "Section heading is not bold")
        let bullet = (decoded.string as NSString).range(of: "Maya")
        let paragraph = decoded.attribute(.paragraphStyle, at: bullet.location, effectiveRange: nil) as! NSParagraphStyle
        check(!paragraph.textLists.isEmpty, "Bullet is decorative rather than a native list after RTF round trip")
        let spacer = decoded.attribute(.paragraphStyle, at: heading.location - 1, effectiveRange: nil) as! NSParagraphStyle
        check(spacer.textLists.isEmpty, "Blank paragraph accidentally continued the list")
        check(spacer.paragraphSpacing == 0 && spacer.paragraphSpacingBefore == 0, "Spacing must use empty paragraphs")
        rejects({ try Transcript.validate("hello") }, "Tiny clipboard accepted")
        rejects({ try Transcript.validate(String(repeating: "é", count: 200_001)) }, "Oversized UTF-8 input accepted")
        let markdown = try String(contentsOf: root.appendingPathComponent("Tests/format-fixture.md"), encoding: .utf8)
        let formatted = try MarkdownFormatter.render(markdown)
        let formatRTF = try NoteRenderer.rtf(formatted)
        let formatDecoded = try NSAttributedString(data: formatRTF, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        check(formatDecoded.string == formatted.string, "Formatted Markdown changed during RTF round trip")
        func attributes(_ phrase: String) -> [NSAttributedString.Key: Any] {
            let range = (formatDecoded.string as NSString).range(of: phrase)
            check(range.location != NSNotFound, "Missing source wording: " + phrase)
            return formatDecoded.attributes(at: range.location, effectiveRange: nil)
        }
        check(NSFontManager.shared.traits(of: attributes("keep the launch small")[.font] as! NSFont).contains(.boldFontMask), "Inline bold lost")
        check(NSFontManager.shared.traits(of: attributes("customer feedback")[.font] as! NSFont).contains(.italicFontMask), "Inline italic lost")
        check(attributes("launch checklist")[.link] as? URL == URL(string: "https://example.com/checklist"), "Link destination lost")
        check(formatDecoded.string.contains("José’s café 🧭"), "Formatter lost Unicode")
        check(formatDecoded.string.contains("team.\u{2028}\nUseful evidence."), "Formatter lost bullet soft returns")
        check(formatDecoded.string.contains("\n\n\nNext steps\n\n"), "Formatter lost Notes section spacing")
        check((attributes("Keep the first announcement")[.paragraphStyle] as! NSParagraphStyle).textLists.count == 2, "Nested list lost")
        check(formatDecoded.string.contains("let literal = \"**not bold**\""), "Code contents were interpreted as Markdown")
        let fallback = NoteRenderer.plainText(formatted)
        check(fallback.contains("3. Review") && fallback.contains("4. Publish") && fallback.contains("5. Collect"), "Numbering or nested-list continuation lost")
        check(fallback.contains("  • Keep the first announcement"), "Nested plain-text indentation lost")
        check(formatDecoded.string.contains("feedback.\n\nA separate paragraph stays separate."), "Paragraph separation lost")
        let wrapped = try MarkdownFormatter.render("```vbnet\n**What worked**\n\n- **Evidence.** We checked the result.\n```")
        check(wrapped.string == "What worked\n\nEvidence. We checked the result.\n", "Chat Markdown wrapper was not handled")
        let codeHeading = try MarkdownFormatter.render("```python\n# A comment\nprint('hello')\n```")
        check(codeHeading.string == "# A comment\nprint('hello')\n", "Code fence mistaken for a chat answer")
        let actions = "# Action items\n\n```codex-prompt\nReview the seven vendors’ responses.\nPrepare follow-up questions by Friday.\n```\n\n```codex-prompt\nDraft a **short rubric** for the calls.\n```"
        let actionText = try MarkdownFormatter.render(actions)
        check(actionText.string == "Action items\n\nReview the seven vendors’ responses. Prepare follow-up questions by Friday.\u{2028}\nDraft a short rubric for the calls.\n", "Codex action wording, wrapping, or spacing lost")
        let actionRTF = try NoteRenderer.rtf(actionText)
        let decodedActions = try NSAttributedString(data: actionRTF, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        check(decodedActions.string == actionText.string, "Codex actions changed during RTF round trip")
        for phrase in ["Review the seven", "Draft a short"] {
            let range = (decodedActions.string as NSString).range(of: phrase)
            let style = decodedActions.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as! NSParagraphStyle
            let font = decodedActions.attribute(.font, at: range.location, effectiveRange: nil) as! NSFont
            check(style.textLists.count == 1, "Codex action should be a native bullet")
            check(!font.isFixedPitch, "Codex action should not use a code font")
        }
        check(NoteRenderer.plainText(actionText).contains("• Review the seven") && NoteRenderer.plainText(actionText).contains("\n\n• Draft a short"), "Codex actions lost bullets or spacing in plain text")
        let wrappedActions = try MarkdownFormatter.render("````perl\n" + actions + "\n````")
        check(wrappedActions.string == actionText.string, "Nested Codex actions in a mislabeled chat wrapper were not handled")
        let tildeActions = try MarkdownFormatter.render("~~~codex-prompt\nReview the proposal.\n~~~")
        check(NoteRenderer.plainText(tildeActions).hasPrefix("• Review the proposal."), "Tilde prompt fence was not handled")
        let ordinaryNestedCode = "# A comment\n```swift\nlet a = 1\n```"
        let literalWrapper = try MarkdownFormatter.render("````perl\n" + ordinaryNestedCode + "\n````")
        check(literalWrapper.string == ordinaryNestedCode + "\n", "Ordinary nested code was unwrapped")
        let mixedActions = try MarkdownFormatter.render(actions + "\n\n```swift\nlet literal = \"**not bold**\"\n```")
        check(mixedActions.string.contains("let literal = \"**not bold**\""), "Source code following Codex actions lost its literal wording")
        let emptyAction = try MarkdownFormatter.render("Before.\n\n```codex-prompt\n \n```\n\nAfter.")
        check(emptyAction.string == "Before.\n\nAfter.\n", "Empty Codex action created a blank bullet")
        rejects({ _ = try MarkdownFormatter.render("```\n```") }, "Empty code fence replaced clipboard with blank output")
        let indentedCode = try MarkdownFormatter.render("    let a = 1\n    let b = 2\n\nAfterwards.")
        check(indentedCode.string == "let a = 1\nlet b = 2\n\nAfterwards.\n", "Indented code lost line breaks")
        let fenceBody = try MarkdownFormatter.render("```swift\nlet a = 1\n```oops\nlet b = 2\n```")
        check(fenceBody.string.contains("```oops\nlet b = 2"), "Nonclosing fence line was discarded")
        let shortText = try MarkdownFormatter.render("Hello, world.")
        check(shortText.string == "Hello, world.\n", "Short plain text should not require a transcript")
        let hardBreak = try MarkdownFormatter.render("First line  \nsecond line")
        check(hardBreak.string == "First line\u{2028}second line\n", "Explicit Markdown line break lost")
        try testMarkdownPatterns(root: root)
        rejects({ _ = try MarkdownFormatter.render(" \n\t") }, "Blank formatting input accepted")
        rejects({ _ = try MarkdownFormatter.render(String(repeating: "é", count: 200_001)) }, "Oversized formatting input accepted")
        let validSource = String(repeating: "Alex: Discuss the project. Sam: I will send the proposal on Friday.\n", count: 10)
        try Transcript.validate(validSource)
        let chunkSource = "First decision and rationale.\nSecond decision with a longer explanation.\nThird decision and follow-up."
        let chunks = TextChunker.split(chunkSource, maxCharacters: 35)
        check(chunks.count > 1 && chunks.allSatisfy { $0.count <= 35 }, "Long text was not split within the model budget")
        check(chunks.joined(separator: " ").split(whereSeparator: \.isWhitespace).map(String.init)
              == chunkSource.split(whereSeparator: \.isWhitespace).map(String.init), "Chunking dropped or reordered source words")
        let unbroken = String(repeating: "x", count: 90)
        check(TextChunker.split(unbroken, maxCharacters: 25).joined() == unbroken, "Long unbroken source was truncated")
        let tinyTailSource = String(repeating: "A ", count: 1_990) + "Maya: I will send it Friday."
        let balanced = TextChunker.split(tinyTailSource, maxCharacters: 4_000)
        check(balanced.count == 2 && balanced.allSatisfy { $0.count >= 800 && $0.count <= 4_000 }, "Tiny final model chunk was not balanced")
        check(balanced.joined(separator: " ").split(whereSeparator: \.isWhitespace).map(String.init)
              == tinyTailSource.split(whereSeparator: \.isWhitespace).map(String.init), "Rebalancing lost source words")
        let turnSource = String(repeating: "A ", count: 18) + "\nMaya: I will send the prototype Friday."
        let turns = TextChunker.split(turnSource, maxCharacters: 50)
        check(turns.count == 2 && turns[1].hasPrefix("Maya:"), "Chunker split a speaker turn")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString(validSource, forType: .string)
        let snapshot = ClipboardSnapshot(board)
        board.clearContents(); board.setString("A newer clipboard", forType: .string)
        let untouched = try ClipboardOutput.write(rendered, to: board, expectedChange: snapshot.changeCount)
        check(!untouched && board.string(forType: .string) == "A newer clipboard", "Newer clipboard was overwritten")
        let copied = try ClipboardOutput.write(rendered, to: board)
        check(copied && board.data(forType: .rtf) != nil && board.types!.contains(ClipboardOutput.marker), "Rich clipboard representations missing")
        check(board.string(forType: .string) == NoteRenderer.plainText(rendered), "Plain text fallback differs")
        check(NoteRenderer.plainText(rendered).contains("• Maya: "), "Plain text fallback lost bullet markers")
        check(NoteRenderer.plainText(rendered).contains("deferred.\n\n• Evidence:"), "Plain text fallback lost bullet spacing")
        check(snapshot.restore(to: board) && board.string(forType: .string) == validSource, "Restore did not preserve original text")
        let formatCopied = try ClipboardOutput.write(formatted, to: board)
        check(formatCopied && board.string(forType: .string) == fallback && board.data(forType: .rtf) != nil, "Formatted clipboard output missing")
        check(snapshot.restore(to: board), "Formatted output could not restore clipboard")
        let mock = root.appendingPathComponent("Tests/mock-codex.sh")
        setenv("NF_TEST_MODE", "success", 1)
        let generated = try CodexRunner().run(transcript: validSource, resources: resources, executable: mock)
        check(generated.title == note.title, "Backend did not decode a valid response")
        for mode in ["fail", "malformed", "empty"] {
            setenv("NF_TEST_MODE", mode, 1)
            rejects({ _ = try CodexRunner().run(transcript: validSource, resources: resources, executable: mock) }, "Invalid response accepted: " + mode)
            check(board.string(forType: .string) == validSource, "Backend failure touched clipboard")
        }
        setenv("NF_TEST_MODE", "hang", 1)
        let before = Date()
        rejects({ _ = try CodexRunner(timeout: 0.15).run(transcript: validSource, resources: resources, executable: mock) }, "Timeout not enforced")
        check(Date().timeIntervalSince(before) < 4, "Timeout did not terminate process promptly")
        let cancelRunner = CodexRunner()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { cancelRunner.cancel() }
        do { _ = try cancelRunner.run(transcript: validSource, resources: resources, executable: mock); fatalError("Cancellation was ignored") }
        catch is CancellationError { checks += 1 }
        let alreadyCancelled = CodexRunner(); alreadyCancelled.cancel()
        do { _ = try alreadyCancelled.run(transcript: validSource, resources: resources, executable: mock); fatalError("Pre-start cancellation ignored") }
        catch is CancellationError { checks += 1 }
        // Claude tests use URLProtocol, so no request reaches Anthropic.
        let claudeConfiguration = URLSessionConfiguration.ephemeral
        claudeConfiguration.protocolClasses = [MockClaudeURLProtocol.self]
        let claudeSession = URLSession(configuration: claudeConfiguration)
        let fixtureText = String(decoding: fixture, as: UTF8.self)
        func envelope(_ text: String, stop: String = "end_turn") -> Data {
            try! JSONSerialization.data(withJSONObject: [
                "content": [["type": "text", "text": text]],
                "stop_reason": stop
            ])
        }
        MockClaudeURLProtocol.status = 200
        MockClaudeURLProtocol.payload = envelope(fixtureText)
        let claudeResult = try ClaudeRunner(session: claudeSession, timeout: 2)
            .run(transcript: validSource, resources: resources, apiKey: "test-key")
        check(claudeResult.title == note.title, "Claude response did not decode")
        let claudeRequest = MockClaudeURLProtocol.observedRequest!
        check(claudeRequest.url?.absoluteString == "https://api.anthropic.com/v1/messages"
              && claudeRequest.httpMethod == "POST", "Claude request used the wrong endpoint")
        check(claudeRequest.value(forHTTPHeaderField: "x-api-key") == "test-key"
              && claudeRequest.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01",
              "Claude authentication or version headers are wrong")
        check(!MockClaudeURLProtocol.observedBody.isEmpty, "Claude request had no body")
        let claudeBody = try JSONSerialization.jsonObject(with: MockClaudeURLProtocol.observedBody) as! [String: Any]
        let messages = claudeBody["messages"] as! [[String: String]]
        let output = claudeBody["output_config"] as! [String: Any]
        check(claudeBody["model"] as? String == "claude-sonnet-4-6"
              && messages[0]["content"]?.contains(validSource) == true
              && output["format"] != nil, "Claude request lost the source or schema")
        MockClaudeURLProtocol.status = 401
        do {
            _ = try ClaudeRunner(session: claudeSession, timeout: 2)
                .run(transcript: validSource, resources: resources, apiKey: "test-key")
            fatalError("Claude accepted an invalid API key response")
        } catch {
            check(error.localizedDescription.contains("401"), "Invalid key error did not identify HTTP 401")
        }
        MockClaudeURLProtocol.status = 403
        do {
            _ = try ClaudeRunner(session: claudeSession, timeout: 2)
                .run(transcript: validSource, resources: resources, apiKey: "test-key")
            fatalError("Claude accepted a key with insufficient permission")
        } catch {
            check(error.localizedDescription.contains("403"), "Permission error did not identify HTTP 403")
        }
        MockClaudeURLProtocol.status = 200
        MockClaudeURLProtocol.payload = envelope("not-json")
        rejects({ _ = try ClaudeRunner(session: claudeSession, timeout: 2)
            .run(transcript: validSource, resources: resources, apiKey: "test-key") },
            "Claude accepted malformed content")
        MockClaudeURLProtocol.payload = envelope(fixtureText, stop: "max_tokens")
        rejects({ _ = try ClaudeRunner(session: claudeSession, timeout: 2)
            .run(transcript: validSource, resources: resources, apiKey: "test-key") },
            "Claude accepted truncated content")
        MockClaudeURLProtocol.status = -1
        let slowClaude = ClaudeRunner(session: claudeSession, timeout: 0.1)
        let claudeStarted = Date()
        rejects({ _ = try slowClaude.run(transcript: validSource, resources: resources, apiKey: "test-key") },
                "Claude did not enforce its request timeout")
        check(Date().timeIntervalSince(claudeStarted) < 2, "Claude timeout took too long")
        let runningClaude = ClaudeRunner(session: claudeSession, timeout: 2)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { runningClaude.cancel() }
        do {
            _ = try runningClaude.run(transcript: validSource, resources: resources, apiKey: "test-key")
            fatalError("Claude running cancellation was ignored")
        } catch is CancellationError { checks += 1 }
        let cancelledClaude = ClaudeRunner(session: claudeSession, timeout: 2)
        cancelledClaude.cancel()
        do {
            _ = try cancelledClaude.run(transcript: validSource, resources: resources, apiKey: "test-key")
            fatalError("Claude pre-start cancellation was ignored")
        } catch is CancellationError { checks += 1 }
        check(board.string(forType: .string) == validSource, "Claude failure touched clipboard")
        unsetenv("NF_TEST_MODE")
        print("Passed \(checks) checks: RTF/native lists, spacing, Unicode, clipboard race/restore, validation, failures, timeout, cancellation.")
    }

    static func testMarkdownPatterns(root: URL) throws {
        let source = try String(contentsOf: root.appendingPathComponent("Tests/markdown-patterns.md"), encoding: .utf8)
        let rich = try MarkdownFormatter.render(source)
        let decoded = try NSAttributedString(data: NoteRenderer.rtf(rich), options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        check(decoded.string == rich.string, "Mixed Markdown wording changed in the RTF round trip")
        func attrs(_ phrase: String) -> [NSAttributedString.Key: Any] {
            let range = (decoded.string as NSString).range(of: phrase)
            check(range.location != NSNotFound, "Missing mixed Markdown wording: " + phrase)
            return decoded.attributes(at: range.location, effectiveRange: nil)
        }
        func cell(_ phrase: String) -> NSTextTableBlock {
            let style = attrs(phrase)[.paragraphStyle] as! NSParagraphStyle
            check(style.textBlocks.last is NSTextTableBlock, "Table cell metadata lost: " + phrase)
            return style.textBlocks.last as! NSTextTableBlock
        }
        check(cell("Criterion").table.numberOfColumns == 3, "Three-column table was flattened")
        check(cell("Experience").startingRow == 1 && cell("35%").startingColumn == 1, "Table rows or columns moved")
        check(cell("Vendor").table.numberOfColumns == 7 && cell("Atlas").startingRow == 1, "Wide table was flattened")
        check(NSFontManager.shared.traits(of: attrs("Criterion")[.font] as! NSFont).contains(.boldFontMask), "Table header should be bold")
        check((attrs("35%")[.paragraphStyle] as! NSParagraphStyle).alignment == .right, "Column alignment lost")
        check((attrs("Show a shipped app")[.paragraphStyle] as! NSParagraphStyle).alignment == .center, "Centered column lost")
        let plain = NoteRenderer.plainText(rich)
        check(plain.contains("Criterion\tWeight\tEvidence\nExperience\t35%\tShow a shipped app."), "Plain table fallback lost row/column separators")
        check(plain.contains("Atlas\tU\tU\tU\tU\tPending\t\n"), "Empty trailing table cell was discarded")
        let html = try NoteRenderer.tableHTML(rich)!
        let htmlText = String(decoding: html, as: UTF8.self)
        check(htmlText.contains("<table") && htmlText.contains("<td") && htmlText.contains("Verify ownership."), "HTML table clipboard representation lost structure")
        let plainHTML = try NoteRenderer.tableHTML(try MarkdownFormatter.render("Plain text."))
        check(plainHTML == nil, "Ordinary rich text should retain its existing clipboard representations")
        check(plain.contains("☐\tReview the proposal.\n\n☑\tRecord the decision."), "Checklist state or item spacing lost")
        check(plain.contains("☑\tSend the follow-up."), "Uppercase checked state lost")
        check(NSFontManager.shared.traits(of: attrs("Alternate heading")[.font] as! NSFont).contains(.boldFontMask), "Setext heading lost")
        check(plain.contains("────────────"), "Thematic divider was not rendered")
        check((attrs("A quoted list item")[.paragraphStyle] as! NSParagraphStyle).textLists.count == 1, "Quoted list lost native list structure")
        check((attrs("A quoted list item")[.paragraphStyle] as! NSParagraphStyle).headIndent >= 40, "Quoted list lost quote indentation")
        check(plain.contains("let literal = \"**not bold**\""), "Code inside a quote was interpreted as prose")
        check(attrs("Image: Architecture sketch")[.link] as? URL == URL(string: "https://example.com/sketch.png"), "Image alt text or destination was discarded")
        check(attrs("Outdated")[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue, "Strikethrough lost")
        check(plain.contains("literal **stars**"), "Inline code was interpreted as emphasis")
        check(attrs("https://example.com/guide")[.link] as? URL == URL(string: "https://example.com/guide"), "Autolink lost")
        check(plain.contains("| Literal | Code |\n| --- | --- |\n- [ ] Not a real checklist here."), "Code containing table/checklist syntax was transformed")
        let escaped = try MarkdownFormatter.render("Name | Detail\n--- | ---\nA \\| B | `x\\|y`\nShort |\nExtra | value | retained")
        check(NoteRenderer.plainText(escaped).contains("A | B\tx|y"), "Escaped table pipe split a cell or changed code wording")
        check(NoteRenderer.plainText(escaped).contains("Extra\tvalue\tretained"), "Ragged table discarded extra cell contents")
        let notTable = try MarkdownFormatter.render("A | B\nnot | a delimiter")
        let notTableHTML = try NoteRenderer.tableHTML(notTable)
        check(notTableHTML == nil && notTable.string.contains("A | B"), "Ordinary pipe-containing prose became a table")
        let nestedQuote = try MarkdownFormatter.render("> > **Nested quote**\n> >\n> > Continued.")
        check(nestedQuote.string.contains("Nested quote") && !nestedQuote.string.contains(">"), "Nested quote markers leaked into output")
        let title = try MarkdownFormatter.render("Two-line\nheading\n===\nBody.")
        check(title.string == "Two-line heading\n\nBody.\n", "Multiline setext heading lost structure")
        let breaks = try MarkdownFormatter.render("A | B\n--- | ---\nOne<br>two | `<br>`")
        check(NoteRenderer.plainText(breaks).contains("One\ntwo\t<br>"), "Table HTML line break was lost or code was interpreted as HTML")
        let screen = NoteRenderer.previewText(rich)
        check(screen.string.contains("\t•\tA quoted list item."), "Table-capable preview lost visible native list markers")
        check(!rich.string.contains("\t•\t"), "Preview markers changed the clipboard content")
        let view = NSTextView(usingTextLayoutManager: false)
        view.frame = NSRect(x: 0, y: 0, width: 900, height: 2000)
        view.textContainer?.containerSize = NSSize(width: 900, height: CGFloat.greatestFiniteMagnitude)
        view.textStorage?.setAttributedString(screen)
        let layout = view.layoutManager!, container = view.textContainer!
        layout.ensureLayout(for: container)
        func bounds(_ phrase: String) -> NSRect {
            let range = (screen.string as NSString).range(of: phrase)
            return layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: container)
        }
        let criterion = bounds("Criterion"), weight = bounds("Weight"), evidence = bounds("Evidence")
        check(abs(criterion.minY - weight.minY) < 1 && abs(weight.minY - evidence.minY) < 1, "Table header cells do not share a visual row")
        check(criterion.maxX < weight.minX && weight.maxX < evidence.minX, "Table columns overlap visually")
        check(bounds("Verify ownership.").maxX <= 900, "Wide table overflowed the text container")
        let nestedTasks = try MarkdownFormatter.render("- [ ] Parent\n    - [x] Child\n        - [ ] Grandchild\n- [ ] Next")
        let child = (nestedTasks.string as NSString).range(of: "Child")
        let grandchild = (nestedTasks.string as NSString).range(of: "Grandchild")
        check((nestedTasks.attribute(.paragraphStyle, at: child.location, effectiveRange: nil) as! NSParagraphStyle).headIndent == 44, "Nested checklist indentation lost")
        check((nestedTasks.attribute(.paragraphStyle, at: grandchild.location, effectiveRange: nil) as! NSParagraphStyle).headIndent == 66, "Deeper checklist became source code")
        let hugeRow = "| " + Array(repeating: "x", count: 160).joined(separator: " | ") + " |"
        let hugeDelimiter = "| " + Array(repeating: "-", count: 160).joined(separator: " | ") + " |"
        rejects({ _ = try MarkdownFormatter.render(([hugeRow, hugeDelimiter] + Array(repeating: hugeRow, count: 160)).joined(separator: "\n")) }, "Oversized table layout was accepted")
        let tableBoard = NSPasteboard.withUniqueName()
        defer { tableBoard.releaseGlobally() }
        let copied = try ClipboardOutput.write(rich, to: tableBoard)
        check(copied && tableBoard.data(forType: .rtf) != nil && tableBoard.data(forType: .html) != nil, "Table clipboard representations missing")
        check(tableBoard.string(forType: .string) == plain, "Plain clipboard table fallback changed")
    }
}
