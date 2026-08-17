import Foundation

/// 编辑器内 Markdown 交互的纯命中判定：复选框点击与 ⌘点击链接。
/// 只做文本几何计算，不做任何 UI 动作，便于单元测试。
enum MarkdownInteractions {
    /// 若 `index` 落在所在行的任务复选框 “[ ]”/“[x]” 标记上，返回括号中间那个状态字符的范围。
    static func checkboxStateRange(in text: NSString, at index: Int) -> NSRange? {
        guard index <= text.length else { return nil }
        let lineRange = text.lineRange(for: NSRange(location: min(index, max(0, text.length - 1)), length: 0))
        let line = text.substring(with: lineRange)
        guard let match = line.range(of: #"^\s*[-*+]\s+\[[ xX]\]"#, options: .regularExpression) else {
            return nil
        }
        let matchEnd = lineRange.location + (String(line[..<match.upperBound]) as NSString).length
        let boxRange = NSRange(location: matchEnd - 3, length: 3) // "[x]"
        guard index >= boxRange.location, index <= boxRange.upperBound else { return nil }
        return NSRange(location: boxRange.location + 1, length: 1)
    }

    /// 若 `index` 落在行内链接上，返回链接目标字符串（`[t](url)`、`<url>` 或裸 URL）。
    static func linkTarget(in text: NSString, at index: Int) -> String? {
        guard text.length > 0, index <= text.length else { return nil }
        let lineRange = text.lineRange(for: NSRange(location: min(index, text.length - 1), length: 0))
        let line = text.substring(with: lineRange)
        let localIndex = index - lineRange.location

        let patterns: [(pattern: String, urlGroup: Int)] = [
            (#"\[[^\]\n]+\]\(([^()\s]+)\)"#, 1),
            (#"<(https?://[^>\s]+)>"#, 1),
            (#"(?<![(<])\bhttps?://[^\s()<>]+"#, 0)
        ]
        let lineNS = line as NSString
        for (pattern, urlGroup) in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = expression.matches(in: line, range: NSRange(location: 0, length: lineNS.length))
            for match in matches where localIndex >= match.range.location && localIndex <= match.range.upperBound {
                let urlRange = match.range(at: urlGroup)
                guard urlRange.location != NSNotFound else { continue }
                return lineNS.substring(with: urlRange)
            }
        }
        return nil
    }

    /// 按 spec 5.4 对链接目标分类。
    enum LinkKind: Equatable {
        case anchor(String)
        case external(URL)
        case relativeFile(String)
    }

    static func classifyLink(_ target: String, baseURL: URL?) -> LinkKind? {
        if target.hasPrefix("#") {
            return .anchor(String(target.dropFirst()))
        }
        if let url = URL(string: target),
           let scheme = url.scheme?.lowercased(),
           ["http", "https", "mailto"].contains(scheme) {
            return .external(url)
        }
        guard !target.contains("://") else { return nil }
        return .relativeFile(target)
    }
}
