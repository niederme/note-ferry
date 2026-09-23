import AppKit

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
        rejects({ _ = try MarkdownFormatter.render("```\n```") }, "Empty code fence replaced clipboard with blank output")
        let shortText = try MarkdownFormatter.render("Hello, world.")
        check(shortText.string == "Hello, world.\n", "Short plain text should not require a transcript")
        let hardBreak = try MarkdownFormatter.render("First line  \nsecond line")
        check(hardBreak.string == "First line\u{2028}second line\n", "Explicit Markdown line break lost")
        rejects({ _ = try MarkdownFormatter.render(" \n\t") }, "Blank formatting input accepted")
        rejects({ _ = try MarkdownFormatter.render(String(repeating: "é", count: 200_001)) }, "Oversized formatting input accepted")
        let validSource = String(repeating: "Alex: Discuss the project. Sam: I will send the proposal on Friday.\n", count: 10)
        try Transcript.validate(validSource)
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
        setenv("SN_TEST_MODE", "success", 1)
        let generated = try CodexRunner().run(transcript: validSource, resources: resources, executable: mock)
        check(generated.title == note.title, "Backend did not decode a valid response")
        for mode in ["fail", "malformed", "empty"] {
            setenv("SN_TEST_MODE", mode, 1)
            rejects({ _ = try CodexRunner().run(transcript: validSource, resources: resources, executable: mock) }, "Invalid response accepted: " + mode)
            check(board.string(forType: .string) == validSource, "Backend failure touched clipboard")
        }
        setenv("SN_TEST_MODE", "hang", 1)
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
        unsetenv("SN_TEST_MODE")
        print("Passed \(checks) checks: RTF/native lists, spacing, Unicode, clipboard race/restore, validation, failures, timeout, cancellation.")
    }
}
