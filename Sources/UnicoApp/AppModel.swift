import AppKit
import SwiftUI
import UniformTypeIdentifiers
import UnicoCore

enum AppPhase { case start, scanning, results }
enum AppPrompt: String, Identifiable { case wholeDisk, manualScan, clean; var id: String { rawValue } }

@MainActor
final class AppModel: ObservableObject {
    @Published var phase: AppPhase = .start
    @Published var roots: [URL] = []
    @Published var progress = ScanProgress()
    @Published var groups: [DuplicateGroup] = []
    @Published var selectedGroupID: String?
    @Published var previewID: String?
    @Published var issues: [ScanIssue] = []
    @Published var showIssues = false
    @Published var prompt: AppPrompt?
    @Published var language = AppLanguage.initial() {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "Unico.language")
            onLanguageChange?()
        }
    }
    var onLanguageChange: (() -> Void)?
    @Published var notice: AppMessage?
    @Published var isWholeDisk = false
    var scopeTitle: String {
        isWholeDisk ? t("本机内置磁盘", "Internal disk") : (roots.count == 1 ? location(roots[0]) : t("\(roots.count) 个文件夹", "\(englishCount(roots.count, "folder"))"))
    }
    func t(_ chinese: String, _ english: String) -> String { language.text(chinese, english) }
    func size(_ bytes: Int64) -> String { fileSize(bytes, language: language) }
    func date(_ value: Date) -> String {
        value.formatted(.dateTime.year().month(.abbreviated).day().hour().minute().locale(language.locale))
    }
    func location(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let names = ["Desktop": t("桌面", "Desktop"), "Documents": t("文稿", "Documents"),
                     "Downloads": t("下载", "Downloads"), "Pictures": t("图片", "Pictures"),
                     "Movies": t("影片", "Movies"), "Music": t("音乐", "Music")]
        if url.path == home.path { return t("个人文件夹", "Home") }
        if url.deletingLastPathComponent().path == home.path { return names[url.lastPathComponent] ?? url.lastPathComponent }
        return url.lastPathComponent
    }
    func shortPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if url.path.hasPrefix(home + "/") { return "~/" + url.path.dropFirst(home.count + 1) }
        return url.path
    }
    @Published var scanned = 0
    @Published var excluded = 0
    @Published var isCleaning = false
    @Published var cleanProcessed = 0
    @Published var cleanTotal = 0
    @Published var cancelling = false
    @Published var isDropTarget = false
    private var token: CancellationToken?
    private var scopedURLs: [URL] = []
    private(set) var confirmedScanRoots: [URL] = []

    var selectedCount: Int { groups.reduce(0) { $0 + $1.selectedIDs.count } }
    var selectedBytes: Int64 { groups.reduce(0) { $0 + $1.selectedBytes } }
    var currentGroup: DuplicateGroup? { groups.first { $0.id == selectedGroupID } }
    var previewFile: FileRecord? {
        guard let group = currentGroup else { return nil }
        return group.files.first { $0.id == previewID } ?? group.files.first { $0.id == group.keeperID }
    }
    var busy: Bool { phase == .scanning || isCleaning }

    func addFolders() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = t("选择要查找重复文件的文件夹", "Choose folders to scan")
        panel.prompt = t("添加文件夹", "Add folders")
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.treatsFilePackagesAsDirectories = true
        panel.showsHiddenFiles = true
        panel.allowsMultipleSelection = true; panel.canCreateDirectories = false
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in self?.add(panel.urls) }
        }
        if let window = NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    func add(_ urls: [URL]) {
        guard !busy else { return }
        notice = nil
        var rejected = 0
        for url in urls {
            let normalized = URL(fileURLWithPath: url.resolvingSymlinksInPath().standardizedFileURL.path, isDirectory: true)
            guard let stamp = try? FileStamp.read(normalized), stamp.isDirectory else { rejected += 1; continue }
            do {
                // Only structural checks here; location/type exclusions are overridden after confirmation.
                try FileSafety.verifyAncestors(normalized, confirmedRoots: [normalized])
                _ = try FileManager.default.contentsOfDirectory(atPath: normalized.path)
            } catch { rejected += 1; continue }
            if roots.contains(where: { $0.path == normalized.path }) { continue }
            if url.startAccessingSecurityScopedResource() { scopedURLs.append(url) }
            roots.append(normalized)
        }
        if rejected > 0 { notice = AppMessage("\(rejected) 个位置未添加：请选择可读取的文件夹。", "\(englishCount(rejected, "location")) not added. Choose readable folders.") }
    }

    func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !busy else { return false }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                let url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else { url = item as? URL }
                if let url { Task { @MainActor in self?.add([url]) } }
            }
        }
        return true
    }

    func start(wholeDisk: Bool = false, confirmed: Bool = false) {
        guard !busy else { return }
        if !wholeDisk && !confirmed {
            if !roots.isEmpty { prompt = .manualScan }
            return
        }
        let scanRoots = wholeDisk ? [URL(fileURLWithPath: "/", isDirectory: true)] : roots
        guard !scanRoots.isEmpty else { return }
        groups = []; issues = []; selectedGroupID = nil; previewID = nil
        progress = ScanProgress(); notice = nil; cancelling = false
        isWholeDisk = wholeDisk
        phase = .scanning
        confirmedScanRoots = wholeDisk ? [] : scanRoots
        let confirmedRoots = confirmedScanRoots
        let cancellation = CancellationToken(); token = cancellation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let result = try Scanner().scan(roots: scanRoots, wholeDisk: wholeDisk, confirmedRoots: confirmedRoots, token: cancellation) { status in
                    DispatchQueue.main.async { self?.progress = status }
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.groups = result.groups; self.scanned = result.scanned
                    self.issues = result.issues; self.excluded = result.excluded
                    self.selectedGroupID = result.groups.first?.id
                    self.phase = .results; self.cancelling = false; self.token = nil
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.phase = .start; self.cancelling = false; self.token = nil
                    self.notice = cancellation.isCancelled ? AppMessage("扫描已取消，未改动任何文件。", "Scan cancelled. No files were changed.") : AppMessage(error.localizedDescription, englishErrorDescription(error))
                }
            }
        }
    }

    func cancel() { cancelling = true; token?.cancel() }
    func reset() {
        guard !busy else { return }
        phase = .start; notice = nil; groups = []; issues = []; confirmedScanRoots = []
    }
    func keep(_ file: FileRecord) {
        guard !isCleaning, let index = groups.firstIndex(where: { $0.id == selectedGroupID }) else { return }
        groups[index].keep(file)
    }
    func toggle(_ file: FileRecord) {
        guard !isCleaning, let index = groups.firstIndex(where: { $0.id == selectedGroupID }), groups[index].keeperID != file.id else { return }
        if groups[index].selectedIDs.contains(file.id) { groups[index].selectedIDs.remove(file.id) }
        else { groups[index].selectedIDs.insert(file.id) }
    }
    func toggleAll() {
        guard !isCleaning else { return }
        let clear = selectedCount > 0
        for index in groups.indices {
            groups[index].selectedIDs = clear ? [] : Set(groups[index].files.filter { $0.id != groups[index].keeperID }.map(\.id))
        }
    }
    func clean() {
        guard !isCleaning, selectedCount > 0 else { return }
        isCleaning = true; cancelling = false; cleanProcessed = 0; cleanTotal = selectedCount
        let snapshot = groups
        let confirmedRoots = confirmedScanRoots
        let cancellation = CancellationToken(); token = cancellation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Cleaner().clean(groups: snapshot, confirmedRoots: confirmedRoots, token: cancellation) { processed in
                DispatchQueue.main.async { self?.cleanProcessed = processed }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                for index in self.groups.indices {
                    self.groups[index].files.removeAll { result.trashed[$0.id] != nil }
                    self.groups[index].selectedIDs = []
                }
                let failedPaths = Set(result.issues.map(\.path))
                self.groups.removeAll { group in
                    group.files.count < 2 || failedPaths.contains(group.id) || group.files.contains { failedPaths.contains($0.id) }
                }
                if !self.groups.contains(where: { $0.id == self.selectedGroupID }) { self.selectedGroupID = self.groups.first?.id }
                self.previewID = nil
                self.issues.append(contentsOf: result.issues)
                let chinese = "\(result.cancelled ? "已停止。" : "")已将 \(result.trashed.count) 个文件移到废纸篓" + (result.issues.isEmpty ? "。" : "，\(result.issues.count) 项未清理，相关组需重新扫描。") + (result.trashed.isEmpty ? "未移动的文件保持原样。" : "可在 Finder 中恢复。清空废纸篓后才释放空间。")
                let english = (result.cancelled ? "Stopped. " : "") + "Moved \(englishCount(result.trashed.count, "file")) to Trash. " + (result.issues.isEmpty ? "" : "\(englishCount(result.issues.count, "item")) not cleaned; scan those groups again. ") + (result.trashed.isEmpty ? "Other files are unchanged." : "Restore them in Finder. Space is freed only after emptying Trash.")
                self.notice = AppMessage(chinese, english)
                self.isCleaning = false; self.cancelling = false; self.token = nil
            }
        }
    }
}

func fileSize(_ bytes: Int64, language: AppLanguage = .chinese) -> String {
    guard bytes >= 1000 else { return language.text("\(bytes) 字节", "\(bytes) \(bytes == 1 ? "byte" : "bytes")") }
    let units = ["KB", "MB", "GB", "TB", "PB"]
    var amount = Double(bytes) / 1000
    var unit = 0
    while amount >= 1000 && unit < units.count - 1 { amount /= 1000; unit += 1 }
    return amount.formatted(.number.precision(.fractionLength(0...1)).locale(language.locale)) + " " + units[unit]
}
