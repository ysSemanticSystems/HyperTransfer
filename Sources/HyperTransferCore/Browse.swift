import Darwin
import Foundation

public let previewLimit = 4096

public struct DirectoryEntry: Equatable, Sendable, Identifiable {
    public var id: String { relative }
    public var name: String
    public var kind: String
    public var size: Int?
    public var modified: String?
    public var hidden: Bool
    public var relative: String
    public var leavesRoot: Bool
}

public struct DirectoryListing: Equatable, Sendable {
    public var path: String
    public var parent: String?
    public var entries: [DirectoryEntry]
    public var truncated: Bool = false
}

public struct FilePreview: Equatable, Sendable {
    public var path: String
    public var kind: String
    public var body: String
    public var windowBytes: Int
    public var fileBytes: Int
    public var truncated: Bool
    public var limit: Int
}

public func listDirectory(root: URL, relative: String) throws -> DirectoryListing {
    let base = root.resolvingSymlinksInPath().standardizedFileURL
    let target = try resolveInside(root: base, relative: relative)
    guard !isSymlink(target), target.isDirectory else {
        throw TransferError.refused("That path is not a folder inside this root.")
    }
    let children = (try? FileManager.default.contentsOfDirectory(
        at: target,
        includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
        options: []
    )) ?? []
    let entries = children.map { entry(root: base, child: $0) }.sorted { lhs, rhs in
        let order = ["folder": 0, "file": 1, "partial": 2, "link": 3, "other": 4]
        let left = order[lhs.kind, default: 9]
        let right = order[rhs.kind, default: 9]
        if left != right { return left < right }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
    let shown = relativePath(root: base, path: target)
    let parent: String?
    if shown == "." {
        parent = nil
    } else {
        let up = (shown as NSString).deletingLastPathComponent
        parent = up.isEmpty ? "." : up
    }
    return DirectoryListing(path: shown, parent: parent, entries: entries)
}

public func previewFile(root: URL, relative: String, limit: Int = previewLimit) throws -> FilePreview {
    let base = root.resolvingSymlinksInPath().standardizedFileURL
    let target = try resolveInside(root: base, relative: relative)
    guard !isSymlink(target), target.isRegularFile else {
        throw TransferError.refused("Preview reads a regular file. This path is not one.")
    }
    let fd = Darwin.open(target.path, O_RDONLY)
    if fd < 0 {
        throw TransferError.refused("That file could not be read.")
    }
    defer { Darwin.close(fd) }
    var info = stat()
    let fileBytes = fstat(fd, &info) == 0 ? Int(info.st_size) : 0
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: limit + 1)
    defer { buffer.deallocate() }
    var collected = Data()
    var remaining = limit + 1
    while remaining > 0 {
        let n = readEINTR(fd, buffer, remaining)
        if n == 0 { break }
        if n < 0 { break }
        collected.append(buffer, count: n)
        remaining -= n
    }
    let truncated = collected.count > limit
    let window = truncated ? collected.prefix(limit) : collected[...]
    let body: String
    let kind: String
    if let text = String(data: Data(window), encoding: .utf8) {
        body = text
        kind = "text"
    } else {
        body = Data(window).map { String(format: "%02x", $0) }.joined()
        kind = "hex"
    }
    return FilePreview(
        path: relativePath(root: base, path: target),
        kind: kind,
        body: body,
        windowBytes: window.count,
        fileBytes: fileBytes,
        truncated: truncated,
        limit: limit
    )
}

public func resolveInside(root: URL, relative: String) throws -> URL {
    let base = root.resolvingSymlinksInPath().standardizedFileURL
    if relative.isEmpty || relative == "." { return base }
    let parts = try pathParts(relative)
    var cursor = base
    for part in parts {
        cursor.append(component: part, directoryHint: .notDirectory)
        if isSymlink(cursor) {
            throw TransferError.refused("That path uses a symlink. Symlinks are listed and not opened.")
        }
    }
    guard cursor.exists else {
        throw TransferError.refused("That path is not there.")
    }
    let landed = cursor.resolvingSymlinksInPath().standardizedFileURL
    guard landed.path == base.path || landed.path.hasPrefix(base.path + "/") else {
        throw TransferError.refused("That path leaves this root.")
    }
    return cursor.standardizedFileURL
}

