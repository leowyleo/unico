import Foundation

public struct Scanner {
    public init() {}
    public func scan(roots: [URL], wholeDisk: Bool = false, confirmedRoots: [URL] = [], token: CancellationToken,
                     progress: (ScanProgress) -> Void = { _ in }) throws -> ScanResult {
        let fm = FileManager.default
        // Whole-disk scans never inherit manual-folder confirmation.
        let confirmedRoots = wholeDisk ? [] : confirmedRoots.map { $0.standardizedFileURL }
        var records: [FileRecord] = []
        var seen = Set<String>()
        var issues: [ScanIssue] = []
        var excluded = 0
        var state = ScanProgress()
        var lastUpdate = Date.distantPast
        func report(_ force: Bool = false) {
            if force || Date().timeIntervalSince(lastUpdate) > 0.12 {
                progress(state); lastUpdate = Date()
            }
        }
        let keys: [URLResourceKey] = [.isPackageKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .volumeIsInternalKey]
        // Resolving only selected roots permits macOS /tmp aliases, while traversal never follows links.
        let normalized = Array(Set(roots.map { $0.resolvingSymlinksInPath().standardizedFileURL })).sorted { $0.path < $1.path }
        var uniqueRoots: [URL] = []
        for root in normalized {
            if !uniqueRoots.contains(where: { root.path == $0.path || root.path.hasPrefix($0.path == "/" ? "/" : $0.path + "/") }) { uniqueRoots.append(root) }
        }
        for root in uniqueRoots {
            try token.check()
            if !FileSafety.isConfirmed(root, roots: confirmedRoots) && FileSafety.excluded(root) { issues.append(.init(path: root.path, reason: "受保护或由应用管理的位置，已跳过", englishReason: "Protected or application-managed location. Skipped.")); continue }
            do {
                guard try FileStamp.read(root).isDirectory else { throw ScanError.unsafe }
                try FileSafety.verifyAncestors(root, confirmedRoots: confirmedRoots)
                if try !FileSafety.isConfirmed(root, roots: confirmedRoots) && FileSafety.protectedDirectory(root) { throw ScanError.unsafe }
                _ = try fm.contentsOfDirectory(atPath: root.path)
            } catch { issues.append(.init(path: root.path, error: error)); continue }
            guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { url, error in
                issues.append(.init(path: url.path, error: error))
                return !token.isCancelled
            }) else { issues.append(.init(path: root.path, reason: "无法读取目录", englishReason: "Could not read this folder.")); continue }
            while let url = walker.nextObject() as? URL {
                try token.check()
                state.currentPath = url.path
                if (!FileSafety.isConfirmed(url, roots: confirmedRoots) && FileSafety.excluded(url)) || (wholeDisk && url.path == "/Volumes") {
                    if (try? FileStamp.read(url).isDirectory) == true { walker.skipDescendants() }
                    excluded += 1; continue
                }
                do {
                    let stamp = try FileStamp.read(url)
                    // DirectoryEnumerator does not follow symlinks. Calling skipDescendants
                    // on a link can suppress traversal of the next real directory on macOS.
                    if stamp.isSymlink { excluded += 1; continue }
                    let values = try url.resourceValues(forKeys: Set(keys))
                    if try stamp.isDirectory && !FileSafety.isConfirmed(url, roots: confirmedRoots) && FileSafety.protectedDirectory(url) {
                        walker.skipDescendants()
                        excluded += 1; continue
                    }
                    if wholeDisk && values.volumeIsInternal != true {
                        if stamp.isDirectory { walker.skipDescendants() }
                        excluded += 1; continue
                    }
                    if stamp.isDirectory { report(); continue }
                    guard try FileSafety.isPersonalFile(url, stamp: stamp, confirmedRoots: confirmedRoots) else { excluded += 1; continue }
                    if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus != .current {
                        issues.append(.init(path: url.path, reason: "文件尚未下载到本机，已跳过", englishReason: "This cloud file is not downloaded. Skipped.")); continue
                    }
                    guard seen.insert(stamp.identity).inserted else { continue }
                    records.append(FileRecord(url: url, stamp: stamp))
                    state.scanned += 1
                } catch { issues.append(.init(path: url.path, error: error)) }
                report()
            }
        }
        try token.check()
        state.phase = "正在核验文件内容"
        state.englishPhase = "Verifying file contents"
        let sizeBuckets = Dictionary(grouping: records, by: \.size).values.filter { $0.count > 1 }
        state.totalToCheck = sizeBuckets.reduce(0) { $0 + $1.count }
        report(true)
        var groups: [DuplicateGroup] = []
        for bucket in sizeBuckets {
            var hashes: [String: [FileRecord]] = [:]
            for file in bucket {
                try token.check()
                state.currentPath = file.url.path
                do { hashes[try FileSafety.digest(file, token: token, confirmedRoots: confirmedRoots), default: []].append(file) }
                catch ScanError.cancelled { throw ScanError.cancelled }
                catch { issues.append(.init(path: file.url.path, error: error)) }
                state.checked += 1; report()
            }
            for matches in hashes.values where matches.count > 1 {
                var verified: [[FileRecord]] = []
                for file in matches {
                    try token.check()
                    var placed = false
                    do {
                        for index in verified.indices {
                            if try FileSafety.equal(verified[index][0], file, token: token, confirmedRoots: confirmedRoots) {
                                verified[index].append(file); placed = true; break
                            }
                        }
                        if !placed { try FileSafety.validate(file, confirmedRoots: confirmedRoots); verified.append([file]) }
                    } catch ScanError.cancelled { throw ScanError.cancelled }
                    catch { issues.append(.init(path: file.url.path, error: error)) }
                }
                for files in verified where files.count > 1 {
                    // A file may change after its comparison while other members are checked.
                    let stable = files.filter { file in
                        do { try FileSafety.validate(file, confirmedRoots: confirmedRoots); return true }
                        catch { issues.append(.init(path: file.url.path, error: error)); return false }
                    }
                    if stable.count > 1 { groups.append(DuplicateGroup(files: stable)) }
                }
                state.duplicateGroups = groups.count; report()
            }
        }
        try token.check()
        groups.sort { $0.redundantBytes == $1.redundantBytes ? $0.id < $1.id : $0.redundantBytes > $1.redundantBytes }
        report(true)
        return ScanResult(groups: groups, scanned: state.scanned, issues: issues, excluded: excluded)
    }
}
