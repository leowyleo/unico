import AppKit
import Foundation
import SwiftUI
import UnicoCore

enum MinimumFileSizeOption: String, CaseIterable, Identifiable {
    case unlimited, kilobytes100, megabytes1, megabytes10, megabytes100, custom

    var id: String { rawValue }
    var bytes: Int64? {
        switch self {
        case .unlimited: return 0
        case .kilobytes100: return 100_000
        case .megabytes1: return 1_000_000
        case .megabytes10: return 10_000_000
        case .megabytes100: return 100_000_000
        case .custom: return nil
        }
    }

    static func option(for bytes: Int64) -> Self {
        allCases.first { $0.bytes == bytes } ?? .custom
    }
}

@MainActor
final class ScanSettings: ObservableObject {
    private static let includedFileTypesKey = "Unico.includedFileTypes"
    private static let defaultKeepRuleKey = "Unico.defaultKeepRule"
    private static let skipHiddenFilesKey = "Unico.skipHiddenFiles"
    private static let minimumFileSizeKey = "Unico.minimumFileSize"
    private static let ignoredPathsKey = "Unico.ignoredPaths"
    private let defaults: UserDefaults

    @Published private(set) var includedFileTypes: Set<FileTypeCategory> {
        didSet { defaults.set(includedFileTypes.map(\.rawValue).sorted(), forKey: Self.includedFileTypesKey) }
    }
    @Published private(set) var defaultKeepRule: DuplicateKeepRule {
        didSet { defaults.set(defaultKeepRule.rawValue, forKey: Self.defaultKeepRuleKey) }
    }
    @Published private(set) var skipHiddenFiles: Bool {
        didSet { defaults.set(skipHiddenFiles, forKey: Self.skipHiddenFilesKey) }
    }
    @Published private(set) var minimumFileSize: Int64 {
        didSet { defaults.set(minimumFileSize, forKey: Self.minimumFileSizeKey) }
    }
    @Published private(set) var ignoredPaths: [String] {
        didSet { defaults.set(ignoredPaths, forKey: Self.ignoredPathsKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.stringArray(forKey: Self.includedFileTypesKey) {
            includedFileTypes = Set(stored.compactMap(FileTypeCategory.init(rawValue:)))
        } else {
            includedFileTypes = FileTypeCategory.defaultIncluded
        }
        defaultKeepRule = defaults.string(forKey: Self.defaultKeepRuleKey).flatMap(DuplicateKeepRule.init(rawValue:)) ?? .newestModified
        skipHiddenFiles = defaults.object(forKey: Self.skipHiddenFilesKey) as? Bool ?? true
        let storedMinimum = defaults.object(forKey: Self.minimumFileSizeKey) as? NSNumber
        minimumFileSize = max(0, storedMinimum?.int64Value ?? 1_000_000)
        ignoredPaths = Array(Set((defaults.stringArray(forKey: Self.ignoredPathsKey) ?? []).map { URL(fileURLWithPath: $0).standardizedFileURL.path })).sorted()
    }

    var scanRules: ScanRules {
        ScanRules(includedFileTypes: includedFileTypes, skipHiddenFiles: skipHiddenFiles, minimumFileSize: minimumFileSize, ignoredPaths: ignoredPaths)
    }

    func setIncluded(_ category: FileTypeCategory, _ included: Bool) {
        if included { includedFileTypes.insert(category) }
        else { includedFileTypes.remove(category) }
    }
    func setDefaultKeepRule(_ rule: DuplicateKeepRule) { defaultKeepRule = rule }
    func setSkipHiddenFiles(_ value: Bool) { skipHiddenFiles = value }
    func setMinimumFileSize(_ value: Int64) { minimumFileSize = max(0, value) }

    func addIgnoredFolder(_ url: URL) {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard !ignoredPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else { return }
        ignoredPaths.removeAll { $0.hasPrefix(path + "/") }
        ignoredPaths.append(path)
        ignoredPaths.sort()
    }
    func removeIgnoredFolder(_ path: String) { ignoredPaths.removeAll { $0 == path } }
}

struct SettingsView: View {
    @ObservedObject var settings: ScanSettings
    let language: AppLanguage
    @State private var showingIgnoredLocations = false
    @State private var showingCustomMinimum = false

    private func text(_ chinese: String, _ english: String) -> String { language.text(chinese, english) }
    private func title(_ category: FileTypeCategory) -> String {
        switch category {
        case .media: return text("图片、视频与音频", "Images, video, and audio")
        case .documents: return text("文档与 PDF", "Documents and PDF")
        case .archivesAndInstallers: return text("压缩包与安装包", "Archives and installers")
        case .scripts: return text("代码与脚本", "Code and scripts")
        case .other: return text("其他文件类型", "Other file types")
        }
    }
    private func keepTitle(_ rule: DuplicateKeepRule) -> String {
        switch rule {
        case .manual: return text("不自动选择", "Do not select automatically")
        case .newestModified: return text("较新的文件", "Newer file")
        case .oldestModified: return text("较早的文件", "Older file")
        }
    }
    private func minimumTitle(_ option: MinimumFileSizeOption) -> String {
        switch option {
        case .unlimited: return text("不限制", "No limit")
        case .kilobytes100: return "100 KB"
        case .megabytes1: return "1 MB"
        case .megabytes10: return "10 MB"
        case .megabytes100: return "100 MB"
        case .custom: return text("自定义…", "Custom…")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeading(text("扫描范围", "Scan scope"), detail: text("选择参与重复文件扫描的类型", "Choose file types to include in duplicate scans"))
            VStack(alignment: .leading, spacing: 2) {
                ForEach(FileTypeCategory.allCases) { category in
                    FileTypeToggleRow(title: title(category), isOn: Binding(
                        get: { settings.includedFileTypes.contains(category) },
                        set: { settings.setIncluded(category, $0) }
                    ))
                }
            }
            .padding(.top, 14)

            Label(text("系统文件、应用程序及受保护位置始终不会扫描", "System files, apps, and protected locations are always skipped"), systemImage: "shield")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 12)

            Divider().padding(.vertical, 26)

            sectionHeading(text("扫描规则", "Scan rules"), detail: nil)
            VStack(spacing: 0) {
                formRow(text("跳过隐藏文件", "Skip hidden files")) {
                    Toggle("", isOn: Binding(get: { settings.skipHiddenFiles }, set: settings.setSkipHiddenFiles))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                formRow(text("忽略小于", "Ignore smaller than")) {
                    Picker("", selection: Binding(
                        get: { MinimumFileSizeOption.option(for: settings.minimumFileSize) },
                        set: { option in
                            if let bytes = option.bytes { settings.setMinimumFileSize(bytes) }
                            else { showingCustomMinimum = true }
                        }
                    )) {
                        ForEach(MinimumFileSizeOption.allCases) { option in
                            Text(minimumTitle(option)).tag(option)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 150, alignment: .trailing)
                }
                formRow(text("始终忽略的位置", "Always ignore locations")) {
                    Button(text("管理…", "Manage…")) { showingIgnoredLocations = true }
                        .buttonStyle(.borderless)
                }
            }
            .padding(.top, 10)

            Divider().padding(.vertical, 26)

            sectionHeading(text("重复文件处理", "Duplicate handling"), detail: nil)
            formRow(text("默认保留", "Default selection")) {
                Picker("", selection: Binding(get: { settings.defaultKeepRule }, set: settings.setDefaultKeepRule)) {
                    ForEach(DuplicateKeepRule.allCases) { rule in Text(keepTitle(rule)).tag(rule) }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 190, alignment: .trailing)
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 52)
        .padding(.vertical, 34)
        .frame(width: 700, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingIgnoredLocations) { IgnoredLocationsSheet(settings: settings, language: language) }
        .sheet(isPresented: $showingCustomMinimum) { CustomMinimumSizeSheet(settings: settings, language: language) }
    }

    @ViewBuilder
    private func sectionHeading(_ title: String, detail: String?) -> some View {
        Text(title).font(.system(size: 16, weight: .semibold))
        if let detail {
            Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 3)
        }
    }
    @ViewBuilder
    private func formRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer(minLength: 24)
            control()
        }
        .frame(minHeight: 34)
    }
}

private struct FileTypeToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    @State private var isHovering = false
    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.checkbox)
            .font(.system(size: 14))
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 7)
            .background(isHovering ? Color.primary.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 4))
            .onHover { isHovering = $0 }
    }
}

