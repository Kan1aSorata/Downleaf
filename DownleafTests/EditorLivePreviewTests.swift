import AppKit
import XCTest
@testable import Downleaf

@MainActor
final class EditorLivePreviewTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppPreferences.registerDefaults()
    }

    private func makeEditor(_ text: String) -> EditorViewController {
        let editor = EditorViewController()
        editor.forcedLivePreview = true
        editor.loadViewIfNeeded()
        editor.setInitialText(text)
        return editor
    }

    func testTableRowsRenderMonospacedWithDimmedPipes() throws {
        let source = "| 名前 | 例 |\n|---|---|\n| 質問 | どこ |"
        let editor = makeEditor(source)
        let storage = try XCTUnwrap(editor.textView.textStorage)
        let text = source as NSString

        let cellOffset = ("| " as NSString).length
        let cellFont = try XCTUnwrap(storage.attribute(.font, at: cellOffset, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(cellFont.isFixedPitch, "表格单元格应使用等宽字体")

        let pipeColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(pipeColor, .tertiaryLabelColor, "竖线应弱化显示")

        let separatorLocation = text.range(of: "|---|").location
        let separatorColor = storage.attribute(.foregroundColor, at: separatorLocation + 1, effectiveRange: nil) as? NSColor
        XCTAssertEqual(separatorColor, .tertiaryLabelColor, "分隔行应整体弱化")
    }

    func testTableStylingIsSkippedInSourceMode() throws {
        let editor = EditorViewController()
        editor.forcedLivePreview = false
        editor.loadViewIfNeeded()
        editor.setInitialText("| a | b |\n|---|---|")
        let storage = try XCTUnwrap(editor.textView.textStorage)
        let font = try XCTUnwrap(storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)
        XCTAssertFalse(font.isFixedPitch, "源码模式不应用表格等宽样式")
    }

    func testBoldContentRendersWithBoldTrait() throws {
        let editor = makeEditor("正文 **重点** 正文")
        let storage = try XCTUnwrap(editor.textView.textStorage)
        let location = ("正文 **" as NSString).length
        let font = try XCTUnwrap(storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }

    func testAlignTopScrollsCounterpartOffsetToVisibleTop() {
        let longText = (1...300).map { "第 \($0) 行内容" }.joined(separator: "\n")
        let editor = makeEditor(longText)
        editor.view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        editor.view.layoutSubtreeIfNeeded()

        let targetOffset = (longText as NSString).range(of: "第 150 行内容").location
        editor.alignTop(toCharacterOffset: targetOffset)

        let topOffset = editor.topVisibleCharacterOffset()
        let text = longText as NSString
        let topLine = text.substring(with: text.lineRange(for: NSRange(location: min(topOffset, text.length - 1), length: 0)))
        XCTAssertTrue(
            topLine.contains("第 149 行") || topLine.contains("第 150 行") || topLine.contains("第 151 行"),
            "顶部行应接近第 150 行，实际是：\(topLine)"
        )
    }
}
