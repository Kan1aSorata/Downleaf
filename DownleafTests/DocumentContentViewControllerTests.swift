import AppKit
import WebKit
import XCTest
@testable import Downleaf

@MainActor
final class DocumentContentViewControllerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppPreferences.registerDefaults()
    }

    func testModeTransitionsKeepExactlyTheExpectedSurfacesVisible() {
        let controller = makeController()

        assertSurfaces(controller, mode: .editor, editorVisible: true, previewVisible: false)

        controller.setMode(.split)
        assertSurfaces(controller, mode: .split, editorVisible: true, previewVisible: true)

        controller.setMode(.reader)
        assertSurfaces(controller, mode: .reader, editorVisible: false, previewVisible: true)

        controller.setMode(.editor)
        assertSurfaces(controller, mode: .editor, editorVisible: true, previewVisible: false)
    }

    func testRepeatedModeSwitchingDoesNotDuplicateChildControllersOrSurfaces() {
        let controller = makeController()
        let stableLayout = controller.view.subviews[0]
        let transitions: [DocumentMode] = [
            .split, .reader, .editor,
            .reader, .split, .editor,
            .split, .reader, .split, .editor
        ]

        for mode in transitions {
            controller.setMode(mode)
            controller.view.layoutSubtreeIfNeeded()
            XCTAssertEqual(controller.view.subviews.count, 1)
            XCTAssertTrue(controller.view.subviews.first === stableLayout)
            XCTAssertEqual(controller.mode, mode)
        }

        XCTAssertEqual(controller.children.count, 3)
        assertSurfaces(controller, mode: .editor, editorVisible: true, previewVisible: false)
    }

    func testContainerResizeKeepsTheActiveModeGeometryAfterPreviewWasCreated() {
        let controller = makeController()

        controller.setMode(.split)
        controller.setMode(.editor)
        controller.view.frame.size.width = 720
        controller.synchronizeLayoutAfterContainerResize()
        assertSurfaces(controller, mode: .editor, editorVisible: true, previewVisible: false)

        controller.view.frame.size.width = 1_180
        controller.synchronizeLayoutAfterContainerResize()
        assertSurfaces(controller, mode: .editor, editorVisible: true, previewVisible: false)

        controller.setMode(.reader)
        controller.view.frame.size.width = 860
        controller.synchronizeLayoutAfterContainerResize()
        assertSurfaces(controller, mode: .reader, editorVisible: false, previewVisible: true)

        controller.setMode(.split)
        controller.view.frame.size.width = 1_060
        controller.synchronizeLayoutAfterContainerResize()
        assertSurfaces(controller, mode: .split, editorVisible: true, previewVisible: true)
    }

    func testPreviewCreatedAtZeroSizeFillsItsHostAfterWindowLayout() throws {
        let controller = DocumentContentViewController()
        controller.loadViewIfNeeded()
        let source = "# 预览标题\n\n预览正文"
        controller.update(
            source: source,
            headings: MarkdownOutlineParser.headings(in: source),
            baseURL: nil,
            preserving: "heading-0"
        )

        controller.setMode(.reader)
        controller.view.frame = NSRect(x: 0, y: 0, width: 1_000, height: 700)
        controller.synchronizeLayoutAfterContainerResize()

        let webView = try XCTUnwrap(firstDescendant(of: controller.view, as: WKWebView.self))
        let hostView = try XCTUnwrap(webView.superview)
        XCTAssertEqual(webView.frame, hostView.bounds)
        XCTAssertGreaterThan(webView.frame.width, 1)
        XCTAssertGreaterThan(webView.frame.height, 1)
    }

    func testReaderPreviewLoadsTheCurrentMarkdown() async throws {
        let controller = DocumentContentViewController()
        controller.loadViewIfNeeded()
        let source = "# 可见的预览标题\n\n可见的预览正文"
        controller.update(
            source: source,
            headings: MarkdownOutlineParser.headings(in: source),
            baseURL: nil,
            preserving: "heading-0"
        )

        controller.setMode(.reader)
        controller.view.frame = NSRect(x: 0, y: 0, width: 1_000, height: 700)
        controller.synchronizeLayoutAfterContainerResize()

        let webView = try XCTUnwrap(firstDescendant(of: controller.view, as: WKWebView.self))
        var renderedText = ""
        var lastError: Error?
        for _ in 0..<40 {
            do {
                if let text = try await webView.evaluateJavaScript("document.body.innerText") as? String {
                    renderedText = text
                    if text.contains("可见的预览标题") {
                        break
                    }
                }
            } catch {
                lastError = error
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        let diagnostic = "text=\(renderedText), url=\(String(describing: webView.url)), loading=\(webView.isLoading), error=\(String(describing: lastError))"
        XCTAssertTrue(renderedText.contains("可见的预览标题"), diagnostic)
        XCTAssertTrue(renderedText.contains("可见的预览正文"), diagnostic)
    }

    func testPreviewAnchorIsEncodedAsSafeJavaScriptStringLiteral() throws {
        XCTAssertEqual(
            PreviewViewController.javaScriptStringLiteral(for: "heading-0"),
            #""heading-0""#
        )

        let unsafeLookingAnchor = #"chapter\"'; alert(1); //"#
        let literal = try XCTUnwrap(
            PreviewViewController.javaScriptStringLiteral(for: unsafeLookingAnchor)
        )
        let decoded = try JSONSerialization.jsonObject(
            with: Data(literal.utf8),
            options: [.fragmentsAllowed]
        ) as? String
        XCTAssertEqual(decoded, unsafeLookingAnchor)
    }

    func testSplitShowsEditableLivePreviewWithCurrentText() {
        let controller = makeController()
        controller.setMode(.split)
        controller.view.layoutSubtreeIfNeeded()

        let previewTextView = controller.previewEditorViewController.textView
        XCTAssertTrue(previewTextView.isDescendant(of: controller.view))
        XCTAssertTrue(previewTextView.isEditable)
        XCTAssertEqual(previewTextView.string, controller.editorViewController.textView.string)
    }

    func testEditingRightPaneMirrorsToLeftPaneAndReportsChange() {
        let controller = makeController()
        controller.setMode(.split)
        controller.view.layoutSubtreeIfNeeded()

        var reportedText: String?
        controller.previewEditorViewController.onTextChange = { [weak controller] text in
            reportedText = text
            if let controller {
                controller.mirrorEditedSource(text, from: controller.previewEditorViewController)
            }
        }

        let previewTextView = controller.previewEditorViewController.textView
        previewTextView.setSelectedRange(NSRange(location: 0, length: 0))
        previewTextView.insertText("新增", replacementRange: NSRange(location: 0, length: 0))

        XCTAssertEqual(reportedText, previewTextView.string)
        XCTAssertEqual(controller.editorViewController.textView.string, previewTextView.string)
    }

    func testEditingLeftPaneMirrorsToRightPane() {
        let controller = makeController()
        controller.setMode(.split)
        controller.view.layoutSubtreeIfNeeded()

        let editorTextView = controller.editorViewController.textView
        controller.editorViewController.onTextChange = { [weak controller] text in
            if let controller {
                controller.mirrorEditedSource(text, from: controller.editorViewController)
            }
        }
        editorTextView.setSelectedRange(NSRange(location: 0, length: 0))
        editorTextView.insertText("左侧", replacementRange: NSRange(location: 0, length: 0))

        XCTAssertEqual(controller.previewEditorViewController.textView.string, editorTextView.string)
    }

    private func makeController() -> DocumentContentViewController {
        let controller = DocumentContentViewController()
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 1_000, height: 700)
        let source = "# 第一章\n\n正文\n\n## 第二章\n\n更多正文"
        controller.editorViewController.setInitialText(source)
        controller.update(
            source: source,
            headings: MarkdownOutlineParser.headings(in: source),
            baseURL: nil,
            preserving: "heading-0"
        )
        controller.view.layoutSubtreeIfNeeded()
        return controller
    }

    private func assertSurfaces(
        _ controller: DocumentContentViewController,
        mode: DocumentMode,
        editorVisible: Bool,
        previewVisible: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(controller.mode, mode, file: file, line: line)
        XCTAssertEqual(
            controller.isEditorSurfaceVisible,
            editorVisible,
            "编辑区域可见状态不符合 \(mode)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            controller.isPreviewSurfaceVisible,
            previewVisible,
            "预览区域可见状态不符合 \(mode)",
            file: file,
            line: line
        )
        XCTAssertEqual(controller.view.subviews.count, 1, file: file, line: line)
    }

    private func firstDescendant<T: NSView>(of view: NSView, as type: T.Type) -> T? {
        for subview in view.subviews {
            if let match = subview as? T {
                return match
            }
            if let match = firstDescendant(of: subview, as: type) {
                return match
            }
        }
        return nil
    }
}
