import SwiftUI
import AppKit
import Quartz
import UnicoCore

struct UnicoColors {
    let dark: Bool
    var canvas: Color { dark ? Color(red: 0.105, green: 0.110, blue: 0.105) : Color(red: 0.967, green: 0.959, blue: 0.940) }
    var surface: Color { dark ? Color(red: 0.145, green: 0.150, blue: 0.145) : Color(red: 0.994, green: 0.989, blue: 0.974) }
    var accent: Color { dark ? Color(red: 0.90, green: 0.63, blue: 0.47) : Color(red: 0.64, green: 0.28, blue: 0.18) }
    var ink: Color { dark ? Color(red: 0.93, green: 0.92, blue: 0.88) : Color(red: 0.17, green: 0.19, blue: 0.17) }
    var muted: Color { ink.opacity(dark ? 0.67 : 0.66) }
    var line: Color { (dark ? Color.white : Color.black).opacity(0.09) }
}

struct UnicoMark: View {
    var color: Color
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let card = RoundedRectangle(cornerRadius: w * 0.17)
            ZStack {
                // A quiet ceramic back plate and a thin lower edge create depth at small sizes.
                card.fill(scheme == .dark ? Color(red: 0.31, green: 0.23, blue: 0.18) : Color(red: 0.66, green: 0.49, blue: 0.38))
                    .offset(y: w * 0.035)
                    .overlay(card.fill(LinearGradient(colors: scheme == .dark
                        ? [Color(red: 0.51, green: 0.39, blue: 0.31), Color(red: 0.33, green: 0.25, blue: 0.20)]
                        : [Color(red: 0.97, green: 0.90, blue: 0.82), Color(red: 0.78, green: 0.64, blue: 0.53)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .overlay(card.strokeBorder(.white.opacity(0.25), lineWidth: max(0.5, w * 0.012)))
                    .frame(width: w * 0.64, height: w * 0.74)
                    .rotationEffect(.degrees(-6))
                    .shadow(color: .black.opacity(0.18), radius: w * 0.055, x: 0, y: w * 0.055)
                    .offset(x: -w * 0.14, y: -w * 0.11)
                ZStack {
                    card.fill(color).overlay(card.fill(.black.opacity(0.28)))
                        .offset(x: w * 0.012, y: w * 0.045)
                    card.fill(color)
                        .overlay(card.fill(LinearGradient(colors: [.white.opacity(0.23), .clear, .black.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .overlay(card.strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.08), .black.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: max(0.6, w * 0.016)))
                    Image(systemName: "checkmark").font(.system(size: w * 0.27, weight: .semibold))
                        .foregroundStyle(Color(red: 0.99, green: 0.97, blue: 0.92))
                        .shadow(color: .black.opacity(0.22), radius: w * 0.008, y: w * 0.018)
                }
                .frame(width: w * 0.64, height: w * 0.74)
                .shadow(color: .black.opacity(scheme == .dark ? 0.30 : 0.22), radius: w * 0.06, x: w * 0.025, y: w * 0.065)
                .offset(x: w * 0.14, y: w * 0.11)
            }.frame(width: w, height: g.size.height)
        }.accessibilityHidden(true)
    }
}

struct UnicoButtonStyle: ButtonStyle {
    var colors: UnicoColors
    var primary = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 16).frame(minHeight: 40)
            .foregroundStyle(primary ? (colors.dark ? Color(red: 0.16, green: 0.12, blue: 0.10) : .white) : colors.ink)
            .background(RoundedRectangle(cornerRadius: 10).fill(primary ? colors.accent : colors.ink.opacity(configuration.isPressed ? 0.10 : 0.055)))
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    private var colors: UnicoColors { UnicoColors(dark: colorScheme == .dark) }
    private func t(_ zh: String, _ en: String) -> String { model.t(zh, en) }
    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .start: startView
            case .scanning: scanningView
            case .results: resultsView
            }
        }
        .foregroundStyle(colors.ink).tint(colors.accent)
        .frame(minWidth: 940, minHeight: 660)
        .background(colors.canvas)
        .environment(\.locale, model.language.locale)
        .alert(item: $model.prompt) { prompt in
            switch prompt {
            case .wholeDisk:
                return Alert(title: Text(t("扫描本机内置磁盘？", "Scan the internal disk?")), message: Text(t("文件较多时可能耗时较长，可以随时取消。只查找常见个人文件；隐藏目录、程序、配置、开发项目及图库内部内容会跳过。外接磁盘与网络位置不包含在内。无法读取的位置会列出提示。", "This may take a while. You can cancel at any time. Only common personal files are included. Hidden folders, applications, configuration, development projects and photo libraries are skipped. External and network disks are excluded. Unreadable locations will be reported.")), primaryButton: .default(Text(t("开始扫描", "Start scan"))) { model.start(wholeDisk: true) }, secondaryButton: .cancel(Text(t("取消", "Cancel"))))
            case .manualScan:
                return Alert(title: Text(t("按所选范围扫描？", "Scan everything in these folders?")), message: Text(t("你主动选择的文件夹及其子目录将优先于默认排除规则，包含隐藏文件、应用内部、项目资源和未知类型。删除这些文件可能影响应用或系统运行。\n\n扫描本身不会修改文件，清理前仍需确认。链接、硬链接、未下载的云文件及无权限内容仍会跳过。\n\n", "Your selected folders and their subfolders override default exclusions, including hidden files, app internals, project resources and unknown types. Removing these files may affect apps or the system.\n\nScanning changes nothing. Cleanup requires a separate confirmation. Links, hard links, cloud-only files and inaccessible items are still skipped.\n\n") + model.roots.map { model.shortPath($0) }.joined(separator: "\n")), primaryButton: .default(Text(t("确认并扫描", "Confirm and scan"))) { model.start(confirmed: true) }, secondaryButton: .cancel(Text(t("取消", "Cancel"))))
            case .clean:
                return Alert(title: Text(t("将 \(model.selectedCount) 个副本移到废纸篓？", "Move \(englishCount(model.selectedCount, "copy", "copies")) to Trash?")), message: Text(t("所选文件共 \(model.size(model.selectedBytes))，每组至少保留一份。请确认这些位置的副本不再需要；内容相同不代表所有路径都可删。清理前会重新检查内容与文件身份。所选目录中的应用、项目或系统文件即使相同，删除也可能导致功能失效。\n\n可从废纸篓恢复。清空废纸篓后才释放空间，实际释放空间可能与文件总大小不同。", "Selected size: \(model.size(model.selectedBytes)). At least one file per group will be kept. Confirm these copies are no longer needed at their locations. Identical contents do not make every path disposable. Contents and file identity are checked again before cleanup. Removing identical app, project or system files in selected folders may still break functionality.\n\nFiles can be restored from Trash. Space is freed only after emptying Trash; actual savings may differ.")), primaryButton: .default(Text(t("移到废纸篓", "Move to Trash"))) { model.clean() }, secondaryButton: .cancel(Text(t("取消", "Cancel"))))
            }
        }
        .sheet(isPresented: $model.showIssues) { issueSheet }
        .onChange(of: model.selectedGroupID) { _ in model.previewID = nil }
    }

