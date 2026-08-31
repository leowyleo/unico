import Foundation

public struct Cleaner {
    public init() {}
    public func clean(groups: [DuplicateGroup], confirmedRoots: [URL] = [], token: CancellationToken,
                      progress: (Int) -> Void = { _ in }) -> CleanupResult {
        clean(groups: groups, confirmedRoots: confirmedRoots, token: token, trash: { url in
            var destination: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
            return destination as URL? ?? url
        }, progress: progress)
    }

    // Injection is internal and available to safety tests only; the app always uses Trash.
    func clean(groups: [DuplicateGroup], confirmedRoots: [URL] = [], token: CancellationToken,
               trash: (URL) throws -> URL, progress: (Int) -> Void = { _ in }) -> CleanupResult {
        var result = CleanupResult()
        var processed = 0
        var consumed = Set<String>()
        for group in groups {
            guard let keeper = group.files.first(where: { $0.id == group.keeperID }),
                  !group.selectedIDs.contains(keeper.id), group.files.count > 1 else {
                result.issues.append(.init(path: group.id, reason: "缺少保留文件，整组已跳过", englishReason: "No file was marked to keep. The entire group was skipped.")); continue
            }
            for candidate in group.files where group.selectedIDs.contains(candidate.id) {
                if token.isCancelled { result.cancelled = true; return result }
                defer { processed += 1; progress(processed) }
                guard consumed.insert(candidate.id).inserted else { continue }
                do {
                    guard try FileSafety.equal(keeper, candidate, token: token, confirmedRoots: confirmedRoots) else { throw ScanError.changed }
                    try token.check()
                    try FileSafety.validate(keeper, confirmedRoots: confirmedRoots)
                    try FileSafety.validate(candidate, confirmedRoots: confirmedRoots)
                    result.trashed[candidate.id] = try trash(candidate.url)
                } catch ScanError.cancelled { result.cancelled = true; return result }
                catch { result.issues.append(.init(path: candidate.id, error: error)) }
            }
        }
        return result
    }
}
