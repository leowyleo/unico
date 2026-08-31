import XCTest
import UniformTypeIdentifiers
import UnicoCore
@testable import UnicoApp

final class AppModelTests: XCTestCase {
    func testLanguageDefaultsAndSavedPreference() throws {
        let suite = "Unico-Language-Test-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["zh-Hans-CN"], forKey: "AppleLanguages")
        XCTAssertEqual(AppLanguage.initial(defaults: defaults), .english)
        defaults.set("invalid", forKey: "Unico.language")
        XCTAssertEqual(AppLanguage.initial(defaults: defaults), .english)
        defaults.set("zh-Hans", forKey: "Unico.language")
        XCTAssertEqual(AppLanguage.initial(defaults: defaults), .chinese)
        defaults.set("en", forKey: "Unico.language")
        XCTAssertEqual(AppLanguage.initial(defaults: defaults), .english)
        XCTAssertEqual(fileSize(1, language: .english), "1 byte")
        XCTAssertEqual(fileSize(2, language: .english), "2 bytes")
        XCTAssertEqual(fileSize(2, language: .chinese), "2 字节")
    }

    @MainActor
    func testLanguageSwitchPreservesScanAndSelection() throws {
        let saved = UserDefaults.standard.object(forKey: "Unico.language")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "Unico.language") }
            else { UserDefaults.standard.removeObject(forKey: "Unico.language") }
        }
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Unico-Language-Test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a.txt", "b.txt"] { try Data("same".utf8).write(to: root.appendingPathComponent(name)) }
        let model = AppModel()
        model.groups = try Scanner().scan(roots: [root], token: CancellationToken()).groups
        let group = try XCTUnwrap(model.groups.first)
        model.selectedGroupID = group.id
        model.previewID = group.files.last?.id
        model.phase = .results
        model.notice = AppMessage("扫描已取消", "Scan cancelled")
        model.language = .english
        XCTAssertEqual(model.notice?.text(model.language), "Scan cancelled")
        XCTAssertEqual(AppLanguage.initial(), .english)
        XCTAssertEqual(model.groups.first?.keeperID, group.keeperID)
        XCTAssertEqual(model.groups.first?.selectedIDs, group.selectedIDs)
        XCTAssertEqual(model.previewID, group.files.last?.id)
        model.language = .chinese
        XCTAssertEqual(model.notice?.text(model.language), "扫描已取消")
        XCTAssertEqual(model.selectedCount, 1)
        let issue = ScanIssue(path: root.path, error: ScanError.changed)
        XCTAssertTrue(issue.englishReason.contains("changed"))
        XCTAssertTrue(issue.reason.contains("变化"))
    }

    @MainActor
    func testDroppedFolderProviderAddsRealDirectoryAndRejectsFiles() async throws {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Unico-Drop-Test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel()
        let provider = NSItemProvider(item: root as NSURL, typeIdentifier: UTType.fileURL.identifier)
        XCTAssertTrue(model.receiveDrop([provider]))
        for _ in 0..<50 {
            if !model.roots.isEmpty { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(model.roots.map(\.path), [root.standardizedFileURL.path])
        let file = root.appendingPathComponent("not-a-folder.txt")
        try Data("test".utf8).write(to: file)
        model.add([file, root])
        XCTAssertEqual(model.roots.count, 1)
        XCTAssertNotNil(model.notice)
    }

    @MainActor
    func testChangedGroupRemovedAfterFailedCleanup() async throws {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Unico-Model-Test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a.txt", "b.txt"] { try Data("same contents".utf8).write(to: root.appendingPathComponent(name)) }
        let groups = try Scanner().scan(roots: [root], token: CancellationToken()).groups
        let group = try XCTUnwrap(groups.first)
        let candidate = URL(fileURLWithPath: try XCTUnwrap(group.selectedIDs.first))
        try Data("changed contents".utf8).write(to: candidate)
        let model = AppModel()
        model.phase = .results; model.groups = groups; model.selectedGroupID = group.id
        model.clean()
        for _ in 0..<100 {
            if !model.isCleaning { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(model.isCleaning)
        XCTAssertTrue(model.groups.isEmpty, "A known stale group must not remain eligible for cleanup")
        XCTAssertEqual(model.selectedCount, 0)
        XCTAssertEqual(model.issues.count, 1)
        XCTAssertTrue(model.notice?.chinese.contains("需重新扫描") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: candidate.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: group.keeperID))
    }
    @MainActor
    func testManualProjectRequiresConfirmationAndGrantDoesNotLeak() async throws {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Unico-Confirmation-Test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Package.swift", "copy.swift"] { try Data("same".utf8).write(to: root.appendingPathComponent(name)) }
        let model = AppModel()
        model.add([root])
        XCTAssertEqual(model.roots.map(\.path), [root.path])
        XCTAssertNil(model.notice)
        model.start()
        XCTAssertEqual(model.prompt, .manualScan)
        XCTAssertEqual(model.phase, .start)
        XCTAssertTrue(model.confirmedScanRoots.isEmpty)
        model.prompt = nil // Cancel leaves both scan and permission untouched.
        XCTAssertTrue(model.groups.isEmpty)
        model.start(confirmed: true)
        for _ in 0..<100 {
            if !model.busy { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.groups.count, 1)
        XCTAssertEqual(model.confirmedScanRoots.map(\.path), [root.path])
        model.roots.removeAll()
        XCTAssertEqual(model.confirmedScanRoots.map(\.path), [root.path], "Cleanup scope belongs to the scan snapshot")
        model.reset()
        XCTAssertTrue(model.confirmedScanRoots.isEmpty)
    }

}
