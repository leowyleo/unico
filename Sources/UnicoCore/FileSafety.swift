import Foundation
import CryptoKit
import Darwin

public enum FileSafety {
    private static let protectedComponents: Set<String> = [
        "system", "library", "applications", "node_modules", "backups.backupdb",
        "bin", "sbin", "lib", "lib64", "vendor", "__pycache__", "venv",
        "caches", "containers", "application support"
    ]

    // Being byte-identical says nothing about whether an application needs both paths.
    // Only recognizable personal file formats are candidates; unknown formats stay untouched.
    private static let personalExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "webp", "bmp", "avif",
        "dng", "cr2", "cr3", "nef", "arw", "orf", "rw2", "raf", "psd", "ai", "svg",
        "pdf", "txt", "md", "rtf", "doc", "docx", "odt", "pages", "xls", "xlsx", "ods",
        "numbers", "csv", "ppt", "pptx", "odp", "key", "epub", "mobi",
        "mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg", "mp4", "mov", "m4v",
        "mkv", "avi", "webm", "zip", "7z", "rar", "tar", "gz", "bz2", "xz", "dmg"
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

    public static func excluded(_ url: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        if components.count > 1 && ["usr", "private", "dev", "cores", "network", "opt", "etc", "var", "tmp"].contains(components[1].lowercased()) { return true }
        return components.dropFirst().contains { component in
            component.hasPrefix(".") || protectedComponents.contains(component.lowercased()) || packageExtensions.contains((component as NSString).pathExtension.lowercased())
        }
    }

    public static func protectedDirectory(_ url: URL) throws -> Bool {
        if excluded(url) { return true }
        let values = try url.resourceValues(forKeys: [.isPackageKey, .isHiddenKey])
        if values.isPackage == true || values.isHidden == true { return true }
        return projectMarkers.contains { marker in
            // lstat detects marker links without following or reading them.
            (try? FileStamp.read(url.appendingPathComponent(marker))) != nil
        }
    }

    public static func isPersonalFile(_ url: URL, stamp: FileStamp, confirmedRoots: [URL] = []) throws -> Bool {
        if isConfirmed(url, roots: confirmedRoots) { return stamp.isRegular && stamp.links == 1 }
        guard !excluded(url), stamp.isRegular, stamp.links == 1, stamp.mode & 0o111 == 0,
              personalExtensions.contains(url.pathExtension.lowercased()) else { return false }
        return try url.resourceValues(forKeys: [.isHiddenKey]).isHidden != true
    }

    public static func verifyAncestors(_ url: URL, confirmedRoots: [URL] = []) throws {
        let confirmed = isConfirmed(url, roots: confirmedRoots)
        guard confirmed || !excluded(url) else { throw ScanError.unsafe }
        var parent = url.deletingLastPathComponent()
        while parent.path != "/" {
            let stamp = try FileStamp.read(parent)
            guard stamp.isDirectory && !stamp.isSymlink else { throw ScanError.unsafe }
            if try !confirmed && protectedDirectory(parent) { throw ScanError.unsafe }
            parent.deleteLastPathComponent()
        }
    }

    public static func validate(_ record: FileRecord, confirmedRoots: [URL] = []) throws {
        try verifyAncestors(record.url, confirmedRoots: confirmedRoots)
        let current = try FileStamp.read(record.url)
        guard try isPersonalFile(record.url, stamp: current, confirmedRoots: confirmedRoots) else { throw ScanError.unsafe }
        guard current == record.stamp else { throw ScanError.changed }
    }

    private static func openVerified(_ record: FileRecord, confirmedRoots: [URL]) throws -> FileHandle {
        try validate(record, confirmedRoots: confirmedRoots)
        let fd = open(record.url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw ScanError.unreadable(String(cString: strerror(errno))) }
        var info = stat()
        guard fstat(fd, &info) == 0, FileStamp(info) == record.stamp else {
            close(fd); throw ScanError.changed
        }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    public static func digest(_ record: FileRecord, token: CancellationToken, confirmedRoots: [URL] = []) throws -> String {
        let handle = try openVerified(record, confirmedRoots: confirmedRoots)
        defer { try? handle.close() }
        var hash = SHA256()
        while true {
            try token.check()
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hash.update(data: data)
        }
        try validate(record, confirmedRoots: confirmedRoots)
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // Hashing narrows candidates; final grouping and cleanup compare every byte.
    public static func equal(_ first: FileRecord, _ second: FileRecord, token: CancellationToken, confirmedRoots: [URL] = []) throws -> Bool {
        guard first.stamp.identity != second.stamp.identity, first.size == second.size else { return false }
        let a = try openVerified(first, confirmedRoots: confirmedRoots)
        defer { try? a.close() }
        let b = try openVerified(second, confirmedRoots: confirmedRoots)
        defer { try? b.close() }
        while true {
            try token.check()
            let left = try a.read(upToCount: 1024 * 1024) ?? Data()
            let right = try b.read(upToCount: 1024 * 1024) ?? Data()
            if left != right { return false }
            if left.isEmpty { break }
        }
        try validate(first, confirmedRoots: confirmedRoots)
        try validate(second, confirmedRoots: confirmedRoots)
        return true
    }
}
