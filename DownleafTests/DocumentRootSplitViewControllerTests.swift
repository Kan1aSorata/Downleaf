import AppKit
import XCTest
@testable import Downleaf

@MainActor
final class DocumentRootSplitViewControllerTests: XCTestCase {
    func testWindowContentFillsAFullscreenSizedResize() throws {
        let document = MarkdownDocument()
        let controller = DocumentWindowController(document: document)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }

        let fullscreenContentSize = NSSize(width: 1_800, height: 1_000)
        window.setContentSize(fullscreenContentSize)
        window.layoutIfNeeded()

        XCTAssertEqual(window.contentView?.bounds.size, fullscreenContentSize)
        XCTAssertEqual(window.contentViewController?.view.frame.size, fullscreenContentSize)
    }

    func testOutlineExpansionKeepsRightEdgeFixedAndMovesDividerLeft() {
        let splitWidth: CGFloat = 1_180
        let dividerThickness: CGFloat = 1
        let widths: [CGFloat] = [0.5, 40, 120, 260, 360]

        let positions = widths.map {
            DocumentRootSplitViewController.outlineDividerPosition(
                splitWidth: splitWidth,
                dividerThickness: dividerThickness,
                outlineWidth: $0
            )
        }

        for index in positions.indices {
            XCTAssertEqual(
                positions[index] + dividerThickness + widths[index],
                splitWidth,
                accuracy: 0.001,
                "The outline's right edge must remain pinned to the window while it expands."
            )

            if index > positions.startIndex {
                XCTAssertLessThan(
                    positions[index],
                    positions[index - 1],
                    "Increasing the outline width must move only its left divider toward the left."
                )
            }
        }
    }
}
