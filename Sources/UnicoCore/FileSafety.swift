import Foundation
import CryptoKit
import Darwin

public enum FileTypeCategory: String, CaseIterable, Hashable, Sendable, Identifiable {
    case media
    case documents
    case archivesAndInstallers
    case scripts
    case other

    public var id: String { rawValue }

    public static let defaultIncluded: Set<Self> = [.media, .documents, .archivesAndInstallers]

    public static func category(for url: URL) -> Self {
        let ext = url.pathExtension.lowercased()
        if mediaExtensions.contains(ext) { return .media }
        if documentExtensions.contains(ext) { return .documents }
        if archiveAndInstallerExtensions.contains(ext) { return .archivesAndInstallers }
        if scriptExtensions.contains(ext) { return .scripts }
        return .other
    }

    private static let mediaExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "webp", "bmp", "avif",
        "dng", "cr2", "cr3", "nef", "arw", "orf", "rw2", "raf", "psd", "ai", "svg",
        "mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg", "mp4", "mov", "m4v", "mkv", "avi", "webm"
    ]
    private static let documentExtensions: Set<String> = [
        "pdf", "txt", "md", "rtf", "doc", "docx", "odt", "pages", "xls", "xlsx", "ods",
        "numbers", "csv", "ppt", "pptx", "odp", "key", "epub", "mobi"
    ]
    private static let archiveAndInstallerExtensions: Set<String> = [
        "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "zst", "cab", "iso", "dmg", "pkg", "mpkg"
    ]
    private static let scriptExtensions: Set<String> = [
        "swift", "py", "js", "mjs", "cjs", "ts", "tsx", "jsx", "java", "c", "h", "m", "mm", "cc", "cpp",
        "cxx", "cs", "go", "rs", "rb", "php", "pl", "lua", "r", "sh", "bash", "zsh", "fish", "sql",
        "html", "htm", "css", "scss", "sass", "less", "json", "yaml", "yml", "toml", "xml"
    ]
}

public struct ScanRules: Sendable, Equatable {
    public var includedFileTypes: Set<FileTypeCategory>
    public var skipHiddenFiles: Bool
    public var minimumFileSize: Int64
    public var ignoredPaths: [String]

    public init(
        includedFileTypes: Set<FileTypeCategory> = FileTypeCategory.defaultIncluded,
        skipHiddenFiles: Bool = true,
        minimumFileSize: Int64 = 0,
        ignoredPaths: [String] = []
    ) {
        self.includedFileTypes = includedFileTypes
        self.skipHiddenFiles = skipHiddenFiles
        self.minimumFileSize = max(0, minimumFileSize)
        self.ignoredPaths = ignoredPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
    }

    public func ignores(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return ignoredPaths.contains { ignored in path == ignored || path.hasPrefix(ignored + "/") }
    }
}

public enum FileSafety {
    private static let protectedComponents: Set<String> = [
        "system", "library", "applications", "node_modules", "backups.backupdb",
        "bin", "sbin", "lib", "lib64", "vendor", "__pycache__", "venv",
        "caches", "containers", "application support"
    ]

