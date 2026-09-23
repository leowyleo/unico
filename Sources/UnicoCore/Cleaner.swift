import Foundation

public struct Cleaner {
    public init() {}
    public func clean(groups: [DuplicateGroup], confirmedRoots: [URL] = [], scanRules: ScanRules = ScanRules(), token: CancellationToken,
                      progress: (Int) -> Void = { _ in }) -> CleanupResult {
        clean(groups: groups, confirmedRoots: confirmedRoots, scanRules: scanRules, token: token, trash: { url in
            var destination: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
            guard let destination = destination as URL? else { throw ScanError.trashVerificationFailed }
            return destination
        }, progress: progress)
    }

    // Injection is internal and available to safety tests only; the app always uses Trash.
    func clean(groups: [DuplicateGroup], confirmedRoots: [URL] = [], scanRules: ScanRules = ScanRules(), token: CancellationToken,
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
                    guard try FileSafety.equal(keeper, candidate, token: token, confirmedRoots: confirmedRoots, scanRules: scanRules) else { throw ScanError.changed }
                    try token.check()
                    try FileSafety.validate(keeper, confirmedRoots: confirmedRoots, scanRules: scanRules)
                    try FileSafety.validate(candidate, confirmedRoots: confirmedRoots, scanRules: scanRules)
                    let destination = try trash(candidate.url)
                    try verifyTrashMove(from: candidate.url, to: destination)
                    result.trashed[candidate.id] = destination
                } catch ScanError.cancelled { result.cancelled = true; return result }
                catch { result.issues.append(.init(path: candidate.id, error: error)) }
            }
        }
        return result
    }

    private func verifyTrashMove(from original: URL, to destination: URL) throws {
        let originalPath = original.standardizedFileURL.path
        let destinationPath = destination.standardizedFileURL.path
        guard !destinationPath.isEmpty, destinationPath != originalPath else {
            throw ScanError.trashVerificationFailed
        }

        var relationship = FileManager.URLRelationship.other
        do {
            try FileManager.default.getRelationship(
                &relationship,
                of: .trashDirectory,
                in: [],
                toItemAt: destination
            )
        } catch {
            throw ScanError.trashVerificationFailed
        }
        guard relationship == .contains else {
            throw ScanError.trashVerificationFailed
        }
    }
}
