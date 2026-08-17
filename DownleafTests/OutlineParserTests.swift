import XCTest
@testable import Downleaf

final class OutlineParserTests: XCTestCase {
    func testParsesATXAndSetextHeadings() {
        let source = """
        # 第一章
        正文

        第二章
        ------

        ### 跳级标题
        """

        let headings = MarkdownOutlineParser.headings(in: source)

        XCTAssertEqual(headings.map(\.level), [1, 2, 3])
        XCTAssertEqual(headings.map(\.title), ["第一章", "第二章", "跳级标题"])
        XCTAssertEqual(headings.map(\.lineNumber), [1, 4, 7])
    }

    func testIgnoresHeadingsInsideCodeFences() {
        let source = """
        # 可见
        ```swift
        # 不应出现
        ```
        ## 仍然可见
        """

        XCTAssertEqual(MarkdownOutlineParser.headings(in: source).map(\.title), ["可见", "仍然可见"])
    }

    func testDuplicateTitlesReceiveDistinctIDsAndAnchors() {
        let headings = MarkdownOutlineParser.headings(in: "# 相同\n\n# 相同")

        XCTAssertEqual(headings.count, 2)
        XCTAssertNotEqual(headings[0].id, headings[1].id)
        XCTAssertNotEqual(headings[0].anchor, headings[1].anchor)
    }
}