    private var startView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            UnicoMark(color: colors.accent).frame(width: 66, height: 72).padding(.bottom, 25)
            Text(t("少一点重复，多一点从容。", "A little less. A little lighter."))
                .font(.system(size: 31, weight: .medium)).tracking(-0.7).padding(.bottom, 12)
            Text(t("找出相同的文件，让每一份保留都有意义。", "Find identical files. Keep what belongs."))
                .font(.system(size: 14)).foregroundStyle(colors.muted).padding(.bottom, 30)
            scopeCard
            HStack(spacing: 8) {
                Image(systemName: "internaldrive").foregroundStyle(colors.muted)
                Button(t("或扫描本机内置磁盘", "Or scan the internal disk")) { model.prompt = .wholeDisk }
                    .buttonStyle(.plain).foregroundStyle(colors.muted).frame(minHeight: 40)
            }.font(.system(size: 12)).padding(.top, 12)
            if let notice = model.notice {
                Text(notice.text(model.language)).font(.system(size: 12)).foregroundStyle(colors.muted)
                    .multilineTextAlignment(.center).frame(maxWidth: 580).padding(.top, 8)
            }
            Spacer(minLength: 20)
            Label(t("完全本地 · 无需账号 · 仅移到废纸篓", "On your Mac · No account · Trash, never erase"), systemImage: "lock.shield")
                .font(.system(size: 11)).foregroundStyle(colors.muted).padding(.bottom, 24)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scopeCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.roots.isEmpty {
                HStack(spacing: 16) {
                    Image(systemName: "folder.badge.plus").font(.system(size: 27, weight: .light))
                        .foregroundStyle(colors.accent).frame(width: 44, height: 48)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("从一个文件夹开始", "Start with a folder")).font(.system(size: 15, weight: .semibold))
                        Text(t("拖到这里，也可以一次选择多个", "Drop folders here, or choose a few"))
                            .font(.system(size: 12)).foregroundStyle(colors.muted)
                    }
                    Spacer(minLength: 16)
                    Button(t("选择文件夹", "Choose folders"), action: model.addFolders)
                        .buttonStyle(UnicoButtonStyle(colors: colors, primary: true))
                }
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.roots, id: \.path) { url in
                            HStack(spacing: 12) {
                                Image(systemName: "folder").foregroundStyle(colors.accent).frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.location(url)).font(.system(size: 13, weight: .semibold))
                                    Text(model.shortPath(url)).font(.system(size: 11)).foregroundStyle(colors.muted).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Button { model.roots.removeAll { $0 == url } } label: {
                                    Image(systemName: "xmark").font(.system(size: 11)).frame(width: 40, height: 40).contentShape(Rectangle())
                                }.buttonStyle(.plain).foregroundStyle(colors.muted)
                                    .accessibilityLabel(t("移除 \(model.location(url))", "Remove \(model.location(url))"))
                            }.frame(minHeight: 52)
                        }
                    }
                }.frame(height: min(150, CGFloat(model.roots.count) * 58))
                HStack {
                    Button(t("添加文件夹", "Add folders"), action: model.addFolders).buttonStyle(UnicoButtonStyle(colors: colors))
                    Spacer()
                    Button { model.start() } label: { Label(t("开始扫描", "Start scan"), systemImage: "arrow.right") }
                        .buttonStyle(UnicoButtonStyle(colors: colors, primary: true))
                }
            }
            Rectangle().fill(colors.line).frame(height: 1)
            VStack(alignment: .leading, spacing: 5) {
                Text(t("选择文件夹，确认后按所选范围扫描", "Your folders. Your scan scope."))
                    .font(.system(size: 11, weight: .medium))
                Text(t("手动选择优先；全盘扫描默认排除受保护内容。", "Confirmed folders override exclusions. Whole-disk scans stay protected."))
                    .font(.system(size: 11)).foregroundStyle(colors.muted)
            }
        }.padding(24).frame(width: 600)
            .background(RoundedRectangle(cornerRadius: 20).fill(colors.surface))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(model.isDropTarget ? colors.accent : colors.line, lineWidth: model.isDropTarget ? 2 : 1))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.08 : 0.035), radius: 18, y: 6)
            .onDrop(of: [.fileURL], isTargeted: $model.isDropTarget, perform: model.receiveDrop)
    }

    private var scanningView: some View {
        VStack(spacing: 0) {
            Spacer()
            UnicoMark(color: colors.accent).frame(width: 52, height: 58).padding(.bottom, 28)
            Text(model.cancelling ? t("正在停止扫描…", "Stopping scan…") : t(model.progress.phase, model.progress.englishPhase))
                .font(.system(size: 27, weight: .medium)).padding(.bottom, 12)
            Text(t("已读取 \(model.progress.scanned) 个文件 · 已发现 \(model.progress.duplicateGroups) 组重复", "\(englishCount(model.progress.scanned, "file")) read · \(englishCount(model.progress.duplicateGroups, "duplicate group"))"))
                .font(.system(size: 13)).foregroundStyle(colors.muted).monospacedDigit().padding(.bottom, 28)
            Group {
                if model.progress.totalToCheck > 0 {
                    ProgressView(value: Double(model.progress.checked), total: Double(model.progress.totalToCheck))
                } else { ProgressView().progressViewStyle(.linear) }
            }.frame(width: 360)
            if model.progress.totalToCheck > 0 {
                Text(t("内容核验 \(model.progress.checked) / \(model.progress.totalToCheck)", "Content checks \(model.progress.checked) / \(model.progress.totalToCheck)"))
                    .font(.system(size: 11)).foregroundStyle(colors.muted).monospacedDigit().padding(.top, 10)
            }
            Text(model.progress.currentPath).font(.system(size: 11)).foregroundStyle(colors.muted)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: 560).padding(.top, 18)
            Button(model.cancelling ? t("正在取消…", "Cancelling…") : t("取消扫描", "Cancel scan"), action: model.cancel)
                .buttonStyle(UnicoButtonStyle(colors: colors)).disabled(model.cancelling).padding(.top, 24)
            Spacer()
            Label(t("此时只读取文件，不会修改或删除。", "Read-only scanning. No files are changed or deleted."), systemImage: "lock.shield")
                .font(.system(size: 11)).foregroundStyle(colors.muted).padding(.bottom, 24)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(t("\(model.groups.count) 组重复", "\(englishCount(model.groups.count, "duplicate group"))"))
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                Text(t("已读取 \(model.scanned) · 已排除 \(model.excluded)", "\(model.scanned) read · \(model.excluded) excluded"))
                    .font(.system(size: 11)).foregroundStyle(colors.muted)
                    .help(model.isWholeDisk ? t("全盘扫描排除隐藏目录、系统、应用、开发项目及未知类型。", "Whole-disk scans exclude hidden folders, system files, apps, projects and unknown types.") : t("已按确认的目录范围扫描；链接、硬链接及无法读取的文件仍跳过。", "Scanned the confirmed folders. Links, hard links and unreadable files are still skipped."))
                Spacer(minLength: 8)
                Button(t("重新扫描", "New scan"), action: model.reset)
                    .buttonStyle(UnicoButtonStyle(colors: colors)).disabled(model.isCleaning)
                if !model.issues.isEmpty {
                    Button { model.showIssues = true } label: { Label(t("\(model.issues.count) 项需注意", "\(englishCount(model.issues.count, "issue"))"), systemImage: "exclamationmark.circle") }
                        .buttonStyle(UnicoButtonStyle(colors: colors))
                }
                if !model.groups.isEmpty {
                    Button(model.selectedCount > 0 ? t("取消全选", "Deselect all") : t("选择多余副本", "Select extra copies"), action: model.toggleAll)
                        .buttonStyle(UnicoButtonStyle(colors: colors)).disabled(model.isCleaning)
                }
            }.padding(.horizontal, 24).padding(.vertical, 10)
            Rectangle().fill(colors.line).frame(height: 1)
            if model.groups.isEmpty { emptyResults } else {
                HSplitView {
                    groupList.frame(minWidth: 220, idealWidth: 260, maxWidth: 300)
                    detail.frame(minWidth: 570, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if let notice = model.notice {
                Text(notice.text(model.language)).font(.system(size: 12)).foregroundStyle(colors.ink)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 12)
                    .background(colors.accent.opacity(0.08))
            }
            Rectangle().fill(colors.line).frame(height: 1)
            footer
        }
    }

    private var emptyResults: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: model.notice == nil ? "doc.text.magnifyingglass" : "checkmark.circle")
                .font(.system(size: 40, weight: .ultraLight)).foregroundStyle(colors.accent)
            Text(model.notice == nil ? t("没有发现完全重复的文件", "No identical files found") : (model.issues.isEmpty ? t("清理完成", "Cleanup complete") : t("本轮处理已结束", "Finished with skipped items")))
                .font(.system(size: 24, weight: .medium))
            Text(model.issues.isEmpty ? (model.isWholeDisk ? t("只查找常见个人文件，受保护的内容已排除。", "Only common personal files were checked. Protected content was excluded.") : t("已按确认的文件夹范围完成检查。", "The confirmed folders have been checked.")) : t("请查看未处理项目，确认后重新扫描。", "Review the unprocessed items, then scan again."))
                .font(.system(size: 12)).foregroundStyle(colors.muted).multilineTextAlignment(.center).frame(maxWidth: 480)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var groupList: some View {
        List(selection: $model.selectedGroupID) {
            ForEach(model.groups) { group in
                HStack(spacing: 12) {
                    FileThumbnail(file: group.files[0]).frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.files.first(where: { $0.id == group.keeperID })?.name ?? t("文件", "File"))
                            .font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        Text(t("\(group.files.count) 份 · 多余 \(model.size(group.redundantBytes))", "\(englishCount(group.files.count, "copy", "copies")) · \(model.size(group.redundantBytes)) extra"))
                            .font(.system(size: 11)).foregroundStyle(colors.muted)
                    }
                    Spacer(minLength: 0)
                }.padding(.vertical, 11).tag(group.id)
            }
        }.listStyle(.sidebar).compatibleScrollBackground().background(colors.canvas).disabled(model.isCleaning)
    }

    private var detail: some View {
        GeometryReader { geometry in
        VStack(alignment: .leading, spacing: 0) {
            if let group = model.currentGroup, let file = model.previewFile {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(file.name).font(.system(size: 15, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        Text(t("正在预览 · \(model.size(file.size))", "Previewing · \(model.size(file.size))"))
                            .font(.system(size: 11)).foregroundStyle(colors.muted)
                    }
                    Spacer()
                    Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: {
                        Image(systemName: "folder").frame(width: 40, height: 40).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(colors.muted)
                        .help(t("在 Finder 中显示", "Show in Finder")).accessibilityLabel(t("在 Finder 中显示", "Show in Finder"))
                }.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 14)
                FilePreview(url: file.url).id(file.id)
                    .frame(maxWidth: .infinity, minHeight: 110, maxHeight: .infinity)
                    .background(colors.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(colors.line, lineWidth: 1))
                    .padding(.horizontal, 24).padding(.bottom, 18)
                HStack {
                    Text(t("保留哪一份", "Choose what stays")).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(t("内容完全相同 · 点击下方文件预览", "Identical contents · Click a file to preview"))
                        .font(.system(size: 10)).foregroundStyle(colors.muted)
                }.padding(.horizontal, 24).padding(.bottom, 10)
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(group.files) { record in fileRow(record, group: group) }
                    }.padding(.horizontal, 20).padding(.bottom, 14)
                }.frame(height: min(248, CGFloat(group.files.count) * 88 + 14, max(130, geometry.size.height - 240)))
            } else {
                Text(t("选择一组文件进行预览", "Select a group to preview"))
                    .foregroundStyle(colors.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(colors.surface)
        }
    }

    private func fileRow(_ file: FileRecord, group: DuplicateGroup) -> some View {
        let keeper = file.id == group.keeperID
        let previewing = model.previewFile?.id == file.id
        let selected = group.selectedIDs.contains(file.id)
        return HStack(spacing: 6) {
            if keeper {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 15)).foregroundStyle(colors.ink)
                    .frame(width: 40, height: 40).help(t("本组保留文件", "Kept in this group"))
            } else {
                Toggle(t("清理 \(file.name)", "Clean \(file.name)"), isOn: Binding(get: { selected }, set: { _ in model.toggle(file) }))
                    .labelsHidden().toggleStyle(.checkbox).frame(width: 40, height: 40).disabled(model.isCleaning)
            }
            Button { model.previewID = file.id } label: {
                HStack(spacing: 12) {
                    FileThumbnail(file: file).frame(width: 58, height: 58)
                        .background(colors.canvas)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(colors.line, lineWidth: 1))
                        .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(file.name).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        Text(keeper ? t("保留", "Keep") : (selected ? t("待清理", "To Trash") : t("不清理", "Not selected")))
                            .font(.system(size: 9, weight: .semibold)).padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Capsule().fill(colors.ink.opacity(keeper ? 0.10 : 0.045)))
                    }
                    Text(model.location(file.url.deletingLastPathComponent()) + "  ·  " + model.shortPath(file.url.deletingLastPathComponent()))
                        .font(.system(size: 11)).foregroundStyle(colors.muted).lineLimit(1).truncationMode(.middle)
                    Text(t("创建于 \(model.date(file.stamp.created))", "Created \(model.date(file.stamp.created))"))
                        .font(.system(size: 10)).foregroundStyle(colors.muted)
                }.frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help(file.url.path)
            if !keeper {
                Button(t("保留此份", "Keep this")) { model.keep(file) }
                    .buttonStyle(UnicoButtonStyle(colors: colors)).disabled(model.isCleaning)
            } else {
                Text(file.id == group.files.first?.id ? t("推荐保留", "Suggested") : t("手动保留", "Your choice"))
                    .font(.system(size: 10)).foregroundStyle(colors.muted).padding(.horizontal, 10)
            }
        }.padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(previewing ? colors.accent.opacity(0.055) : colors.canvas.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(previewing ? colors.accent.opacity(0.55) : Color.clear, lineWidth: 1))
    }

    private var footer: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.isCleaning ? t("正在核验并清理 \(model.cleanProcessed) / \(model.cleanTotal)", "Checking and cleaning \(model.cleanProcessed) / \(model.cleanTotal)") : t("已选 \(model.selectedCount) 个副本 · \(model.size(model.selectedBytes))", "\(englishCount(model.selectedCount, "copy", "copies")) selected · \(model.size(model.selectedBytes))"))
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                Text(t("确认副本所在位置不再需要。仅移到废纸篓，可恢复。", "Confirm these copies are no longer needed here. Recoverable from Trash."))
                    .font(.system(size: 11)).foregroundStyle(colors.muted)
            }
            Spacer(minLength: 0)
            if model.isCleaning {
                ProgressView().controlSize(.small)
                Button(model.cancelling ? t("正在停止…", "Stopping…") : t("停止清理", "Stop cleanup"), action: model.cancel)
                    .buttonStyle(UnicoButtonStyle(colors: colors)).disabled(model.cancelling)
            } else {
                Button { model.prompt = .clean } label: { Label(t("移到废纸篓", "Move to Trash"), systemImage: "trash") }
                    .buttonStyle(UnicoButtonStyle(colors: colors, primary: true)).disabled(model.selectedCount == 0)
            }
        }.padding(.horizontal, 24).padding(.vertical, 18)
    }

    private var issueSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("未处理的项目", "Unprocessed items")).font(.system(size: 23, weight: .medium))
            Text(t("这些项目没有被成功扫描或清理，不计作已处理。", "These items could not be scanned or cleaned. They are not counted as processed."))
                .font(.system(size: 12)).foregroundStyle(colors.muted)
            List(model.issues) { issue in
                VStack(alignment: .leading, spacing: 5) {
                    Text(issue.path).font(.system(size: 12)).textSelection(.enabled)
                    Text(t(issue.reason, issue.englishReason)).font(.system(size: 11)).foregroundStyle(colors.muted)
                }.padding(.vertical, 6)
            }.compatibleScrollBackground()
            HStack { Spacer(); Button(t("完成", "Done")) { model.showIssues = false }
                .buttonStyle(UnicoButtonStyle(colors: colors, primary: true)).keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 640, height: 430).background(colors.canvas)
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
