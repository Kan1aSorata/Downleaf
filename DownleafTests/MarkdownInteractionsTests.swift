import XCTest
@testable import Downleaf

final class MarkdownInteractionsTests: XCTestCase {
    func testClickOnCheckboxTokenReturnsStateCharacterRange() {
        let text = "- [ ] 买牛奶\n- [x] 已完成" as NSString
        let bracketIndex = ("- [" as NSString).length - 1

        let range = MarkdownInteractions.checkboxStateRange(in: text, at: bracketIndex)
        XCTAssertEqual(range, NSRange(location: 3, length: 1))
        XCTAssertEqual(text.substring(with: range!), " ")

        let secondLineStart = ("- [ ] 买牛奶\n" as NSString).length
        let doneRange = MarkdownInteractions.checkboxStateRange(in: text, at: secondLineStart + 3)
        XCTAssertEqual(text.substring(with: doneRange!), "x")
    }

    func testClickOutsideCheckboxTokenDoesNotToggle() {
        let text = "- [ ] 买牛奶" as NSString
        XCTAssertNil(MarkdownInteractions.checkboxStateRange(in: text, at: text.length - 1))
        XCTAssertNil(MarkdownInteractions.checkboxStateRange(in: "普通 [ ] 文本" as NSString, at: 4))
    }

    func testLinkTargetDetection() {
        let text = "看 [官网](https://example.com/a) 和 <https://b.dev> 以及 https://bare.link/x 结束" as NSString
        let inlineIndex = ("看 [官" as NSString).length
        XCTAssertEqual(MarkdownInteractions.linkTarget(in: text, at: inlineIndex), "https://example.com/a")

        let autolinkIndex = text.range(of: "b.dev").location
        XCTAssertEqual(MarkdownInteractions.linkTarget(in: text, at: autolinkIndex), "https://b.dev")

        let bareIndex = text.range(of: "bare.link").location
        XCTAssertEqual(MarkdownInteractions.linkTarget(in: text, at: bareIndex), "https://bare.link/x")

        XCTAssertNil(MarkdownInteractions.linkTarget(in: text, at: 0))
    }

    func testLinkClassification() {
        XCTAssertEqual(
            MarkdownInteractions.classifyLink("https://example.com", baseURL: nil),
            .external(URL(string: "https://example.com")!)
        )
        XCTAssertEqual(
            MarkdownInteractions.classifyLink("#section-2", baseURL: nil),
            .anchor("section-2")
        )
        XCTAssertEqual(
            MarkdownInteractions.classifyLink("docs/readme.md", baseURL: URL(fileURLWithPath: "/tmp")),
            .relativeFile("docs/readme.md")
        )
        XCTAssertNil(MarkdownInteractions.classifyLink("ftp://weird", baseURL: nil))
    }
}
