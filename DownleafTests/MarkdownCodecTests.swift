import Foundation
import XCTest
@testable import Downleaf

final class MarkdownCodecTests: XCTestCase {
    func testUTF8BOMAndCRLFRoundTrip() throws {
        let original = Data([0xEF, 0xBB, 0xBF]) + Data("# 标题\r\n正文\r\n".utf8)
        let decoded = try MarkdownCodec.decode(original)

        XCTAssertEqual(decoded.text, "# 标题\n正文\n")
        XCTAssertEqual(decoded.format, MarkdownFileFormat(encoding: .utf8WithBOM, lineEnding: .crlf))
        XCTAssertEqual(try MarkdownCodec.encode(decoded.text, format: decoded.format), original)
    }

    func testUTF16LittleEndianRoundTrip() throws {
        let text = "标题\r正文"
        let format = MarkdownFileFormat(encoding: .utf16LittleEndian, lineEnding: .cr)
        let encoded = try MarkdownCodec.encode(text.replacingOccurrences(of: "\r", with: "\n"), format: format)
        let decoded = try MarkdownCodec.decode(encoded)

        XCTAssertEqual(decoded.text, "标题\n正文")
        XCTAssertEqual(decoded.format, format)
    }

    func testLatin1FailsWhenTextCannotBeRepresented() {
        let format = MarkdownFileFormat(encoding: .isoLatin1, lineEnding: .lf)
        XCTAssertThrowsError(try MarkdownCodec.encode("中文", format: format))
    }
}
