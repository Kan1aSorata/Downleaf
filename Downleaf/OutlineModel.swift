import Foundation

struct OutlineHeading: Hashable, Sendable {
    let id: String
    let level: Int
    let title: String
    let sourceRange: NSRange
    let lineNumber: Int
    let anchor: String
}

enum MarkdownOutlineParser {
    static func headings(in source: String) -> [OutlineHeading] {
        let nsSource = source as NSString
        var headings: [OutlineHeading] = []
        var offset = 0
        var lineNumber = 1
        var fence: Character?
        var previousLine: (text: String, range: NSRange, lineNumber: Int)?

        while offset < nsSource.length {
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            nsSource.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: offset, length: 0))
            let range = NSRange(location: lineStart, length: contentsEnd - lineStart)
            let line = nsSource.substring(with: range)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let marker = fenceMarker(in: trimmed) {
                if fence == nil {
                    fence = marker
                } else if fence == marker {
                    fence = nil
                }
                previousLine = nil
                lineNumber += 1
                offset = lineEnd
                continue
            }

            if fence != nil {
                previousLine = nil
                lineNumber += 1
                offset = lineEnd
                continue
            }

            if let atx = parseATXHeading(trimmed) {
                let heading = makeHeading(level: atx.level, title: atx.title, range: range, lineNumber: lineNumber, ordinal: headings.count)
                headings.append(heading)
                previousLine = nil
            } else if let setextLevel = setextHeadingLevel(trimmed),
                      let previous = previousLine,
                      !previous.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let title = previous.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let heading = makeHeading(level: setextLevel, title: title, range: previous.range, lineNumber: previous.lineNumber, ordinal: headings.count)
                headings.append(heading)
                previousLine = nil
            } else {
                previousLine = (line, range, lineNumber)
            }

            lineNumber += 1
            offset = lineEnd
        }

        return headings
    }

    private static func fenceMarker(in line: String) -> Character? {
        guard let first = line.first, first == "`" || first == "~" else { return nil }
        let count = line.prefix { $0 == first }.count
        return count >= 3 ? first : nil
    }

    private static func parseATXHeading(_ line: String) -> (level: Int, title: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let markerEnd = line.index(line.startIndex, offsetBy: hashes)
        guard markerEnd < line.endIndex, line[markerEnd].isWhitespace else { return nil }

        var title = line[markerEnd...].trimmingCharacters(in: .whitespaces)
        while title.last == "#" {
            title.removeLast()
            title = title.trimmingCharacters(in: .whitespaces)
        }
        guard !title.isEmpty else { return nil }
        return (hashes, stripInlineMarkdown(title))
    }

    private static func setextHeadingLevel(_ line: String) -> Int? {
        guard line.count >= 3 else { return nil }
        if line.allSatisfy({ $0 == "=" || $0.isWhitespace }), line.contains("=") {
            return 1
        }
        if line.allSatisfy({ $0 == "-" || $0.isWhitespace }), line.contains("-") {
            return 2
        }
        return nil
    }

    private static func stripInlineMarkdown(_ title: String) -> String {
        title
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private static func makeHeading(level: Int, title: String, range: NSRange, lineNumber: Int, ordinal: Int) -> OutlineHeading {
        let anchor = "heading-\(ordinal)"
        return OutlineHeading(
            id: "\(range.location)-\(level)-\(title)",
            level: level,
            title: title,
            sourceRange: range,
            lineNumber: lineNumber,
            anchor: anchor
        )
    }
}
