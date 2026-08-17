import AppKit
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

        XCTAssertEqual(controller.children.count, 2)
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

    private func makeController() -> DocumentContentViewController {
        let controller = DocumentContentViewController()
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 1_000, height: 700)
        let source = "# 第一章\n\n正文\n\n## 第二章\n\n更多正文"
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
}