private struct IgnoredLocationsSheet: View {
    @ObservedObject var settings: ScanSettings
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss
    private func text(_ chinese: String, _ english: String) -> String { language.text(chinese, english) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(text("始终忽略的位置", "Always ignore locations")).font(.headline)
            Group {
                if settings.ignoredPaths.isEmpty {
                    Text(text("暂无忽略位置", "No ignored locations"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    List(settings.ignoredPaths, id: \.self) { path in
                        HStack(spacing: 10) {
                            Image(systemName: "folder").foregroundStyle(.secondary)
                            Text(path).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { settings.removeIgnoredFolder(path) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(text("移除 \(path)", "Remove \(path)"))
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(height: 230)
            HStack {
                Button(text("添加文件夹…", "Add Folder…"), action: chooseFolder)
                Spacer()
                Button(text("完成", "Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 520, height: 340)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = text("选择要忽略的文件夹", "Choose a folder to ignore")
        panel.prompt = text("添加", "Add")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        let complete: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            Task { @MainActor in panel.urls.forEach(settings.addIgnoredFolder) }
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow { panel.beginSheetModal(for: window, completionHandler: complete) }
        else { panel.begin(completionHandler: complete) }
    }
}

private struct CustomMinimumSizeSheet: View {
    @ObservedObject var settings: ScanSettings
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var amount = "1"
    @State private var unit = "MB"
    private func text(_ chinese: String, _ english: String) -> String { language.text(chinese, english) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(text("自定义最小文件大小", "Custom minimum file size")).font(.headline)
            HStack {
                TextField(text("大小", "Size"), text: $amount).frame(width: 110)
                Picker("", selection: $unit) {
                    Text("KB").tag("KB")
                    Text("MB").tag("MB")
                }
                .labelsHidden().pickerStyle(.menu)
                Spacer()
            }
            HStack {
                Spacer()
                Button(text("取消", "Cancel")) { dismiss() }
                Button(text("完成", "Done")) {
                    let multiplier: Int64 = unit == "MB" ? 1_000_000 : 1_000
                    if let value = Int64(amount), value >= 0 { settings.setMinimumFileSize(value * multiplier) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 360)
    }
}
