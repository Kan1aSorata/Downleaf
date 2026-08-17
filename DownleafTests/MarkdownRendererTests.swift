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

    func testRendersTableWithAlignmentAndInlineStyles() {
        let source = """
        | 名前 | 数 | 備考 |
        |:---|---:|:---:|
        | **強調** | 12 | ~~取消~~ |
        | 質問 | 3 | `code` |
        """
        let html = MarkdownRenderer.html(for: source, headings: [])

        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th style=\"text-align: left\">名前</th>"))
        XCTAssertTrue(html.contains("<th style=\"text-align: right\">数</th>"))
        XCTAssertTrue(html.contains("<th style=\"text-align: center\">備考</th>"))
        XCTAssertTrue(html.contains("<td style=\"text-align: left\"><strong>強調</strong></td>"))
        XCTAssertTrue(html.contains("<del>取消</del>"))
        XCTAssertTrue(html.contains("<code>code</code>"))
        XCTAssertEqual(html.components(separatedBy: "<tr>").count - 1, 3)
    }

    func testPipeLineWithoutSeparatorIsNotATable() {
        let html = MarkdownRenderer.html(for: "| 只是一行 | 文本 |\n普通段落", headings: [])
        XCTAssertFalse(html.contains("<table>"))
    }

    func testStrikethroughAndAutolink() {
        let html = MarkdownRenderer.html(for: "支持 ~~删除线~~ 和 <https://example.com/a?b=1>", headings: [])
        XCTAssertTrue(html.contains("<del>删除线</del>"))
        XCTAssertTrue(html.contains("<a href=\"https://example.com/a?b=1\">https://example.com/a?b=1</a>"))
    }

    func testConsecutiveQuoteLinesMergeIntoOneBlockquote() {
        let source = "> 第一行\n> 第二行\n>\n> 新段落"
        let html = MarkdownRenderer.html(for: source, headings: [])
        XCTAssertEqual(html.components(separatedBy: "<blockquote>").count - 1, 1)
        XCTAssertTrue(html.contains("<p>第一行<br>\n第二行</p>"))
        XCTAssertTrue(html.contains("<p>新段落</p>"))
    }

    func testLocalImageRenders() {
        let html = MarkdownRenderer.html(for: "![图](assets/a.png)", headings: [])
        XCTAssertTrue(html.contains("<img src=\"assets/a.png\" alt=\"图\">"))
    }
}
