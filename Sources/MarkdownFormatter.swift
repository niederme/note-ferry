import AppKit

/// Local Markdown conversion. Source text never passes through a model or an HTML loader.
enum MarkdownFormatter {
    private struct Block {
        enum Kind { case paragraph, heading(Int), list(Int, Int?), code, quote }
        let kind: Kind
        var text: String
    }

    static func render(_ source: String) throws -> NSAttributedString {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.message("Paste some text to format. Your clipboard is unchanged.")
        }
        guard source.utf8.count <= 400_000 else {
            throw AppError.message("This text is larger than 400 KB. Format it in smaller parts. Nothing was truncated or sent.")
        }
        let blocks = parse(source)
        let result = NSMutableAttributedString(string: "")
        let base = NSMutableParagraphStyle()
        base.paragraphSpacing = 0; base.paragraphSpacingBefore = 0
        var lists: [(indent: Int, ordered: Bool, list: NSTextList)] = []
        func spacer(_ text: String) {
            result.append(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14), .paragraphStyle: base]))
        }
        for (index, block) in blocks.enumerated() {
            let paragraph = base.mutableCopy() as! NSMutableParagraphStyle
            var size: CGFloat = 14
            var bold = false
            var code = false
            if index > 0 {
                switch block.kind {
                case .heading: spacer("\n\n")
                case .list:
                    // List items already carry a soft return for space inside the preceding item.
                    if case .list = blocks[index - 1].kind {} else { spacer("\n") }
                default: spacer("\n")
                }
            }
            switch block.kind {
            case .heading(let level): size = level == 1 ? 24 : 17; bold = true; lists = []
            case .list(let indent, let number):
                while let last = lists.last, last.indent > indent { lists.removeLast() }
                if let last = lists.last, last.indent == indent, last.ordered != (number != nil) { lists.removeLast() }
                if lists.last?.indent != indent {
                    let list = NSTextList(markerFormat: number == nil ? .disc : .init(rawValue: "{decimal}."), options: 0)
                    list.startingItemNumber = number ?? 1
                    lists.append((indent, number != nil, list))
                }
                paragraph.textLists = lists.map(\.list)
                paragraph.headIndent = CGFloat(lists.count * 22)
                paragraph.firstLineHeadIndent = CGFloat((lists.count - 1) * 22)
                paragraph.tabStops = [NSTextTab(textAlignment: .left, location: CGFloat((lists.count - 1) * 22 + 8)), NSTextTab(textAlignment: .left, location: CGFloat(lists.count * 22))]
            case .code: code = true; lists = []
            case .quote: paragraph.headIndent = 18; paragraph.firstLineHeadIndent = 18; lists = []
            case .paragraph: lists = []
            }
            let rich = code
                ? NSAttributedString(string: block.text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)])
                : inline(block.text, size: size, bold: bold)
            let styled = NSMutableAttributedString(attributedString: rich)
            styled.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: styled.length))
            result.append(styled)
            var ending = "\n"
            if case .list = block.kind, index + 1 < blocks.count, case .list = blocks[index + 1].kind { ending = "\u{2028}\n" }
            result.append(NSAttributedString(string: ending, attributes: [.font: NSFont.systemFont(ofSize: size), .paragraphStyle: paragraph]))
        }
        guard !result.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.message("There’s no text to format. Your clipboard is unchanged.")
        }
        return result
    }

    private static func inline(_ source: String, size: CGFloat, bold: Bool) -> NSAttributedString {
        // Apple's inline parser preserves links and emphasis without loading URLs or images.
        guard let parsed = try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return NSAttributedString(string: source, attributes: [.font: NSFont.systemFont(ofSize: size)])
        }
        let result = NSMutableAttributedString(string: "")
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            var font = intent.contains(.code) ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular) : NSFont.systemFont(ofSize: size)
            if bold || intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attributes[.link] = link }
            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return result
    }

    private static func matches(_ pattern: String, _ text: String) -> [String]? {
        let regex = try! NSRegularExpression(pattern: pattern)
        let text = text as NSString
        guard let match = regex.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length)) else { return nil }
        return (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : text.substring(with: match.range(at: $0)) }
    }

    private static func parse(_ source: String) -> [Block] {
        var lines = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        if let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            lines.removeSubrange(0..<first)
        }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        // Chat replies sometimes wrap an entire Markdown answer in a mislabeled code fence.
        // Only unwrap a complete outer fence when its contents show clear Markdown structure.
        if lines.count >= 3, let opening = lines.first, ["```", "```md", "```markdown", "```text", "```plaintext", "```vbnet"].contains(opening.lowercased()), lines.last == "```",
           !lines.dropFirst().dropLast().contains(where: { $0.hasPrefix("```") }),
           lines.dropFirst().dropLast().contains(where: { matches("^(#{1,6} |[-*+] \\*\\*|\\*\\*[^*]+\\*\\*$)", $0) != nil }) {
            lines = Array(lines.dropFirst().dropLast())
        }
        var blocks: [Block] = []
        var index = 0
        func isSpecial(_ line: String) -> Bool {
            matches("^\\s*(#{1,6} |[-*+] |[0-9]+[.)] |>|```|~~~)", line) != nil || (line.hasPrefix("**") && line.hasSuffix("**"))
        }
        func joined(_ lines: [String]) -> String {
            var output = ""
            for (index, line) in lines.enumerated() {
                let hardBreak = line.hasSuffix("  ") || line.hasSuffix("\\")
                var content = line.trimmingCharacters(in: .whitespaces)
                if line.hasSuffix("\\") { content.removeLast() }
                output += content
                if index + 1 < lines.count { output += hardBreak ? "\u{2028}" : " " }
            }
            return output
        }
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { index += 1; continue }
            if let fence = matches("^ {0,3}(`{3,}|~{3,})(.*)$", line) {
                let marker = fence[1]
                index += 1
                var body: [String] = []
                let closing = "^ {0,3}" + String(marker.prefix(1)) + "{" + String(marker.count) + ",}[ \t]*$"
                while index < lines.count && matches(closing, lines[index]) == nil { body.append(lines[index]); index += 1 }
                if index < lines.count { index += 1 }
                blocks.append(Block(kind: .code, text: body.joined(separator: "\n")))
                continue
            }
            // Indented code starts a block; a nested list marker remains a list item.
            let followsList: Bool
            if let last = blocks.last, case .list = last.kind { followsList = true } else { followsList = false }
            let nestedItem = followsList && matches("^\\s*(?:[-*+]|[0-9]+[.)]) +", line) != nil
            if let codeLine = matches("^(?: {4}|\\t)(.*)$", line), !nestedItem {
                var body = [codeLine[1]]; index += 1
                while index < lines.count {
                    if let next = matches("^(?: {4}|\\t)(.*)$", lines[index]) { body.append(next[1]) }
                    else if lines[index].trimmingCharacters(in: .whitespaces).isEmpty { body.append("") }
                    else { break }
                    index += 1
                }
                while body.last == "" { body.removeLast() }
                blocks.append(Block(kind: .code, text: body.joined(separator: "\n"))); continue
            }
            if let heading = matches("^ {0,3}(#{1,6}) +(.+?)(?: +#+)?$", line) {
                blocks.append(Block(kind: .heading(heading[1].count), text: heading[2])); index += 1; continue
            }
            if let heading = matches("^\\*\\*([^*]+)\\*\\*\\s*$", line) {
                blocks.append(Block(kind: .heading(2), text: heading[1])); index += 1; continue
            }
            if let item = matches("^(\\s*)(?:([-*+])|([0-9]+)[.)]) +(.+)$", line) {
                let indent = item[1].replacingOccurrences(of: "\t", with: "    ").count
                var body = [item[4]]
                index += 1
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty && !isSpecial(lines[index]) {
                    body.append(lines[index]); index += 1
                }
                blocks.append(Block(kind: .list(indent, Int(item[3])), text: joined(body))); continue
            }
            if let quote = matches("^ *> ?(.*)$", line) {
                var body = [quote[1]]; index += 1
                while index < lines.count, let next = matches("^ *> ?(.*)$", lines[index]) { body.append(next[1]); index += 1 }
                blocks.append(Block(kind: .quote, text: joined(body))); continue
            }
            var body = [line]; index += 1
            while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty && !isSpecial(lines[index]) { body.append(lines[index]); index += 1 }
            blocks.append(Block(kind: .paragraph, text: joined(body)))
        }
        return blocks
    }
}
