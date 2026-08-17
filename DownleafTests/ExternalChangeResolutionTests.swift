import XCTest
@testable import Downleaf

final class ExternalChangeResolutionTests: XCTestCase {
    func testIdenticalDiskContentIsIgnored() {
        XCTAssertEqual(
            ExternalChangeResolution.decide(diskText: "a", memoryText: "a", isEdited: true, resolvedConflictText: nil),
            .ignore
        )
        XCTAssertEqual(
            ExternalChangeResolution.decide(diskText: "a", memoryText: "a", isEdited: false, resolvedConflictText: nil),
            .ignore
        )
    }

    func testCleanDocumentAutoReloads() {
        XCTAssertEqual(
            ExternalChangeResolution.decide(diskText: "新内容", memoryText: "旧内容", isEdited: false, resolvedConflictText: nil),
            .autoReload
        )
    }

    func testDirtyDocumentAsksUserInsteadOfSilentOverwrite() {
        XCTAssertEqual(
            ExternalChangeResolution.decide(diskText: "磁盘版", memoryText: "本地版", isEdited: true, resolvedConflictText: nil),
            .askUser
        )
    }

    func testSameDiskVersionDoesNotPromptTwiceAfterUserKeptLocal() {
        XCTAssertEqual(
            ExternalChangeResolution.decide(diskText: "磁盘版", memoryText: "本地版", isEdited: true, resolvedConflictText: "磁盘版"),
            .ignore
        )
        XCTAssertEqual(
            ExternalChangeResolution.decide(diskText: "更新的磁盘版", memoryText: "本地版", isEdited: true, resolvedConflictText: "磁盘版"),
            .askUser
        )
    }
}
