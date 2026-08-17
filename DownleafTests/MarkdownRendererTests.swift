import XCTest
@testable import Downleaf

final class MarkdownRendererTests: XCTestCase {
    func testEscapesRawHTMLAndRendersCommonBlocks() {
        let source = """
        # 标题

        <script>alert('x')</script>

        - [x] 完成
        """
        let headings = MarkdownOutlineParser.headings(in: source)
        let html = MarkdownRenderer.html(for: source, headings: headings)

        XCTAssertTrue(html.contains("id=\"heading-0\""))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertFalse(html.contains("<script>alert"))
        XCTAssertTrue(html.contains("class=\"task done\""))
    }

    func testDoesNotRenderRemoteImages() {
        let html = MarkdownRenderer.html(for: "![远程](https://example.com/a.png)", headings: [])
        XCTAssertFalse(html.contains("<img src=\"https://"))
    }

    func testPreservesSingleLineBreaksInsideParagraphs() {
        let source = "第一行\n**第二行**\n第三行\n\n新的段落"
        let html = MarkdownRenderer.html(for: source, headings: [])

        XCTAssertTrue(html.contains("<p>第一行<br>\n<strong>第二行</strong><br>\n第三行</p>"))
        XCTAssertTrue(html.contains("<p>新的段落</p>"))
        XCTAssertFalse(html.contains("第三行<br>\n<br>\n新的段落"))
    }

    func testPreviewContentSecurityPolicyBlocksNetworkLoads() {
        let html = MarkdownRenderer.html(for: "# 安全预览", headings: [])

        XCTAssertTrue(html.contains("default-src 'none'"))
        XCTAssertTrue(html.contains("img-src file: data:"))
        XCTAssertFalse(html.contains("img-src http:"))
        XCTAssertFalse(html.contains("img-src https:"))
    }
}
