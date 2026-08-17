import Foundation

enum MarkdownRenderer {
    static func html(for source: String, headings: [OutlineHeading]) -> String {
        let body = renderBlocks(source, headings: headings)
        return """
        <!doctype html>
        <html lang="zh-Hans">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src file: data:; style-src 'unsafe-inline'; script-src 'none';">
          <style>
            :root { color-scheme: light dark; }
            * { box-sizing: border-box; }
            html { scroll-behavior: smooth; }
            body {
              max-width: 820px;
              margin: 0 auto;
              padding: 58px 54px 160px;
              color: light-dark(#262626, #dedede);
              background: light-dark(#fbfbfb, #171717);
              font: 15px/1.78 -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", sans-serif;
              -webkit-font-smoothing: antialiased;
            }
            h1, h2, h3, h4, h5, h6 { color: light-dark(#111, #f0f0f0); line-height: 1.3; letter-spacing: -0.012em; scroll-margin-top: 38px; }
            h1 { margin: 0 0 1.4em; font-size: 2em; }
            h2 { margin: 2.2em 0 .75em; font-size: 1.55em; }
            h3 { margin: 1.9em 0 .65em; font-size: 1.25em; }
            h4, h5, h6 { margin: 1.65em 0 .55em; font-size: 1em; }
            p { margin: 0 0 1.05em; }
            a { color: light-dark(#1475d1, #72aaf7); text-decoration-thickness: 1px; text-underline-offset: 3px; }
            ul, ol { margin: .4em 0 1.2em; padding-left: 1.55em; }
            li { margin: .2em 0; }
            blockquote { margin: 1.35em 0; padding: .1em 0 .1em 1.1em; color: light-dark(#666, #aaa); border-left: 3px solid light-dark(#d1d1d1, #444); }
            code { padding: .13em .34em; border-radius: 4px; background: light-dark(#efefef, #292929); font: .9em/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
            pre { overflow-x: auto; margin: 1.35em 0; padding: 16px 18px; border: 1px solid light-dark(#e5e5e5, #333); border-radius: 8px; background: light-dark(#f4f4f4, #121212); }
            pre code { padding: 0; background: transparent; }
            hr { margin: 2.4em 0; border: 0; border-top: 1px solid light-dark(#ddd, #3a3a3a); }
            img { max-width: 100%; height: auto; border-radius: 6px; }
            .task { list-style: none; margin-left: -1.4em; }
            .task::before { display: inline-block; width: 1.4em; content: "☐"; color: light-dark(#777, #aaa); }
            .task.done::before { content: "☑"; color: #2aa66b; }
            @media (max-width: 700px) { body { padding: 38px 28px 120px; } }
          </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    private static func renderBlocks(_ source: String, headings: [OutlineHeading]) -> String {
        let lines = source.components(separatedBy: "\n")
        var output: [String] = []
        var paragraph: [String] = []
        var listType: String?
        var inCodeFence = false
        var codeLines: [String] = []
        var headingIndex = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let content = inline(paragraph.joined(separator: "\n"))
                .replacingOccurrences(of: "\n", with: "<br>\n")
            output.append("<p>\(content)</p>")
            paragraph.removeAll(keepingCapacity: true)
        }

        func closeList() {
            guard let currentListType = listType else { return }
            output.append("</\(currentListType)>")
            listType = nil
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph()
                closeList()
                if inCodeFence {
                    output.append("<pre><code>\(escape(codeLines.joined(separator: "\n")))</code></pre>")
                    codeLines.removeAll(keepingCapacity: true)
                }
                inCodeFence.toggle()
                continue
            }

            if inCodeFence {
                codeLines.append(line)
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                closeList()
                let anchor = headingIndex < headings.count ? headings[headingIndex].anchor : "heading-\(headingIndex)"
                output.append("<h\(heading.level) id=\"\(anchor)\">\(inline(heading.title))</h\(heading.level)>")
                headingIndex += 1
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                closeList()
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                closeList()
                output.append("<hr>")
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                closeList()
                let content = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                output.append("<blockquote>\(inline(content))</blockquote>")
                continue
            }

            if let item = unorderedListItem(trimmed) {
                flushParagraph()
                if listType != "ul" {
                    closeList()
                    output.append("<ul>")
                    listType = "ul"
                }
                output.append(renderListItem(item))
                continue
            }

            if let item = orderedListItem(trimmed) {
                flushParagraph()
                if listType != "ol" {
                    closeList()
                    output.append("<ol>")
                    listType = "ol"
                }
                output.append("<li>\(inline(item))</li>")
                continue
            }

            closeList()
            paragraph.append(trimmed)
        }

        flushParagraph()
        closeList()
        if inCodeFence {
            output.append("<pre><code>\(escape(codeLines.joined(separator: "\n")))</code></pre>")
        }
        return output.joined(separator: "\n")
    }

    private static func parseHeading(_ line: String) -> (level: Int, title: String)? {
        let count = line.prefix { $0 == "#" }.count
        guard (1...6).contains(count) else { return nil }
        let index = line.index(line.startIndex, offsetBy: count)
        guard index < line.endIndex, line[index].isWhitespace else { return nil }
        var title = line[index...].trimmingCharacters(in: .whitespaces)
        while title.last == "#" {
            title.removeLast()
            title = title.trimmingCharacters(in: .whitespaces)
        }
        return title.isEmpty ? nil : (count, title)
    }

    private static func unorderedListItem(_ line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    private static func orderedListItem(_ line: String) -> String? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let number = line[..<dot]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        let afterDot = line.index(after: dot)
        guard afterDot < line.endIndex, line[afterDot].isWhitespace else { return nil }
        return String(line[afterDot...].trimmingCharacters(in: .whitespaces))
    }

    private static func renderListItem(_ item: String) -> String {
        let lower = item.lowercased()
        if lower.hasPrefix("[ ] ") {
            return "<li class=\"task\">\(inline(String(item.dropFirst(4))))</li>"
        }
        if lower.hasPrefix("[x] ") {
            return "<li class=\"task done\">\(inline(String(item.dropFirst(4))))</li>"
        }
        return "<li>\(inline(item))</li>"
    }

    private static func inline<S: StringProtocol>(_ raw: S) -> String {
        var text = escape(String(raw))
        text = replace(text, pattern: #"!\[([^\]]*)\]\(([^\s\)]+)\)"#) { captures in
            let source = captures[2]
            guard isSafeImageSource(source) else { return captures[0] }
            return "<img src=\"\(source)\" alt=\"\(captures[1])\">"
        }
        text = replace(text, pattern: #"\[([^\]]+)\]\(([^\s\)]+)\)"#) { captures in
            "<a href=\"\(captures[2])\">\(captures[1])</a>"
        }
        text = replace(text, pattern: #"`([^`]+)`"#) { captures in
            "<code>\(captures[1])</code>"
        }
        text = replace(text, pattern: #"\*\*([^*]+)\*\*"#) { captures in
            "<strong>\(captures[1])</strong>"
        }
        text = replace(text, pattern: #"__([^_]+)__"#) { captures in
            "<strong>\(captures[1])</strong>"
        }
        text = replace(text, pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#) { captures in
            "<em>\(captures[1])</em>"
        }
        text = replace(text, pattern: #"(?<!_)_([^_]+)_(?!_)"#) { captures in
            "<em>\(captures[1])</em>"
        }
        return text
    }

    private static func replace(_ source: String, pattern: String, transform: ([String]) -> String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return source }
        let matches = expression.matches(in: source, range: NSRange(location: 0, length: (source as NSString).length))
        guard !matches.isEmpty else { return source }

        let mutable = NSMutableString(string: source)
        for match in matches.reversed() {
            let captures = (0..<match.numberOfRanges).map { index -> String in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : (source as NSString).substring(with: range)
            }
            mutable.replaceCharacters(in: match.range, with: transform(captures))
        }
        return mutable as String
    }

    private static func isSafeImageSource(_ source: String) -> Bool {
        let lower = source.lowercased()
        return !(lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("javascript:"))
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
