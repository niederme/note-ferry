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
