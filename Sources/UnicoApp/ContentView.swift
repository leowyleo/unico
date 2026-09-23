import SwiftUI
import AppKit
import Quartz
import UnicoCore

private enum SystemPalette {
    static let window = Color(nsColor: .windowBackgroundColor)
    static let control = Color(nsColor: .controlBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
    static let selection = Color(nsColor: .selectedContentBackgroundColor)
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    private func t(_ zh: String, _ en: String) -> String { model.t(zh, en) }
    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .start: startView
            case .scanning: scanningView
            case .results: resultsView
            }
        }
        .foregroundStyle(.primary).tint(.accentColor)
        .frame(minWidth: 940, minHeight: 660)
        .background(SystemPalette.window)
        .overlay(SettingsTitlebarAccessory(settings: model.settings, language: model.language).frame(width: 0, height: 0).allowsHitTesting(false))
        .environment(\.locale, model.language.locale)
        .alert(item: $model.prompt) { prompt in
            switch prompt {
            case .wholeDisk:
                return Alert(title: Text(t("扫描本机内置磁盘？", "Scan the internal disk?")), message: Text(t("文件较多时可能耗时较长，可以随时取消。只查找设置中选定的文件类型；系统位置、隐藏目录、应用、依赖与缓存会跳过。外接磁盘与网络位置不包含在内。", "This may take a while. You can cancel at any time. Only selected file types are included. System locations, hidden folders, apps, dependencies, and caches are skipped. External and network volumes are excluded.")), primaryButton: .default(Text(t("开始扫描", "Start scan"))) { model.start(wholeDisk: true) }, secondaryButton: .cancel(Text(t("取消", "Cancel"))))
            case .manualScan:
                return Alert(title: Text(t("按所选范围扫描？", "Scan these folders?")), message: Text(t("扫描所选文件夹及其子目录中、设置允许的文件类型。\n\n扫描只读取文件，不会修改任何内容。系统位置、应用包、链接、隐藏项、依赖与缓存会自动跳过。发现重复项后，仍需确认才能移到废纸篓。\n\n", "Scanning selected file types in these folders and their subfolders is read-only. System locations, app bundles, links, hidden items, dependencies, and caches are skipped. Duplicates still require confirmation before moving to Trash.\n\n") + model.roots.map { model.shortPath($0) }.joined(separator: "\n")), primaryButton: .default(Text(t("确认并扫描", "Confirm and scan"))) { model.start(confirmed: true) }, secondaryButton: .cancel(Text(t("取消", "Cancel"))))
            case .clean:
                return Alert(title: Text(t("将 \(model.selectedCount) 个副本移到废纸篓？", "Move \(englishCount(model.selectedCount, "copy", "copies")) to Trash?")), message: Text(t("所选文件共 \(model.size(model.selectedBytes))，每组至少保留一份。请确认这些位置的副本不再需要；内容相同不代表所有路径都可删。清理前会重新检查内容与文件身份。所选目录中的应用、项目或系统文件即使相同，删除也可能导致功能失效。\n\n可从废纸篓恢复。清空废纸篓后才释放空间，实际释放空间可能与文件总大小不同。", "Selected size: \(model.size(model.selectedBytes)). At least one file per group will be kept. Confirm these copies are no longer needed at their locations. Identical contents do not make every path disposable. Contents and file identity are checked again before cleanup. Removing identical app, project or system files in selected folders may still break functionality.\n\nFiles can be restored from Trash. Space is freed only after emptying Trash; actual savings may differ.")), primaryButton: .default(Text(t("移到废纸篓", "Move to Trash"))) { model.clean() }, secondaryButton: .cancel(Text(t("取消", "Cancel"))))
            }
        }
        .sheet(isPresented: $model.showIssues) { issueSheet }
        .onChange(of: model.selectedGroupID) { _ in model.previewID = nil }
    }

    private var startView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 42)
            Image(systemName: "doc.on.doc")
                .font(.system(size: 32, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 64, height: 64)
                .background(Circle().fill(SystemPalette.control))
                .padding(.bottom, 18)
            Text(t("少一点重复，多一点从容。", "A little less. A little lighter."))
                .font(.title2.weight(.semibold))
                .padding(.bottom, 8)
            Text(t("选择文件夹，找出内容完全相同的文件，再决定保留哪一份。", "Choose folders, find identical files, then decide what stays."))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
                .padding(.bottom, 28)
            scopeCard
            if model.supportsWholeDiskScan {
                Button { model.prompt = .wholeDisk } label: {
                    Label(t("扫描本机内置磁盘", "Scan the internal disk"), systemImage: "internaldrive")
                }
                .buttonStyle(.bordered)
                .padding(.top, 14)
            }
            if let notice = model.notice {
                Text(notice.text(model.language))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
                    .padding(.top, 10)
            }
            Spacer(minLength: 36)
            Label(t("完全本地 · 无需账号 · 仅移到废纸篓", "On your Mac · No account · Trash, never erase"), systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scopeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.roots.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 29, weight: .light))
                        .foregroundStyle(Color.accentColor)
                    Text(t("从文件夹开始", "Start with folders"))
                        .font(.headline)
                    Text(t("拖入文件夹，或一次选择多个", "Drop folders here, or choose several at once"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button(t("选择文件夹", "Choose folders"), action: model.addFolders)
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 6)
                        .accessibilityHint(t("可一次选择多个文件夹", "You can choose more than one folder"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
            } else {
                Text(t("已选择的文件夹", "Selected folders"))
                    .font(.headline)
                Text(t("确认范围后开始扫描", "Review the scope, then start scanning"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(model.roots, id: \.path) { url in
                            HStack(spacing: 12) {
                                Image(systemName: "folder")
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.location(url)).font(.subheadline.weight(.semibold))
                                    Text(model.shortPath(url))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Button { model.roots.removeAll { $0 == url } } label: {
                                    Image(systemName: "xmark").font(.system(size: 11)).frame(width: 40, height: 40).contentShape(Rectangle())
                                }.buttonStyle(.plain).foregroundStyle(.secondary)
                                    .accessibilityLabel(t("移除 \(model.location(url))", "Remove \(model.location(url))"))
                            }.frame(minHeight: 52)
                        }
                    }
                }
                .padding(.top, 16)
                .frame(height: min(150, CGFloat(model.roots.count) * 58))
                HStack {
                    Button(t("添加文件夹", "Add folders"), action: model.addFolders).buttonStyle(.bordered)
                    Spacer()
                    Button { model.start() } label: { Label(t("开始扫描", "Start scan"), systemImage: "arrow.right") }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 16)
            }
            Divider()
                .padding(.vertical, 18)
            Label(t("按设置扫描所选类型；受保护位置始终跳过", "Selected types are scanned; protected locations are always skipped"), systemImage: "checkmark.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 500)
            .background(RoundedRectangle(cornerRadius: 12).fill(SystemPalette.control))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(model.isDropTarget ? Color.accentColor : SystemPalette.separator, lineWidth: model.isDropTarget ? 2 : 1))
            .onDrop(of: [.fileURL], isTargeted: $model.isDropTarget, perform: model.receiveDrop)
    }

    private var scanningView: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "doc.on.doc").font(.system(size: 36, weight: .light)).foregroundStyle(.secondary).padding(.bottom, 28)
            Text(model.cancelling ? t("正在停止扫描…", "Stopping scan…") : t(model.progress.phase, model.progress.englishPhase))
                .font(.system(size: 27, weight: .medium)).padding(.bottom, 12)
            Text(t("已读取 \(model.progress.scanned) 个文件 · 已发现 \(model.progress.duplicateGroups) 组重复", "\(englishCount(model.progress.scanned, "file")) read · \(englishCount(model.progress.duplicateGroups, "duplicate group"))"))
                .font(.system(size: 13)).foregroundStyle(.secondary).monospacedDigit().padding(.bottom, 28)
            Group {
                if model.progress.totalToCheck > 0 {
                    ProgressView(value: Double(model.progress.checked), total: Double(model.progress.totalToCheck))
                } else { ProgressView().progressViewStyle(.linear) }
            }.frame(width: 360)
            if model.progress.totalToCheck > 0 {
                Text(t("内容核验 \(model.progress.checked) / \(model.progress.totalToCheck)", "Content checks \(model.progress.checked) / \(model.progress.totalToCheck)"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit().padding(.top, 10)
            }
            Text(model.progress.currentPath).font(.system(size: 11)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: 560).padding(.top, 18)
            Button(model.cancelling ? t("正在取消…", "Cancelling…") : t("取消扫描", "Cancel scan"), action: model.cancel)
                .buttonStyle(.bordered).disabled(model.cancelling).padding(.top, 24)
            Spacer()
            Label(t("此时只读取文件，不会修改或删除。", "Read-only scanning. No files are changed or deleted."), systemImage: "lock.shield")
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.bottom, 24)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(t("\(model.visibleGroups.count) 组重复", "\(englishCount(model.visibleGroups.count, "duplicate group"))"))
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                Text(t("已读取 \(model.scanned) · 已排除 \(model.excluded)", "\(model.scanned) read · \(model.excluded) excluded"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .help(model.isWholeDisk ? t("仅扫描设置允许的类型；系统、应用、隐藏项、依赖和缓存会跳过。", "Only selected types are scanned. System locations, apps, hidden items, dependencies, and caches are skipped.") : t("已按确认的目录和所选类型扫描；受保护内容仍会跳过。", "Scanned confirmed folders and selected types; protected content is still skipped."))
                Spacer(minLength: 8)
                if model.systemOrProtectedGroupCount > 0 {
                    Toggle(t("隐藏系统及受保护文件", "Hide system and protected files"), isOn: Binding(
                        get: { model.hidesSystemFiles },
                        set: { model.setSystemFileVisibility($0) }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .help(t("默认隐藏这些结果；显示后也需要你逐项选择，才会清理。", "These results are hidden by default. Showing them never selects them for cleanup."))
                }
                Button(t("重新扫描", "New scan"), action: model.reset)
                    .buttonStyle(.bordered).disabled(model.isCleaning)
                if !model.issues.isEmpty {
                    Button { model.showIssues = true } label: { Label(t("\(model.issues.count) 项需注意", "\(englishCount(model.issues.count, "issue"))"), systemImage: "exclamationmark.circle") }
                        .buttonStyle(.bordered)
                }
                if !model.visibleGroups.isEmpty {
                    Button(model.visibleSelectedCount > 0 ? t("取消全选", "Deselect all") : t("选择多余副本", "Select extra copies"), action: model.toggleAll)
                        .buttonStyle(.bordered).disabled(model.isCleaning)
                }
            }.padding(.horizontal, 24).padding(.vertical, 10)
            Rectangle().fill(SystemPalette.separator).frame(height: 1)
            if model.visibleGroups.isEmpty { emptyResults } else {
                HSplitView {
                    groupList.frame(minWidth: 220, idealWidth: 260, maxWidth: 300)
                    detail.frame(minWidth: 570, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if let notice = model.notice {
                Text(notice.text(model.language)).font(.system(size: 12)).foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 12)
                    .background(SystemPalette.selection.opacity(0.32))
                    .overlay(Rectangle().fill(Color.accentColor).frame(width: 3), alignment: .leading)
            }
            Rectangle().fill(SystemPalette.separator).frame(height: 1)
            footer
        }
    }

    private var emptyResults: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: model.notice == nil ? "doc.text.magnifyingglass" : "checkmark.circle")
                .font(.system(size: 40, weight: .ultraLight)).foregroundStyle(Color.accentColor)
            Text(model.notice == nil ? (model.groups.isEmpty ? t("没有发现完全重复的文件", "No identical files found") : t("没有显示中的重复文件", "No visible duplicate files")) : (model.issues.isEmpty ? t("清理完成", "Cleanup complete") : t("本轮处理已结束", "Finished with skipped items")))
                .font(.system(size: 24, weight: .medium))
            Text(model.issues.isEmpty ? (model.groups.isEmpty ? (model.isWholeDisk ? t("只查找常见个人文件，受保护的内容已排除。", "Only common personal files were checked. Protected content was excluded.") : t("已按确认的文件夹范围完成检查。", "The confirmed folders have been checked.")) : t("取消“隐藏系统及受保护文件”即可查看这些结果。", "Turn off Hide system and protected files to review these results.")) : t("请查看未处理项目，确认后重新扫描。", "Review the unprocessed items, then scan again."))
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 480)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var groupList: some View {
        List(selection: $model.selectedGroupID) {
            ForEach(model.visibleGroups) { group in
                HStack(spacing: 12) {
                    FileThumbnail(file: group.files[0]).frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.files.first(where: { $0.id == group.keeperID })?.name ?? t("文件", "File"))
                            .font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        Text(t("\(group.files.count) 份 · 多余 \(model.size(group.redundantBytes))", "\(englishCount(group.files.count, "copy", "copies")) · \(model.size(group.redundantBytes)) extra"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }.padding(.vertical, 11).tag(group.id)
            }
        }.listStyle(.sidebar).compatibleScrollBackground().disabled(model.isCleaning)
    }

    private var detail: some View {
        GeometryReader { geometry in
        VStack(alignment: .leading, spacing: 0) {
            if let group = model.currentGroup, let file = model.previewFile {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(file.name).font(.system(size: 15, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        Text(t("正在预览 · \(model.size(file.size))", "Previewing · \(model.size(file.size))"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: {
                        Image(systemName: "folder").frame(width: 40, height: 40).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                        .help(t("在 Finder 中显示", "Show in Finder")).accessibilityLabel(t("在 Finder 中显示", "Show in Finder"))
                }.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 14)
                FilePreview(url: file.url).id(file.id)
                    .frame(maxWidth: .infinity, minHeight: 110, maxHeight: .infinity)
                    .background(SystemPalette.window)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(SystemPalette.separator, lineWidth: 1))
                    .padding(.horizontal, 24).padding(.bottom, 18)
                HStack {
                    Text(t("保留哪一份", "Choose what stays")).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(t("内容完全相同 · 点击下方文件预览", "Identical contents · Click a file to preview"))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.horizontal, 24).padding(.bottom, 10)
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(group.files) { record in fileRow(record, group: group) }
                    }.padding(.horizontal, 20).padding(.bottom, 14)
                }.frame(height: min(248, CGFloat(group.files.count) * 88 + 14, max(130, geometry.size.height - 240)))
            } else {
                Text(t("选择一组文件进行预览", "Select a group to preview"))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(SystemPalette.window)
        }
    }

    private func fileRow(_ file: FileRecord, group: DuplicateGroup) -> some View {
        let keeper = file.id == group.keeperID
        let previewing = model.previewFile?.id == file.id
        let selected = group.selectedIDs.contains(file.id)
        return HStack(spacing: 6) {
            if keeper {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 15)).foregroundStyle(.primary)
                    .frame(width: 40, height: 40).help(t("本组保留文件", "Kept in this group"))
            } else {
                Toggle(t("清理 \(file.name)", "Clean \(file.name)"), isOn: Binding(get: { selected }, set: { _ in model.toggle(file) }))
                    .labelsHidden().toggleStyle(.checkbox).frame(width: 40, height: 40).disabled(model.isCleaning)
            }
            Button { model.previewID = file.id } label: {
                HStack(spacing: 12) {
                    FileThumbnail(file: file).frame(width: 58, height: 58)
                        .background(SystemPalette.window)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SystemPalette.separator, lineWidth: 1))
                        .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(file.name).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        Text(keeper ? t("保留", "Keep") : (selected ? t("待清理", "To Trash") : t("不清理", "Not selected")))
                            .font(.system(size: 9, weight: .semibold)).padding(.horizontal, 6).padding(.vertical, 3)
                            .foregroundStyle(keeper ? Color.accentColor : .secondary)
                            .background(Capsule().fill(keeper ? SystemPalette.selection : Color.secondary.opacity(0.08)))
                    }
                    Text(model.location(file.url.deletingLastPathComponent()) + "  ·  " + model.shortPath(file.url.deletingLastPathComponent()))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Text(t("修改于 \(model.date(file.stamp.modified))", "Modified \(model.date(file.stamp.modified))"))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help(file.url.path)
                .accessibilityLabel(t("预览 \(file.name)", "Preview \(file.name)"))
                .accessibilityHint(t("在上方显示此文件", "Shows this file above"))
            if !keeper {
                Button(t("保留此份", "Keep this")) { model.keep(file) }
                    .buttonStyle(.bordered).disabled(model.isCleaning)
            } else {
                Text(defaultKeepLabel(file, group: group))
                    .font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 10)
            }
        }.padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(previewing ? SystemPalette.selection.opacity(0.35) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(previewing ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1))
    }

    private func defaultKeepLabel(_ file: FileRecord, group: DuplicateGroup) -> String {
        guard file.id == group.keeperID else { return t("手动保留", "Your choice") }
        switch group.defaultKeepRule {
        case .newestModified: return t("默认保留最新修改日期", "Newest modified kept by default")
        case .oldestModified: return t("默认保留最早修改日期", "Earliest modified kept by default")
        case .manual: return group.selectedIDs.isEmpty ? t("未预选清理", "Nothing preselected") : t("手动保留", "Your choice")
        }
    }

    private var footer: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.isCleaning ? t("正在核验并清理 \(model.cleanProcessed) / \(model.cleanTotal)", "Checking and cleaning \(model.cleanProcessed) / \(model.cleanTotal)") : t("已选 \(model.selectedCount) 个副本 · \(model.size(model.selectedBytes))", "\(englishCount(model.selectedCount, "copy", "copies")) selected · \(model.size(model.selectedBytes))"))
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                Text(t("确认副本所在位置不再需要。仅移到废纸篓，可恢复。", "Confirm these copies are no longer needed here. Recoverable from Trash."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if model.isCleaning {
                ProgressView().controlSize(.small)
                Button(model.cancelling ? t("正在停止…", "Stopping…") : t("停止清理", "Stop cleanup"), action: model.cancel)
                    .buttonStyle(.bordered).disabled(model.cancelling)
            } else {
                Button { model.prompt = .clean } label: { Label(t("移到废纸篓", "Move to Trash"), systemImage: "trash") }
                    .buttonStyle(.borderedProminent).disabled(model.selectedCount == 0)
            }
        }.padding(.horizontal, 24).padding(.vertical, 18)
    }

    private var issueSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("未处理的项目", "Unprocessed items")).font(.system(size: 23, weight: .medium))
            Text(t("这些项目没有被成功扫描或清理，不计作已处理。", "These items could not be scanned or cleaned. They are not counted as processed."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            List(model.issues) { issue in
                VStack(alignment: .leading, spacing: 5) {
                    Text(issue.path).font(.system(size: 12)).textSelection(.enabled)
                    Text(t(issue.reason, issue.englishReason)).font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.vertical, 6)
            }.compatibleScrollBackground()
            HStack { Spacer(); Button(t("完成", "Done")) { model.showIssues = false }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 640, height: 430).background(SystemPalette.window)
    }
}

struct FilePreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact)!
        view.autostarts = false
        view.previewItem = url as NSURL
        return view
    }
    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if (nsView.previewItem as? NSURL) != url as NSURL { nsView.previewItem = url as NSURL }
    }
}
