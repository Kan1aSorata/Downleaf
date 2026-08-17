import XCTest
@testable import Downleaf

final class LivePreviewParserTests: XCTestCase {
    private func element(
        _ kind: LivePreviewElement.Kind,
        in source: String
    ) -> LivePreviewElement? {
        LivePreviewParser.elements(in: source).first { $0.kind == kind }
    }

    func testHeadingMarkerCoversHashesAndFollowingSpaces() throws {
        let source = "## 标题文本"
        let heading = try XCTUnwrap(element(.heading(level: 2), in: source))
        XCTAssertEqual(heading.markerRanges, [NSRange(location: 0, length: 3)])
        XCTAssertEqual(heading.range, NSRange(location: 0, length: (source as NSString).length))
    }

    func testStrongEmphasisAndStrikethroughMarkers() throws {
        let source = "普通 **加粗** 和 *斜体* 和 ~~删除~~"
        let strong = try XCTUnwrap(element(.strong, in: source))
        XCTAssertEqual(strong.markerRanges.map(\.length), [2, 2])
        let emphasis = try XCTUnwrap(element(.emphasis, in: source))
        XCTAssertEqual(emphasis.markerRanges.map(\.length), [1, 1])
        let strike = try XCTUnwrap(element(.strikethrough, in: source))
        XCTAssertEqual(strike.markerRanges.map(\.length), [2, 2])
    }

    func testInlineCodeBackticksAreMarkers() throws {
        let source = "看 `code` 这里"
        let code = try XCTUnwrap(element(.inlineCode, in: source))
        let text = source as NSString
        XCTAssertEqual(text.substring(with: code.markerRanges[0]), "`")
        XCTAssertEqual(text.substring(with: code.markerRanges[1]), "`")
    }

    func testLinkHidesBracketsAndURL() throws {
        let source = "前文 [官网](https://example.com) 后文"
        let link = try XCTUnwrap(element(.link, in: source))
        let text = source as NSString
        XCTAssertEqual(text.substring(with: link.markerRanges[0]), "[")
        XCTAssertEqual(text.substring(with: link.markerRanges[1]), "](https://example.com)")
    }

    func testEmphasisInsideInlineCodeIsIgnored() {
        let source = "`a *not italic* b`"
        XCTAssertNil(element(.emphasis, in: source))
    }

    func testInlineSyntaxInsideFencedCodeBlockIsIgnored() {
        let source = "```\n**不加粗** `no` # 不是标题\n```"
        let elements = LivePreviewParser.elements(in: source)
        XCTAssertTrue(elements.isEmpty, "\(elements)")
    }

    func testBoldItalicDoNotMatchAcrossWords() {
        XCTAssertNil(element(.emphasis, in: "snake_case_identifier 保持原样"))
        XCTAssertNil(element(.strong, in: "a ** b ** c"))
    }

    func testElementsAreSortedBySourceLocation() {
        let source = "# 标题\n\n**粗** 和 *斜* 与 `码`"
        let locations = LivePreviewParser.elements(in: source).map(\.range.location)
        XCTAssertEqual(locations, locations.sorted())
    }
}