    private static let projectMarkers = [
        ".git", ".hg", ".svn", "Package.swift", "package.json", "pyproject.toml",
        "Cargo.toml", "go.mod", "CMakeLists.txt", "Makefile", "pom.xml", "build.gradle",
        "build.gradle.kts", "requirements.txt", "Pipfile"
    ]
    private static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "plugin", "kext", "photoslibrary", "photolibrary",
        "musiclibrary", "imovielibrary", "fcpbundle", "backupbundle", "sparsebundle",
        "playground", "xcodeproj", "xcworkspace"
    ]

    // Confirmation is scoped to selected paths, never a global switch.
    public static func isConfirmed(_ url: URL, roots: [URL]) -> Bool {
        let path = url.standardizedFileURL.path
        return roots.contains {
            let root = $0.standardizedFileURL.path
            return path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
        }
    }

    public static func excluded(_ url: URL, skipHiddenFiles: Bool = true) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        if components.count > 1 && ["usr", "private", "dev", "cores", "network", "opt", "etc", "var", "tmp"].contains(components[1].lowercased()) { return true }
        return components.dropFirst().contains { component in
            (skipHiddenFiles && component.hasPrefix(".")) || protectedComponents.contains(component.lowercased()) || packageExtensions.contains((component as NSString).pathExtension.lowercased())
        }
    }

    public static func isSystemOrProtected(_ url: URL) -> Bool { excluded(url) }

    public static func protectedDirectory(_ url: URL, skipHiddenFiles: Bool = true) throws -> Bool {
        if excluded(url, skipHiddenFiles: skipHiddenFiles) { return true }
        let values = try url.resourceValues(forKeys: [.isPackageKey, .isHiddenKey])
        if values.isPackage == true || (skipHiddenFiles && values.isHidden == true) { return true }
        return projectMarkers.contains { marker in
            // lstat detects marker links without following or reading them.
            (try? FileStamp.read(url.appendingPathComponent(marker))) != nil
        }
    }

    public static func isPersonalFile(_ url: URL, stamp: FileStamp, confirmedRoots: [URL] = [], scanRules: ScanRules = ScanRules()) throws -> Bool {
        guard scanRules.includedFileTypes.contains(FileTypeCategory.category(for: url)),
              !scanRules.ignores(url),
              !excluded(url, skipHiddenFiles: scanRules.skipHiddenFiles),
              stamp.size >= scanRules.minimumFileSize,
              stamp.isRegular,
              stamp.links == 1 else { return false }
        if isConfirmed(url, roots: confirmedRoots) { return true }
        guard stamp.mode & 0o111 == 0 else { return false }
        if !scanRules.skipHiddenFiles { return true }
        return try url.resourceValues(forKeys: [.isHiddenKey]).isHidden != true
    }

    public static func verifyAncestors(_ url: URL, confirmedRoots: [URL] = [], skipHiddenFiles: Bool = true) throws {
        let confirmed = isConfirmed(url, roots: confirmedRoots)
        guard confirmed || !excluded(url, skipHiddenFiles: skipHiddenFiles) else { throw ScanError.unsafe }
        var parent = url.deletingLastPathComponent()
        while parent.path != "/" {
            let stamp = try FileStamp.read(parent)
            guard stamp.isDirectory && !stamp.isSymlink else { throw ScanError.unsafe }
            if try !confirmed && protectedDirectory(parent, skipHiddenFiles: skipHiddenFiles) { throw ScanError.unsafe }
            parent.deleteLastPathComponent()
        }
    }

    public static func validate(_ record: FileRecord, confirmedRoots: [URL] = [], scanRules: ScanRules = ScanRules()) throws {
        try verifyAncestors(record.url, confirmedRoots: confirmedRoots, skipHiddenFiles: scanRules.skipHiddenFiles)
        let current = try FileStamp.read(record.url)
        guard try isPersonalFile(record.url, stamp: current, confirmedRoots: confirmedRoots, scanRules: scanRules) else { throw ScanError.unsafe }
        guard current == record.stamp else { throw ScanError.changed }
    }

    private static func openVerified(_ record: FileRecord, confirmedRoots: [URL], scanRules: ScanRules) throws -> FileHandle {
        try validate(record, confirmedRoots: confirmedRoots, scanRules: scanRules)
        let fd = open(record.url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw ScanError.unreadable(String(cString: strerror(errno))) }
        var info = stat()
        guard fstat(fd, &info) == 0, FileStamp(info) == record.stamp else {
            close(fd); throw ScanError.changed
        }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    public static func digest(_ record: FileRecord, token: CancellationToken, confirmedRoots: [URL] = [], scanRules: ScanRules = ScanRules()) throws -> String {
        let handle = try openVerified(record, confirmedRoots: confirmedRoots, scanRules: scanRules)
        defer { try? handle.close() }
        var hash = SHA256()
        while true {
            try token.check()
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hash.update(data: data)
        }
        try validate(record, confirmedRoots: confirmedRoots, scanRules: scanRules)
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // Hashing narrows candidates; final grouping and cleanup compare every byte.
    public static func equal(_ first: FileRecord, _ second: FileRecord, token: CancellationToken, confirmedRoots: [URL] = [], scanRules: ScanRules = ScanRules()) throws -> Bool {
        guard first.stamp.identity != second.stamp.identity, first.size == second.size else { return false }
        let a = try openVerified(first, confirmedRoots: confirmedRoots, scanRules: scanRules)
        defer { try? a.close() }
        let b = try openVerified(second, confirmedRoots: confirmedRoots, scanRules: scanRules)
        defer { try? b.close() }
        while true {
            try token.check()
            let left = try a.read(upToCount: 1024 * 1024) ?? Data()
            let right = try b.read(upToCount: 1024 * 1024) ?? Data()
            if left != right { return false }
            if left.isEmpty { break }
        }
        try validate(first, confirmedRoots: confirmedRoots, scanRules: scanRules)
        try validate(second, confirmedRoots: confirmedRoots, scanRules: scanRules)
        return true
    }
}