public func resolvePlace(root: URL, relative: String) throws -> URL {
    let base = root.resolvingSymlinksInPath().standardizedFileURL
    if relative.isEmpty || relative == "." { return base }
    let parts = try pathParts(relative)
    var cursor = base
    if parts.count > 1 {
        for part in parts.dropLast() {
            cursor.append(component: part, directoryHint: .isDirectory)
            if isSymlink(cursor) {
                throw TransferError.refused("That path uses a symlink. Symlinks are listed and not opened.")
            }
            guard cursor.isDirectory else {
                throw TransferError.refused("That destination folder is not there.")
            }
        }
    }
    cursor.append(component: parts[parts.count - 1], directoryHint: .notDirectory)
    if isSymlink(cursor) {
        throw TransferError.refused("That path uses a symlink. Symlinks are listed and not opened.")
    }
    let parent = cursor.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
    guard parent.path == base.path || parent.path.hasPrefix(base.path + "/") else {
        throw TransferError.refused("That path leaves this root.")
    }
    return cursor.standardizedFileURL
}

private func pathParts(_ text: String) throws -> [String] {
    if text.hasPrefix("/") || text.hasPrefix("~") || text.contains("\0") {
        throw TransferError.refused("That path leaves this root.")
    }
    let parts = text.split(separator: "/", omittingEmptySubsequences: true).map(String.init).filter { $0 != "." }
    if parts.isEmpty || parts.contains("..") {
        throw TransferError.refused("That path leaves this root.")
    }
    return parts
}

private func entry(root: URL, child: URL) -> DirectoryEntry {
    let name = child.lastPathComponent
    let hidden = name.hasPrefix(".")
    let relative = relativePath(root: root, path: child)
    if isSymlink(child) {
        return DirectoryEntry(
            name: name, kind: "link", size: nil, modified: modified(child),
            hidden: hidden, relative: relative, leavesRoot: linkLeaves(root: root, child: child)
        )
    }
    if child.isDirectory {
        return DirectoryEntry(
            name: name, kind: "folder", size: nil, modified: modified(child),
            hidden: hidden, relative: relative, leavesRoot: false
        )
    }
    if child.isRegularFile {
        let kind = name.hasSuffix(".ht-partial") ? "partial" : "file"
        var info = stat()
        let size = stat(child.path, &info) == 0 ? Int(info.st_size) : nil
        return DirectoryEntry(
            name: name, kind: kind, size: size, modified: modified(child),
            hidden: hidden, relative: relative, leavesRoot: false
        )
    }
    return DirectoryEntry(
        name: name, kind: "other", size: nil, modified: modified(child),
        hidden: hidden, relative: relative, leavesRoot: false
    )
}

private func linkLeaves(root: URL, child: URL) -> Bool {
    let raw = (try? FileManager.default.destinationOfSymbolicLink(atPath: child.path)) ?? ""
    if raw.isEmpty { return true }
    let target = raw.hasPrefix("/") ? URL(fileURLWithPath: raw) : child.deletingLastPathComponent().appendingPathComponent(raw)
    let landed = target.resolvingSymlinksInPath().standardizedFileURL
    return landed.path != root.path && !landed.path.hasPrefix(root.path + "/")
}

private func modified(_ url: URL) -> String? {
    var info = stat()
    let path = url.path
    let rc = lstat(path, &info)
    if rc != 0 { return nil }
    let date = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return formatter.string(from: date)
}

private func relativePath(root: URL, path: URL) -> String {
    let rootPath = root.standardizedFileURL.path
    let childPath = path.standardizedFileURL.path
    if childPath == rootPath { return "." }
    let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    if childPath.hasPrefix(prefix) {
        return String(childPath.dropFirst(prefix.count))
    }
    return path.lastPathComponent
}

private extension URL {
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
    var isDirectory: Bool {
        guard !isSymlink(self) else { return false }
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue
    }
    var isRegularFile: Bool {
        guard !isSymlink(self) else { return false }
        var info = stat()
        guard stat(path, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFREG
    }
}
