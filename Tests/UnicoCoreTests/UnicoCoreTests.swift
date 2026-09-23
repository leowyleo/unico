import XCTest
import Foundation
import Darwin
@testable import UnicoCore

final class UnicoCoreTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Unico-Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { if let root { try? FileManager.default.removeItem(at: root) } }
    @discardableResult
    func file(_ path: String, _ content: String = "same contents") throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
        return url
    }
    func scan(_ roots: [URL]? = nil) throws -> ScanResult {
        try Scanner().scan(roots: roots ?? [root], token: CancellationToken())
    }

    func testExactContentAcrossDirectoriesWithDifferentNames() throws {
        let first = try file("a/first.txt")
        let second = try file("b/renamed.txt")
        try file("b/first.txt", "other content") // same length, different bytes
        try file("empty1.txt", ""); try file("empty2.txt", "")
        let result = try scan()
        XCTAssertEqual(result.groups.count, 2)
        XCTAssertEqual(Set(result.groups[0].files.map(\.url)), Set([first, second]))
        XCTAssertEqual(result.groups[0].selectedIDs.count, 1)
        XCTAssertEqual(result.groups.last?.redundantBytes, 0)
    }

    func testOnlyIncludedFileTypesAppearInFutureScans() throws {
        let imageA = try file("a.jpg")
        let imageB = try file("b.jpg")
        let textA = try file("a.txt")
        let textB = try file("b.txt")
        let result = try Scanner().scan(roots: [root], scanRules: ScanRules(includedFileTypes: [.documents]), token: CancellationToken())
        XCTAssertEqual(FileTypeCategory.category(for: imageA), .media)
        XCTAssertEqual(FileTypeCategory.category(for: textA), .documents)
        XCTAssertEqual(result.scanned, 2)
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(Set(result.groups[0].files.map(\.url)), Set([textA, textB]))
        XCTAssertFalse(result.groups[0].files.contains { $0.url == imageA || $0.url == imageB })
    }

    func testOtherFilesAreOffByDefaultAndCanBeIncluded() throws {
        try file("a.bin")
        try file("b.bin")
        XCTAssertTrue(try scan().groups.isEmpty)

        let result = try Scanner().scan(roots: [root], scanRules: ScanRules(includedFileTypes: [.other]), token: CancellationToken())
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups.first?.selectedIDs.count, 1)
    }

    func testScanRulesFilterHiddenSmallAndIgnoredFiles() throws {
        let visibleA = try file("visible-a.txt")
        let visibleB = try file("visible-b.txt")
        try file(".hidden-a.txt")
        try file(".hidden-b.txt")
        try file("ignored/a.txt")
        try file("ignored/b.txt")
        let rules = ScanRules(
            includedFileTypes: [.documents],
            skipHiddenFiles: true,
            minimumFileSize: 8,
            ignoredPaths: [root.appendingPathComponent("ignored").path]
        )
        let result = try Scanner().scan(roots: [root], scanRules: rules, token: CancellationToken())
        XCTAssertEqual(Set(result.groups.flatMap(\.files).map(\.url)), Set([visibleA, visibleB]))

        let unrestricted = ScanRules(includedFileTypes: [.documents], skipHiddenFiles: false)
        let hiddenResult = try Scanner().scan(roots: [root], scanRules: unrestricted, token: CancellationToken())
        let hiddenFiles = Set(hiddenResult.groups.flatMap(\.files).map(\.url))
        XCTAssertTrue(hiddenFiles.isSuperset(of: [root.appendingPathComponent(".hidden-a.txt"), root.appendingPathComponent(".hidden-b.txt")]))
    }

    func testOverlappingRootsSymlinksHardlinksAndProtectedPackages() throws {
        try file("folder/original.txt"); try file("folder/copy.txt")
        let linked = try file("hard-source.txt", "link data")
        XCTAssertEqual(link(linked.path, root.appendingPathComponent("hard-copy.txt").path), 0)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias"), withDestinationURL: root.appendingPathComponent("folder"))
        try file("Photos.photoslibrary/inside"); try file("Test.app/inside")
        try file("Library/inside"); try file("repository/.git/inside")
        let result = try scan([root, root.appendingPathComponent("folder"), root])
        XCTAssertEqual(result.groups.count, 1, "scanned=\(result.scanned), excluded=\(result.excluded), issues=\(result.issues)")
        let group = try XCTUnwrap(result.groups.first)
        XCTAssertEqual(group.files.count, 2)
        XCTAssertEqual(result.scanned, 2)
        XCTAssertGreaterThanOrEqual(result.excluded, 7)
        let explicit = try scan([root.appendingPathComponent("Photos.photoslibrary")])
        XCTAssertTrue(explicit.groups.isEmpty)
        XCTAssertEqual(explicit.issues.count, 1)
    }

    func testLatestModificationIsRecommendedAndKeeperCanBeChanged() throws {
        let first = try file("a.txt")
        let second = try file("b.txt")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000_000_000)], ofItemAtPath: second.path)
        var group = try XCTUnwrap(scan().groups.first)
        XCTAssertEqual(group.keeperID, second.path)
        group.keep(try XCTUnwrap(group.files.first { $0.url == first }))
        XCTAssertEqual(group.keeperID, first.path)
        XCTAssertFalse(group.selectedIDs.contains(first.path))
        XCTAssertTrue(group.selectedIDs.contains(second.path))
    }

    func testOldestAndManualKeepRules() throws {
        let oldest = try file("old.swift")
        let newest = try file("new.swift")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000_000_000)], ofItemAtPath: newest.path)

        let scriptRules = ScanRules(includedFileTypes: [.scripts])
        let oldestRule = try XCTUnwrap(Scanner().scan(roots: [root], scanRules: scriptRules, defaultKeepRule: .oldestModified, token: CancellationToken()).groups.first)
        XCTAssertEqual(oldestRule.keeperID, oldest.path)
        XCTAssertEqual(oldestRule.selectedIDs, [newest.path])

        let manual = try XCTUnwrap(Scanner().scan(roots: [root], scanRules: scriptRules, defaultKeepRule: .manual, token: CancellationToken()).groups.first)
        XCTAssertEqual(manual.keeperID, newest.path)
        XCTAssertTrue(manual.selectedIDs.isEmpty)
    }

    func testExcludedLeafDoesNotSuppressFollowingDirectory() throws {
        try file("archive.app", "package-like leaf")
        try file("folder/a.txt"); try file("folder/b.txt")
        let result = try scan()
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.scanned, 2)
    }

    func testRegularDocumentsAreIncludedButDocumentPackageContentsAreNot() throws {
        try file("document.pages", "regular document bytes")
        try file("copy.pages", "regular document bytes")
        try file("Package.rtfd/inside.txt")
        try file("Package.rtfd/copy.txt")
        let result = try scan()
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.scanned, 2)
        XCTAssertEqual(result.groups.first?.files.first?.url.pathExtension, "pages")
    }

    func testCancellationBeforeAndDuringEnumeration() throws {
        try file("a.txt"); try file("b.txt")
        let pre = CancellationToken(); pre.cancel()
        XCTAssertThrowsError(try Scanner().scan(roots: [root], token: pre))
        let during = CancellationToken()
        XCTAssertThrowsError(try Scanner().scan(roots: [root], token: during) { _ in during.cancel() })
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("a.txt").path))
    }

    func testInternalVolumeModeFindsDuplicatesAndSkipsAppCaches() throws {
        try file("a.txt"); try file("b.txt")
        try file(".cache/one"); try file(".cache/two")
        let result = try Scanner().scan(roots: [root], wholeDisk: true, token: CancellationToken())
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.scanned, 2)
        XCTAssertGreaterThan(result.excluded, 0)
    }

    func testUnreadableFolderIsReported() throws {
        let locked = root.appendingPathComponent("locked")
        try file("locked/a.txt"); try file("locked/b.txt")
        XCTAssertEqual(chmod(locked.path, 0), 0)
        defer { chmod(locked.path, 0o700) }
        let result = try scan()
        XCTAssertTrue(result.groups.isEmpty)
        XCTAssertFalse(result.issues.isEmpty)
        let direct = try scan([locked])
        XCTAssertEqual(direct.issues.count, 1)
    }

    func testModifiedKeeperStopsCleanup() throws {
        try file("a.txt"); try file("b.txt")
        let group = try XCTUnwrap(scan().groups.first)
        try Data("modified file".utf8).write(to: URL(fileURLWithPath: group.keeperID))
        var calls = 0
        let result = Cleaner().clean(groups: [group], token: CancellationToken(), trash: { url in calls += 1; return url })
        XCTAssertEqual(calls, 0); XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 2)
    }

    func testReplacedSymlinkAndMovedFileAreNotCleaned() throws {
        try file("a.txt"); try file("b.txt")
        let group = try XCTUnwrap(scan().groups.first)
        let candidate = URL(fileURLWithPath: try XCTUnwrap(group.selectedIDs.first))
        let moved = root.appendingPathComponent("moved")
        try FileManager.default.moveItem(at: candidate, to: moved)
        try FileManager.default.createSymbolicLink(at: candidate, withDestinationURL: moved)
        var called = false
        let result = Cleaner().clean(groups: [group], token: CancellationToken(), trash: { url in called = true; return url })
        XCTAssertFalse(called); XCTAssertEqual(result.issues.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
    }

    func testWholeGroupSelectionAndTrashFailureNeverDelete() throws {
        try file("a.txt"); try file("b.txt")
        var group = try XCTUnwrap(scan().groups.first)
        group.selectedIDs.insert(group.keeperID)
        var calls = 0
        let blocked = Cleaner().clean(groups: [group], token: CancellationToken(), trash: { url in calls += 1; return url })
        XCTAssertEqual(calls, 0); XCTAssertFalse(blocked.issues.isEmpty)
        group.selectedIDs.remove(group.keeperID)
        let failed = Cleaner().clean(groups: [group], token: CancellationToken(), trash: { _ in throw CocoaError(.fileWriteNoPermission) })
        XCTAssertTrue(failed.trashed.isEmpty); XCTAssertEqual(failed.issues.count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 2)
    }

    func testCleanupDoesNotReportADeletedFileAsMovedToTrash() throws {
        try file("a.txt"); try file("b.txt")
        let group = try XCTUnwrap(scan().groups.first)
        let candidate = try XCTUnwrap(group.selectedIDs.first)

        // Reproduce the dangerous failure mode: the deletion callback removes the
        // file but does not return a real Trash destination.
        let result = Cleaner().clean(groups: [group], token: CancellationToken(), trash: { url in
            try FileManager.default.removeItem(at: url)
            return url
        })

        XCTAssertTrue(result.trashed.isEmpty)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: candidate))
    }

    func testCleanupCancellationDoesNotTrash() throws {
        try file("a.txt"); try file("b.txt")
        let token = CancellationToken(); token.cancel()
        let result = Cleaner().clean(groups: try scan().groups, token: token, trash: { _ in XCTFail("Must not trash"); return self.root })
        XCTAssertTrue(result.cancelled); XCTAssertTrue(result.trashed.isEmpty)
    }

    func testRealTrashAndRecoveryPreserveKeeper() throws {
        try file("a.txt"); try file("b.txt"); try file("c.txt")
        let group = try XCTUnwrap(scan().groups.first)
        let result = Cleaner().clean(groups: [group], token: CancellationToken())
        XCTAssertTrue(result.issues.isEmpty, "\(result.issues)")
        XCTAssertEqual(result.trashed.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: group.keeperID))
        XCTAssertEqual(try String(contentsOfFile: group.keeperID, encoding: .utf8), "same contents")
        for (original, destination) in result.trashed {
            XCTAssertFalse(FileManager.default.fileExists(atPath: original))
            XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
            try FileManager.default.moveItem(at: destination, to: URL(fileURLWithPath: original))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 3)
    }

    func testRuntimeUnknownConfigurationAndExecutableFilesAreExcluded() throws {
        let original = try file("Documents/report.txt")
        let copy = try file("Downloads/report-copy.TXT")
        for path in [".slock/cli-transport/slock", ".slock/cli-transport/raft",
                     ".unknown-app/data/a.txt", ".unknown-app/data/b.txt",
                     "runtime/slock", "runtime/raft", "config/a.json", "config/b.json",
                     "config/a.plist", "config/b.plist", "data/a.sqlite", "data/b.sqlite",
                     "unknown/a.bin", "unknown/b.bin", ".hidden.txt"] {
            try file(path)
        }
        let executable = try file("Downloads/executable.txt")
        XCTAssertEqual(chmod(executable.path, 0o755), 0)
        let hidden = try file("Downloads/hidden.txt")
        XCTAssertEqual(chflags(hidden.path, UInt32(UF_HIDDEN)), 0)
        for wholeDisk in [false, true] {
            let result = try Scanner().scan(roots: [root], wholeDisk: wholeDisk, token: CancellationToken())
            XCTAssertEqual(result.scanned, 2)
            XCTAssertEqual(result.groups.count, 1)
            XCTAssertEqual(Set(result.groups.flatMap(\.files).map(\.url)), Set([original, copy]))
        }
        let direct = try scan([root.appendingPathComponent(".slock/cli-transport")])
        XCTAssertTrue(direct.groups.isEmpty)
        XCTAssertEqual(direct.issues.count, 1)
    }

    func testProjectAssetsExcludedEvenWhenSubdirectoryExplicitlySelected() throws {
        try file("Documents/a.txt"); try file("Downloads/b.txt")
        try file("Project/package.json", "{}")
        try file("Project/assets/a.png"); try file("Project/assets/b.png")
        try file("Checkout/.git", "gitdir: elsewhere")
        try file("Checkout/docs/a.txt"); try file("Checkout/docs/b.txt")
        let result = try scan()
        XCTAssertEqual(result.scanned, 2)
        XCTAssertEqual(result.groups.count, 1)
        let direct = try scan([root.appendingPathComponent("Project/assets"), root.appendingPathComponent("Checkout/docs")])
        XCTAssertEqual(direct.scanned, 0)
        XCTAssertEqual(direct.issues.count, 2)
    }

    func testNewProjectMarkerAfterScanBlocksCleanup() throws {
        try file("Project/a.txt"); try file("Project/b.txt")
        let groups = try scan().groups
        XCTAssertEqual(groups.count, 1)
        try file("Project/package.json", "{}")
        var calls = 0
        let result = Cleaner().clean(groups: groups, token: CancellationToken(), trash: { url in calls += 1; return url })
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertTrue(result.trashed.isEmpty)
    }

    func testForgedRuntimeGroupCannotBypassCleanerProtection() throws {
        let a = try file(".slock/cli-transport/slock")
        let b = try file(".slock/cli-transport/raft")
        let group = DuplicateGroup(files: try [a, b].map { FileRecord(url: $0, stamp: try FileStamp.read($0)) })
        var calls = 0
        let result = Cleaner().clean(groups: [group], token: CancellationToken(), trash: { url in calls += 1; return url })
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertTrue(result.trashed.isEmpty)
    }
    func testConfirmedScopeNeverBypassesProtectedTypes() throws {
        let project = root.appendingPathComponent("Project")
        try file("Project/Package.swift", "manifest")
        let a = try file("Project/.runtime/a.bin", "binary data")
        let b = try file("Project/App.app/b", "binary data")
        XCTAssertEqual(chmod(b.path, 0o755), 0)
        try file("Project-other/Package.swift", "manifest")
        try file("Project-other/a.bin", "binary data")
        try FileManager.default.createSymbolicLink(at: project.appendingPathComponent("alias"), withDestinationURL: a)
        let hard = try file("Project/hard", "hardlink data")
        XCTAssertEqual(link(hard.path, project.appendingPathComponent("hard-copy").path), 0)
        let result = try Scanner().scan(roots: [root], confirmedRoots: [project], token: CancellationToken())
        XCTAssertTrue(result.groups.isEmpty)
        let direct = try Scanner().scan(roots: [a.deletingLastPathComponent()], confirmedRoots: [a.deletingLastPathComponent()], token: CancellationToken())
        XCTAssertEqual(direct.scanned, 0, "Selecting a project child must not override protected ancestors")
        let automatic = try Scanner().scan(roots: [root], wholeDisk: true, confirmedRoots: [project], token: CancellationToken())
        XCTAssertTrue(automatic.groups.isEmpty, "Whole-disk mode must ignore manual grants")
    }

    func testConfirmedProtectedCleanupUsesTrashAndCanBeRestored() throws {
        try file(".config/a.json"); try file(".config/b.json")
        let confirmed = root.appendingPathComponent(".config")
        let rules = ScanRules(includedFileTypes: [.scripts], skipHiddenFiles: false)
        let groups = try Scanner().scan(roots: [confirmed], confirmedRoots: [confirmed], scanRules: rules, token: CancellationToken()).groups
        let group = try XCTUnwrap(groups.first)
        let result = Cleaner().clean(groups: groups, confirmedRoots: [confirmed], scanRules: rules, token: CancellationToken())
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.trashed.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: group.keeperID))
        for (original, destination) in result.trashed {
            XCTAssertFalse(FileManager.default.fileExists(atPath: original))
            try FileManager.default.moveItem(at: destination, to: URL(fileURLWithPath: original))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: confirmed.path).count, 2)
    }

}
