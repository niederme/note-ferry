import AppKit

/// Local Markdown conversion. Source text never passes through a model or an HTML loader.
enum MarkdownFormatter {
    private struct Block {
        enum Kind { case paragraph, heading(Int), list(Int, Int?), task(Int, Bool), code, divider, table([[String]], [NSTextAlignment]) }
        let kind: Kind
        var text: String
        var quoteDepth: Int = 0
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
        var taskIndents: [Int] = []
        func spacer(_ text: String) {
            result.append(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14), .paragraphStyle: base]))
        }
        for (index, block) in blocks.enumerated() {
            if case .task = block.kind {} else { taskIndents = [] }
            if index > 0, block.quoteDepth != blocks[index - 1].quoteDepth { lists = []; taskIndents = [] }
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
                case .task:
                    if case .task = blocks[index - 1].kind {} else { spacer("\n") }
                default: spacer("\n")
                }
            }
            if case .table(let rows, let alignments) = block.kind {
                guard (rows.map(\.count).max() ?? 0) * rows.count <= 25_000 else {
                    throw AppError.message("This table has too many cells to format. Split it into smaller tables. Your clipboard is unchanged.")
                }
                result.append(table(rows, alignments: alignments, quoteDepth: block.quoteDepth))
                lists = []
                continue
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
            case .task(let indent, _):
                if taskIndents.isEmpty { taskIndents = lists.isEmpty ? [0] : lists.map(\.indent) }
                while let last = taskIndents.last, last > indent { taskIndents.removeLast() }
                if taskIndents.last != indent { taskIndents.append(indent) }
                let inset = CGFloat((taskIndents.count - 1) * 22)
                paragraph.headIndent = inset + 22
                paragraph.firstLineHeadIndent = inset
                paragraph.tabStops = [NSTextTab(textAlignment: .left, location: inset + 22)]
                lists = []
            case .divider, .table: lists = []
            case .paragraph: lists = []
            }
            paragraph.headIndent += CGFloat(block.quoteDepth * 18)
            paragraph.firstLineHeadIndent += CGFloat(block.quoteDepth * 18)
            if block.quoteDepth > 0 {
                paragraph.tabStops = paragraph.tabStops.map { NSTextTab(textAlignment: $0.alignment, location: $0.location + CGFloat(block.quoteDepth * 18), options: $0.options) }
            }
            var text = block.text
            if case .task(_, let checked) = block.kind { text = (checked ? "☑" : "☐") + "\t" + text }
            let rich = code
                ? NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)])
                : inline(text, size: size, bold: bold)
            let styled = NSMutableAttributedString(attributedString: rich)
            styled.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: styled.length))
            result.append(styled)
            var ending = "\n"
            if case .list = block.kind, index + 1 < blocks.count, case .list = blocks[index + 1].kind { ending = "\u{2028}\n" }
            if case .task = block.kind, index + 1 < blocks.count, case .task = blocks[index + 1].kind { ending = "\u{2028}\n" }
            result.append(NSAttributedString(string: ending, attributes: [.font: NSFont.systemFont(ofSize: size), .paragraphStyle: paragraph]))
        }
        guard !result.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.message("There’s no text to format. Your clipboard is unchanged.")
        }
        return result
    }

    private static func table(_ rows: [[String]], alignments: [NSTextAlignment], quoteDepth: Int) -> NSAttributedString {
        let columns = rows.map(\.count).max() ?? 0
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.layoutAlgorithm = .fixedLayoutAlgorithm
        table.collapsesBorders = true
        table.setValue(100, type: .percentageValueType, for: .width)
        let weights = (0..<columns).map { column in
            CGFloat(min(80, max(12, rows.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0)))
        }
        let total = weights.reduce(0, +)
        let result = NSMutableAttributedString(string: "")
        for (row, cells) in rows.enumerated() {
            for column in 0..<columns {
                let cell = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                cell.setValue(weights[column] / total * 100, type: .percentageValueType, for: .width)
                cell.setWidth(6, type: .absoluteValueType, for: .padding)
                cell.setWidth(0.5, type: .absoluteValueType, for: .border)
                cell.setBorderColor(.gray)
                let paragraph = NSMutableParagraphStyle()
                paragraph.textBlocks = [cell]
                paragraph.alignment = column < alignments.count ? alignments[column] : .left
                paragraph.headIndent = CGFloat(quoteDepth * 18)
                let rich = NSMutableAttributedString(attributedString: inline(column < cells.count ? cells[column] : "", size: 14, bold: row == 0))
                rich.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 14)]))
                rich.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: rich.length))
                result.append(rich)
            }
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
            if let link = run.link ?? run.imageURL { attributes[.link] = link }
            var text = String(parsed[run.range].characters)
            if intent.contains(.inlineHTML), matches("(?i)^<br\\s*/?>$", text) != nil { text = "\u{2028}" }
            if run.imageURL != nil { text = "Image: " + (text.trimmingCharacters(in: .whitespaces).isEmpty ? "image" : text) }
            result.append(NSAttributedString(string: text, attributes: attributes))
        }
        return result
    }

    private static func matches(_ pattern: String, _ text: String) -> [String]? {
        let regex = try! NSRegularExpression(pattern: pattern)
        let text = text as NSString
        guard let match = regex.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length)) else { return nil }
        return (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : text.substring(with: match.range(at: $0)) }
    }

    private static func fence(_ line: String) -> (marker: String, info: String)? {
        guard let match = matches("^ {0,3}(`{3,}|~{3,})(.*)$", line) else { return nil }
        return (match[1], match[2].trimmingCharacters(in: .whitespaces).lowercased())
    }

    private static func closesFence(_ line: String, marker: String) -> Bool {
        matches("^ {0,3}" + String(marker.prefix(1)) + "{" + String(marker.count) + ",}[ \\t]*$", line) != nil
    }

    private static func tableCells(_ line: String) -> [String]? {
        guard !line.hasPrefix("    "), !line.hasPrefix("\t") else { return nil }
        let text = line.trimmingCharacters(in: .whitespaces)
        var cells = [String](), cell = "", escaped = false, hasPipe = false
        for character in text {
            if escaped {
                cell.append(character); escaped = false
            } else if character == "\\" {
                cell.append(character); escaped = true
            } else if character == "|" {
                cells.append(cell.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\|", with: "|")); cell = ""; hasPipe = true
            } else { cell.append(character) }
        }
        guard hasPipe else { return nil }
        cells.append(cell.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\|", with: "|"))
        if text.hasPrefix("|") { cells.removeFirst() }
        // An escaped final pipe belongs to the last cell.
        if cells.last == "" && text.hasSuffix("|") { cells.removeLast() }
        return cells.isEmpty ? nil : cells
    }

    private static func tableHeader(_ lines: [String], at index: Int) -> (cells: [String], alignments: [NSTextAlignment])? {
        guard index + 1 < lines.count, let cells = tableCells(lines[index]), let delimiters = tableCells(lines[index + 1]),
              cells.count == delimiters.count, delimiters.allSatisfy({ matches("^:?-+:?$", $0) != nil }) else { return nil }
        return (cells, delimiters.map { $0.hasSuffix(":") ? ($0.hasPrefix(":") ? .center : .right) : .left })
    }

    private static func setextLevel(_ line: String) -> Int? {
        if matches("^ {0,3}=+[ \\t]*$", line) != nil { return 1 }
        if matches("^ {0,3}-+[ \\t]*$", line) != nil { return 2 }
        return nil
    }

    private static func isDivider(_ line: String) -> Bool {
        matches("^ {0,3}([*_-])(?:[ \\t]*\\1){2,}[ \\t]*$", line) != nil
    }

    private static func parse(_ source: String, depth: Int = 0) -> [Block] {
        var lines = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        if let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            lines.removeSubrange(0..<first)
        }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        // Chat replies sometimes wrap an entire Markdown answer in a mislabeled code fence.
        // Only unwrap a complete outer fence when its contents show clear Markdown structure.
        if lines.count >= 3, let opening = fence(lines[0]), closesFence(lines[lines.count - 1], marker: opening.marker),
           !lines.dropFirst().dropLast().contains(where: { closesFence($0, marker: opening.marker) }) {
            let body = Array(lines.dropFirst().dropLast())
            let markdownStructure = body.contains { matches("^(#{1,6} |[-*+] \\*\\*|\\*\\*[^*]+\\*\\*$)", $0) != nil }
            let plainWrapper = ["", "md", "markdown", "text", "plaintext", "vbnet"].contains(opening.info)
                && !body.contains(where: { fence($0) != nil })
            // A longer, sometimes mislabeled outer fence can wrap Markdown containing
            // Codex action blocks. Require a heading and a shorter inner prompt fence.
            let promptWrapper = body.contains { matches("^ {0,3}#{1,6} +", $0) != nil }
                && body.contains { line in
                    guard let inner = fence(line) else { return false }
                    return inner.info == "codex-prompt" && inner.marker.count < opening.marker.count
                }
            if markdownStructure && (plainWrapper || promptWrapper) { lines = body }
        }
        var blocks: [Block] = []
        var index = 0
        func isSpecial(_ at: Int) -> Bool {
            let line = lines[at]
            return matches("^\\s*(#{1,6} |[-*+] |[0-9]+[.)] |>|```|~~~)", line) != nil
                || matches("^\\*\\*([^*]+)\\*\\*\\s*$", line) != nil || isDivider(line) || tableHeader(lines, at: at) != nil
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
            if let opening = fence(line) {
                index += 1
                var body: [String] = []
                while index < lines.count && !closesFence(lines[index], marker: opening.marker) { body.append(lines[index]); index += 1 }
                if index < lines.count { index += 1 }
                if opening.info == "codex-prompt" {
                    // ChatGPT Meetings exports these as prose action items.
                    if !body.joined().trimmingCharacters(in: .whitespaces).isEmpty {
                        blocks.append(Block(kind: .list(0, nil), text: joined(body)))
                    }
                } else {
                    blocks.append(Block(kind: .code, text: body.joined(separator: "\n")))
                }
                continue
            }
            // Indented code starts a block; a nested list marker remains a list item.
            let followsList: Bool
            if let last = blocks.last {
                switch last.kind { case .list, .task: followsList = true; default: followsList = false }
            } else { followsList = false }
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
            if let header = tableHeader(lines, at: index) {
                var rows = [header.cells]; index += 2
                while index < lines.count, !isSpecial(index), let cells = tableCells(lines[index]) {
                    rows.append(cells); index += 1
                }
                blocks.append(Block(kind: .table(rows, header.alignments), text: "")); continue
            }
            if let heading = matches("^ {0,3}(#{1,6}) +(.+?)(?: +#+)?$", line) {
                blocks.append(Block(kind: .heading(heading[1].count), text: heading[2])); index += 1; continue
            }
            if let heading = matches("^\\*\\*([^*]+)\\*\\*\\s*$", line) {
                blocks.append(Block(kind: .heading(2), text: heading[1])); index += 1; continue
            }
            if isDivider(line) {
                blocks.append(Block(kind: .divider, text: "────────────")); index += 1; continue
            }
            if let item = matches("^(\\s*)(?:([-*+])|([0-9]+)[.)]) +(.+)$", line) {
                let indent = item[1].replacingOccurrences(of: "\t", with: "    ").count
                var body = [item[4]]
                index += 1
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty && !isSpecial(index) {
                    body.append(lines[index]); index += 1
                }
                if let task = matches("^\\[([ xX])\\] +(.+)$", joined(body)) {
                    blocks.append(Block(kind: .task(indent, task[1].lowercased() == "x"), text: task[2]))
                } else {
                    blocks.append(Block(kind: .list(indent, Int(item[3])), text: joined(body)))
                }
                continue
            }
            if let quote = matches("^ {0,3}>[ \\t]?(.*)$", line) {
                var body = [quote[1]]; index += 1
                while index < lines.count, let next = matches("^ {0,3}>[ \\t]?(.*)$", lines[index]) { body.append(next[1]); index += 1 }
                // Bound recursion for deeply nested pasted quotes.
                var quoted = depth < 16 ? parse(body.joined(separator: "\n"), depth: depth + 1) : [Block(kind: .paragraph, text: joined(body))]
                for index in quoted.indices { quoted[index].quoteDepth += 1 }
                blocks.append(contentsOf: quoted); continue
            }
            var body = [line]; index += 1
            while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty && setextLevel(lines[index]) == nil && !isSpecial(index) { body.append(lines[index]); index += 1 }
            if index < lines.count, let level = setextLevel(lines[index]) {
                blocks.append(Block(kind: .heading(level), text: joined(body))); index += 1
            } else {
                blocks.append(Block(kind: .paragraph, text: joined(body)))
            }
        }
        return blocks
    }
}
