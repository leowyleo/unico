import Foundation
import Darwin

public final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    public func check() throws { if isCancelled { throw ScanError.cancelled } }
}

public enum ScanError: Error, LocalizedError {
    case cancelled, changed, unsafe, unreadable(String)
    public var errorDescription: String? {
        switch self {
        case .cancelled: return "操作已取消"
        case .changed: return "文件已变化或无法确认内容一致，请重新扫描"
        case .unsafe: return "受保护的内容、链接或非普通文件，已跳过"
        case .unreadable(let reason): return reason
        }
    }
}

public struct FileStamp: Equatable, Sendable {
    public let device: Int32
    public let inode: UInt64
    public let size: Int64
    public let links: UInt16
    public let mode: UInt16
    public let modifiedSeconds: Int
    public let modifiedNanos: Int
    public let changedSeconds: Int
    public let changedNanos: Int
    public let created: Date
    init(_ value: stat) {
        device = value.st_dev; inode = value.st_ino; size = value.st_size
        links = value.st_nlink; mode = value.st_mode
        modifiedSeconds = value.st_mtimespec.tv_sec; modifiedNanos = value.st_mtimespec.tv_nsec
        changedSeconds = value.st_ctimespec.tv_sec; changedNanos = value.st_ctimespec.tv_nsec
        created = Date(timeIntervalSince1970: Double(value.st_birthtimespec.tv_sec) + Double(value.st_birthtimespec.tv_nsec) / 1e9)
    }
    public var identity: String { "\(device):\(inode)" }
    public var isRegular: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFREG) }
    public var isDirectory: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFDIR) }
    public var isSymlink: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFLNK) }
    public static func read(_ url: URL) throws -> FileStamp {
        var value = stat()
        guard lstat(url.path, &value) == 0 else {
            throw ScanError.unreadable(String(cString: strerror(errno)))
        }
        return FileStamp(value)
    }
}

public struct FileRecord: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let stamp: FileStamp
    public var name: String { url.lastPathComponent }
    public var size: Int64 { stamp.size }
    public init(url: URL, stamp: FileStamp) { self.url = url; self.stamp = stamp }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.stamp == rhs.stamp }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public struct DuplicateGroup: Identifiable, Sendable {
    public let id: String
    public var files: [FileRecord]
    public var keeperID: String
    public var selectedIDs: Set<String>
    public init(files: [FileRecord]) {
        self.files = files.sorted {
            if $0.stamp.created != $1.stamp.created { return $0.stamp.created < $1.stamp.created }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
        id = self.files[0].id
        keeperID = self.files[0].id
        selectedIDs = Set(self.files.dropFirst().map(\.id))
    }
    public var selectedBytes: Int64 { files.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.size } }
    public var redundantBytes: Int64 { Int64(max(0, files.count - 1)) * (files.first?.size ?? 0) }
    public mutating func keep(_ file: FileRecord) {
        guard files.contains(file), file.id != keeperID else { return }
        selectedIDs.insert(keeperID)
        keeperID = file.id
        selectedIDs.remove(file.id)
    }
}

public struct ScanIssue: Identifiable, Sendable {
    public let id = UUID()
    public let path: String
    public let reason: String
    public let englishReason: String
    public init(path: String, reason: String, englishReason: String) {
        self.path = path; self.reason = reason; self.englishReason = englishReason
    }
    public init(path: String, error: Error) {
        self.path = path; self.reason = error.localizedDescription
        self.englishReason = englishErrorDescription(error)
    }
}

public struct ScanProgress: Sendable {
    public var phase = "正在读取文件"
    public var englishPhase = "Reading files"
    public var scanned = 0
    public var checked = 0
    public var totalToCheck = 0
    public var duplicateGroups = 0
    public var currentPath = ""
    public init() {}
}

public struct ScanResult: Sendable {
    public var groups: [DuplicateGroup]
    public var scanned: Int
    public var issues: [ScanIssue]
    public var excluded: Int
}

public struct CleanupResult: Sendable {
    public var trashed: [String: URL] = [:]
    public var issues: [ScanIssue] = []
    public var cancelled = false
    public init() {}
}

// Application messages are translated explicitly; OS error details stay intact for diagnosis.
public func englishErrorDescription(_ error: Error) -> String {
    if let scan = error as? ScanError {
        switch scan {
        case .cancelled: return "Operation cancelled"
        case .changed: return "The file changed or could not be verified. Scan again."
        case .unsafe: return "Protected content, link, or unsupported file. Skipped."
        case .unreadable(let detail): return "Could not read this item. \(detail)"
        }
    }
    let value = error as NSError
    if value.domain == NSCocoaErrorDomain {
        switch value.code {
        case NSFileReadNoPermissionError, NSFileWriteNoPermissionError: return "Permission denied. The item was not processed."
        case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return "The item no longer exists. Scan again."
        default: break
        }
    }
    return "Could not process this item (\(value.domain), \(value.code))."
}
