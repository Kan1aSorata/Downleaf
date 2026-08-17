import Foundation

/// 实时预览中一个可折叠语法元素：`range` 为含标记的完整范围，
/// `markerRanges` 为默认隐藏、光标进入时恢复显示的语法标记。
struct LivePreviewElement: Equatable {
    enum Kind: Equatable {
        case heading(level: Int)
        case strong
        case emphasis
        case strikethrough
        case inlineCode
        case link
    }

    let kind: Kind
    let range: NSRange
    let markerRanges: [NSRange]
}

/// 纯函数解析器：只负责定位元素与标记范围，不做任何样式决策。
/// 与阅读渲染器无关，服务于编辑器的显示层。
enum LivePreviewParser {
    static func elements(in source: String) -> [LivePreviewElement] {
        let text = source as NSString
        let fullRange = NSRange(location: 0, length: text.length)
        guard fullRange.length > 0 else { return [] }

        var elements: [LivePreviewElement] = []
        // 围栏代码块内不解析任何行内语法；行内代码内不解析强调与链接。
        var exclusions: [NSRange] = matches(#"(?m)^\s*```[\s\S]*?(^\s*```\s*$|\z)"#, in: text, range: fullRange).map(\.range)

        for match in matches(#"(?m)^(#{1,6})([ \t]+)\S.*$"#, in: text, range: fullRange) {
            guard !intersectsAny(match.range, exclusions) else { continue }
            let level = match.range(at: 1).length
            let marker = NSRange(location: match.range.location, length: match.range(at: 1).length + match.range(at: 2).length)
            elements.append(LivePreviewElement(kind: .heading(level: level), range: match.range, markerRanges: [marker]))
        }

        for match in matches(#"`[^`\n]+`"#, in: text, range: fullRange) {
            guard !intersectsAny(match.range, exclusions) else { continue }
            elements.append(LivePreviewElement(
                kind: .inlineCode,
                range: match.range,
                markerRanges: edgeMarkers(of: match.range, width: 1)
            ))
            exclusions.append(match.range)
        }

        for match in matches(#"\[([^\[\]\n]+)\]\(([^()\n]+)\)"#, in: text, range: fullRange) {
            guard !intersectsAny(match.range, exclusions) else { continue }
            let textRange = match.range(at: 1)
            let leading = NSRange(location: match.range.location, length: 1)
            let trailing = NSRange(
                location: textRange.upperBound,
                length: match.range.upperBound - textRange.upperBound
            )
            elements.append(LivePreviewElement(kind: .link, range: match.range, markerRanges: [leading, trailing]))
            exclusions.append(match.range)
        }

        for (pattern, kind, width) in [
            (#"\*\*(?=\S)(?:[^*\n]|\*(?!\*))+?(?<=\S)\*\*"#, LivePreviewElement.Kind.strong, 2),
            (#"__(?=\S)[^_\n]+?(?<=\S)__"#, .strong, 2),
            (#"~~(?=\S)[^~\n]+?(?<=\S)~~"#, .strikethrough, 2),
            (#"(?<![*\w])\*(?=[^\s*])[^*\n]+?(?<=[^\s*])\*(?![*\w])"#, .emphasis, 1),
            (#"(?<![_\w])_(?=[^\s_])[^_\n]+?(?<=[^\s_])_(?![_\w])"#, .emphasis, 1)
        ] {
            for match in matches(pattern, in: text, range: fullRange) {
                guard !intersectsAny(match.range, exclusions) else { continue }
                elements.append(LivePreviewElement(
                    kind: kind,
                    range: match.range,
                    markerRanges: edgeMarkers(of: match.range, width: width)
                ))
                exclusions.append(match.range)
            }
        }

        return elements.sorted { $0.range.location < $1.range.location }
    }

    private static func matches(_ pattern: String, in text: NSString, range: NSRange) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in: text as String, range: range)
    }

    private static func edgeMarkers(of range: NSRange, width: Int) -> [NSRange] {
        [
            NSRange(location: range.location, length: width),
            NSRange(location: range.upperBound - width, length: width)
        ]
    }

    private static func intersectsAny(_ range: NSRange, _ ranges: [NSRange]) -> Bool {
        ranges.contains { NSIntersectionRange($0, range).length > 0 }
    }
}
