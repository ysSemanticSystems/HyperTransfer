import CryptoKit
import Darwin
import Foundation

public let defaultChunkSize = 1024 * 1024

public struct Receipt: Equatable, Sendable {
    public var source: String
    public var destination: String
    public var promoted: Bool
    public var code: TransferCode
    public var word: String
    public var tone: StatusTone
    public var summary: String
    public var before: Digest?
    public var destinationHash: Digest?
    public var after: Digest?
    public var byteCount: Int
    public var transferSeconds: Double
    public var hashBeforeSeconds: Double
    public var hashDestinationSeconds: Double
    public var hashAfterSeconds: Double
    public var rateBytesPerSecond: Double?
    public var sampleShort: Bool
    public var sync: String
    public var metadataLeftBehind: [String]
    public var inodeChanged: Bool
    public var partial: String?
    public var osStamps: [String]
    public var sent: Digest?
}

public struct SkippedEntry: Equatable, Sendable {
    public var path: String
    public var reason: String
}

public struct FolderResult: Equatable, Sendable {
    public var code: TransferCode
    public var word: String
    public var tone: StatusTone
    public var summary: String
    public var files: [Receipt]
    public var skipped: [SkippedEntry]
}

public func transferFile(
    source: URL,
    destination: URL,
    endpoint: ChunkEndpoint,
    replace: Bool = false,
    chunkSize: Int = defaultChunkSize,
    afterFirstHash: ((URL) -> Void)? = nil,
    promote: (URL, URL) -> String? = promotePartial
) -> Receipt {
    if let refusal = refuseFile(source: source, destination: destination, replace: replace) {
        return early(source, destination, refusal.0, refusal.1)
    }
    let before: HashRead
    do {
        before = try hashFile(at: source, dropCache: false)
    } catch let error as TransferError {
        return early(source, destination, error.code, error.detail)
    } catch {
        return early(source, destination, .ioError, "The first hash could not read the source.")
    }
    let identity = fileIdentity(source)
    afterFirstHash?(source)

    let partial = partialURL(destination)
    let started = DispatchTime.now().uptimeNanoseconds
    var failure: TransferError?
    var written = 0
    var sync = ""
    let inFD = Darwin.open(source.path, O_RDONLY)
    if inFD < 0 {
        return early(source, destination, .ioError, errnoString("The copy could not open the source"))
    }
    defer { Darwin.close(inFD) }
    let outFD = Darwin.open(partial.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    if outFD < 0 {
        return early(source, destination, .ioError, errnoString("The copy could not open the partial file"))
    }
    defer { Darwin.close(outFD) }

    var sentSHA = SHA512()
    var sentBlake = Blake2b()
    var offset = 0
    var index: UInt32 = 0
    while failure == nil {
        let payload: Data
        do {
            payload = try readChunk(inFD, chunkSize)
        } catch {
            failure = TransferError(.ioError, "The copy stopped while reading the source.")
            break
        }
        if payload.isEmpty && offset > 0 {
            break
        }
        do {
            try endpoint.land(chunkIndex: index, offset: UInt64(offset), payload: payload)
            let visible = try takeChunk(
                cookie: endpoint.cpuCookie(),
                payload: endpoint.cpuPayload(offset: offset, count: payload.count),
                chunkIndex: index
            )
            guard visible == payload else {
                failure = TransferError.writeIncomplete(
                    "The notified bytes differ from the bytes read from the source."
                )
                break
            }
            try writeAll(outFD, visible)
            written += visible.count
            sentSHA.update(data: visible)
            sentBlake.update(visible)
        } catch let error as TransferError {
            failure = error
            break
        } catch {
            failure = TransferError(.ioError, "The copy stopped while moving bytes.")
            break
        }
        offset += payload.count
        index += 1
        if payload.count < chunkSize { break }
    }
    if failure == nil {
        sync = syncFile(outFD)
    }
    let transferSeconds = Double(DispatchTime.now().uptimeNanoseconds &- started) / 1_000_000_000
    let sent = Digest(
        sha512: sentSHA.finalize().hex,
        blake2b: sentBlake.finalize().hexString,
        byteCount: written,
        cache: "posted-bytes"
    )
    let destOutcome = hashOutcome(partial, dropCache: true)
    let afterOutcome = source.isRegularFile ? hashOutcome(source, dropCache: true) : .missing
    let notes = FileManager.default.fileExists(atPath: source.path) ? fileNotes(at: source) : FileNotes(leftBehind: [], stamps: [])
    let inodeChanged = identity != fileIdentity(source)
    if case .failed(let error) = destOutcome {
        return failedRead(source, destination, before, error, written, transferSeconds, sync, notes, inodeChanged, partial, sent)
    }
    if case .failed(let error) = afterOutcome {
        return failedRead(source, destination, before, error, written, transferSeconds, sync, notes, inodeChanged, partial, sent)
    }
    let destRead = destOutcome.hashRead
    let after = afterOutcome.hashRead

    if let failure {
        var summary = failure.detail
        if let destRead, let after {
            summary += " " + judge(before: before.digest, destination: destRead.digest, after: after.digest).summary
        }
        return done(
            source: source, destination: destination, promoted: false, code: failure.code,
            word: "Down", tone: .down, summary: summary, before: before, destRead: destRead, after: after,
            byteCount: written, transferSeconds: transferSeconds, sync: sync, meta: notes.leftBehind,
            inodeChanged: inodeChanged, partial: partial.exists ? partial : nil, osStamps: notes.stamps, sent: sent
        )
    }
    guard let destRead, let after else {
        return done(
            source: source, destination: destination, promoted: false, code: .ioError,
            word: "Down", tone: .down,
            summary: "A hash after the copy could not be read, so the file was not renamed into place.",
            before: before, destRead: destRead, after: after, byteCount: written,
            transferSeconds: transferSeconds, sync: sync, meta: notes.leftBehind,
            inodeChanged: inodeChanged, partial: partial.exists ? partial : nil, osStamps: notes.stamps, sent: sent
        )
    }
    let verdict = judge(before: before.digest, destination: destRead.digest, after: after.digest)
    if verdict.code != .match {
        return done(
            source: source, destination: destination, promoted: false, code: verdict.code,
            word: "Down", tone: .down, summary: verdict.summary, before: before, destRead: destRead,
            after: after, byteCount: written, transferSeconds: transferSeconds, sync: sync,
            meta: notes.leftBehind, inodeChanged: inodeChanged, partial: partial, osStamps: notes.stamps, sent: sent
        )
    }
    if !sent.sameBytes(as: before.digest) {
        return done(
            source: source, destination: destination, promoted: false, code: .sentDisagreed,
            word: "Down", tone: .down,
            summary: "The bytes read for the copy do not match the measurement taken before the copy.",
            before: before, destRead: destRead, after: after, byteCount: written,
            transferSeconds: transferSeconds, sync: sync, meta: notes.leftBehind,
            inodeChanged: inodeChanged, partial: partial, osStamps: notes.stamps, sent: sent
        )
    }
    if let renameError = promote(partial, destination) {
        return done(
            source: source, destination: destination, promoted: false, code: .renameFailed,
            word: "Down", tone: .down,
            summary: "SHA-512 and BLAKE2b match. The finished name was not written (\(renameError)). The partial file is still beside it.",
            before: before, destRead: destRead, after: after, byteCount: written,
            transferSeconds: transferSeconds, sync: sync, meta: notes.leftBehind,
            inodeChanged: inodeChanged, partial: partial.exists ? partial : nil, osStamps: notes.stamps, sent: sent
        )
    }
    var summary: String
    let code: TransferCode
    let word: String
    let tone: StatusTone
    if notes.leftBehind.isEmpty {
        summary = verdict.summary
        code = .match
        word = "Match"
        tone = .up
    } else {
        summary = "SHA-512 and BLAKE2b match on the data fork. Left behind: \(notes.leftBehind.joined(separator: ", "))."
        code = .dataForkMatches
        word = "Data fork"
        tone = .place
    }
    if !notes.stamps.isEmpty {
        summary += " Kept by this Mac, and not part of the hash: \(notes.stamps.joined(separator: ", "))."
    }
    if inodeChanged {
        summary += " The source inode changed between the two reads."
    }
    summary += " " + cacheNote(destination: destRead.digest, after: after.digest)
    return done(
        source: source, destination: destination, promoted: true, code: code, word: word, tone: tone,
        summary: summary, before: before, destRead: destRead, after: after, byteCount: written,
        transferSeconds: transferSeconds, sync: sync, meta: notes.leftBehind, inodeChanged: inodeChanged,
        partial: nil, osStamps: notes.stamps, sent: sent
    )
}

public func transferDirectory(
    source: URL,
    destination: URL,
    endpointFactory: () -> ChunkEndpoint,
    replace: Bool = false,
    chunkSize: Int = defaultChunkSize
) -> FolderResult {
    if isSymlink(source) || !source.isDirectory {
        return folderResult([early(source, destination, .refused, "The source is not a folder, so the folder copy did not start.")], [])
    }
    if isSymlink(destination) || (destination.exists && !destination.isDirectory) {
        return folderResult([early(source, destination, .refused, "The destination is not a folder. The folder copy did not start.")], [])
    }
    if isNested(source: source, destination: destination) {
        return folderResult([
            early(source, destination, .refused, "The destination sits inside the source folder. The copy did not start."),
        ], [])
    }
    var files: [Receipt] = []
    var skipped: [SkippedEntry] = []
    walk(source, skipped: &skipped) { file in
        let src = source.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        let prefix = src.hasSuffix("/") ? src : src + "/"
        guard filePath.hasPrefix(prefix) else { return }
        let relative = String(filePath.dropFirst(prefix.count))
        let target = destination.appendingPathComponent(relative)
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        files.append(transferFile(
            source: file,
            destination: target,
            endpoint: endpointFactory(),
            replace: replace,
            chunkSize: chunkSize
        ))
    }
    return folderResult(files, skipped)
}

private func walk(_ directory: URL, skipped: inout [SkippedEntry], visit: (URL) -> Void) {
    let children = (try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey],
        options: []
    )) ?? []
    for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        if isSymlink(child) {
            let reason = symlinkPointsAtDirectory(child) ? "symlink folder, not followed" : "symlink"
            skipped.append(SkippedEntry(path: child.path, reason: reason))
            continue
        }
        if child.isDirectory {
            walk(child, skipped: &skipped, visit: visit)
        } else if child.isRegularFile {
            visit(child)
        } else {
            skipped.append(SkippedEntry(path: child.path, reason: "not a regular file"))
        }
    }
}

private func folderResult(_ files: [Receipt], _ skipped: [SkippedEntry]) -> FolderResult {
    if files.count == 1, files[0].code == .refused, skipped.isEmpty {
        return FolderResult(code: .refused, word: "Down", tone: .down, summary: files[0].summary, files: files, skipped: skipped)
    }
    if files.isEmpty && skipped.isEmpty {
        return FolderResult(
            code: .empty, word: "Place", tone: .place,
            summary: "The folder has no files to copy.", files: files, skipped: skipped
        )
    }
    let bad = files.filter { !$0.promoted || $0.code != .match }
    if !bad.isEmpty || !skipped.isEmpty {
        var bits: [String] = []
        if !bad.isEmpty {
            bits.append(bad.count == 1 ? "1 file did not fully match" : "\(bad.count) files did not fully match")
        }
        if !skipped.isEmpty {
            bits.append(skipped.count == 1 ? "1 entry skipped" : "\(skipped.count) entries skipped")
        }
        return FolderResult(
            code: .incomplete, word: "Down", tone: .down,
            summary: "Folder copy finished with gaps. \(bits.joined(separator: ", and ")).",
            files: files, skipped: skipped
        )
    }
    return FolderResult(
        code: .match, word: "Match", tone: .up,
        summary: "All \(files.count) files match on the data fork, with nothing skipped.",
        files: files, skipped: skipped
    )
}

private func refuseFile(source: URL, destination: URL, replace: Bool) -> (TransferCode, String)? {
    if isSymlink(source) || !source.isRegularFile {
        return (.refused, "The source is not a regular file. Symlinks, devices, and folders are not copied this way.")
    }
    if destination.exists && source.resolvingSymlinksInPath().standardizedFileURL.path == destination.resolvingSymlinksInPath().standardizedFileURL.path {
        return (.refused, "The source and the destination are the same file.")
    }
    if isSymlink(destination) {
        return (.refused, "The destination is a symlink. The file was not written through it.")
    }
    if destination.exists && destination.isDirectory {
        return (.refused, "The destination is a folder. The file was not written over it.")
    }
    if destination.exists && !replace {
        return (.exists, "A file is already at the destination. It was left in place.")
    }
    var parentIsDir: ObjCBool = false
    let parent = destination.deletingLastPathComponent()
    if !FileManager.default.fileExists(atPath: parent.path, isDirectory: &parentIsDir) || !parentIsDir.boolValue {
        return (.refused, "The destination folder does not exist yet.")
    }
    return nil
}

private func early(_ source: URL, _ destination: URL, _ code: TransferCode, _ summary: String) -> Receipt {
    done(
        source: source, destination: destination, promoted: false, code: code, word: "Down", tone: .down,
        summary: summary, before: nil, destRead: nil, after: nil, byteCount: 0, transferSeconds: 0,
        sync: "", meta: [], inodeChanged: false, partial: nil, osStamps: []
    )
}

private func done(
    source: URL,
    destination: URL,
    promoted: Bool,
    code: TransferCode,
    word: String,
    tone: StatusTone,
    summary: String,
    before: HashRead?,
    destRead: HashRead?,
    after: HashRead?,
    byteCount: Int,
    transferSeconds: Double,
    sync: String,
    meta: [String],
    inodeChanged: Bool,
    partial: URL?,
    osStamps: [String],
    sent: Digest? = nil
) -> Receipt {
    let rate: Double? = (transferSeconds > 0 && byteCount > 0) ? Double(byteCount) / transferSeconds : nil
    return Receipt(
        source: source.path,
        destination: destination.path,
        promoted: promoted,
        code: code,
        word: word,
        tone: tone,
        summary: summary,
        before: before?.digest,
        destinationHash: destRead?.digest,
        after: after?.digest,
        byteCount: byteCount,
        transferSeconds: transferSeconds,
        hashBeforeSeconds: before?.seconds ?? 0,
        hashDestinationSeconds: destRead?.seconds ?? 0,
        hashAfterSeconds: after?.seconds ?? 0,
        rateBytesPerSecond: rate,
        sampleShort: byteCount > 0 && transferSeconds < 0.001,
        sync: sync,
        metadataLeftBehind: meta,
        inodeChanged: inodeChanged,
        partial: partial?.path,
        osStamps: osStamps,
        sent: sent
    )
}

private func cacheNote(destination: Digest, after: Digest) -> String {
    var missed: [String] = []
    if destination.cache != "stepped-aside" { missed.append("received file") }
    if after.cache != "stepped-aside" { missed.append("source again") }
    if missed.isEmpty {
        return "The received file and the second source read asked the cache to step aside."
    }
    return "Cache aside was not confirmed for \(missed.joined(separator: " and ")). A warm cache can hide a disk that would have returned different bytes."
}

private enum HashOutcome {
    case hash(HashRead)
    case failed(TransferError)
    case missing

    var hashRead: HashRead? {
        if case .hash(let value) = self { return value }
        return nil
    }
}

private func hashOutcome(_ url: URL, dropCache: Bool) -> HashOutcome {
    guard url.isRegularFile else { return .missing }
    do {
        return .hash(try hashFile(at: url, dropCache: dropCache))
    } catch let error as TransferError {
        return .failed(error)
    } catch {
        return .failed(TransferError(.ioError, "A hash after the copy could not be read."))
    }
}

private func failedRead(
    _ source: URL,
    _ destination: URL,
    _ before: HashRead,
    _ error: TransferError,
    _ written: Int,
    _ transferSeconds: Double,
    _ sync: String,
    _ notes: FileNotes,
    _ inodeChanged: Bool,
    _ partial: URL,
    _ sent: Digest
) -> Receipt {
    done(
        source: source, destination: destination, promoted: false, code: error.code,
        word: "Down", tone: .down, summary: error.detail, before: before, destRead: nil, after: nil,
        byteCount: written, transferSeconds: transferSeconds, sync: sync, meta: notes.leftBehind,
        inodeChanged: inodeChanged, partial: partial.exists ? partial : nil, osStamps: notes.stamps, sent: sent
    )
}

private func readChunk(_ fd: Int32, _ size: Int) throws -> Data {
    var data = Data()
    data.reserveCapacity(size)
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
    defer { buffer.deallocate() }
    var remaining = size
    while remaining > 0 {
        let n = readEINTR(fd, buffer, remaining)
        if n == 0 { break }
        if n < 0 { throw TransferError(.ioError, errnoString("The copy read failed")) }
        data.append(buffer, count: n)
        remaining -= n
    }
    return data
}

private func writeAll(_ fd: Int32, _ data: Data) throws {
    try data.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return }
        var written = 0
        while written < raw.count {
            let n = Darwin.write(fd, base.advanced(by: written), raw.count - written)
            if n < 0 {
                if errno == EINTR { continue }
                throw TransferError(.ioError, errnoString("The copy write failed"))
            }
            written += n
        }
    }
}

private func partialURL(_ destination: URL) -> URL {
    destination.deletingLastPathComponent().appendingPathComponent(destination.lastPathComponent + ".ht-partial")
}

private struct FileIdentity: Equatable {
    var dev: UInt64
    var ino: UInt64
}

private func fileIdentity(_ url: URL) -> FileIdentity? {
    var info = stat()
    if stat(url.path, &info) != 0 { return nil }
    return FileIdentity(dev: UInt64(info.st_dev), ino: info.st_ino)
}

private func isNested(source: URL, destination: URL) -> Bool {
    let src = source.resolvingSymlinksInPath().standardizedFileURL.path
    let dst = destination.resolvingSymlinksInPath().standardizedFileURL.path
    if dst == src { return true }
    let prefix = src.hasSuffix("/") ? src : src + "/"
    return dst.hasPrefix(prefix)
}

func symlinkPointsAtDirectory(_ url: URL) -> Bool {
    let raw = (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) ?? ""
    if raw.isEmpty { return false }
    let target = raw.hasPrefix("/")
        ? URL(fileURLWithPath: raw)
        : url.deletingLastPathComponent().appendingPathComponent(raw)
    var dir: ObjCBool = false
    return FileManager.default.fileExists(atPath: target.path, isDirectory: &dir) && dir.boolValue
}

func isSymlink(_ url: URL) -> Bool {
    let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
    return values?.isSymbolicLink == true
}

private extension URL {
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
    var isDirectory: Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue && !isSymlink(self)
    }
    var isRegularFile: Bool {
        guard !isSymlink(self) else { return false }
        var info = stat()
        guard stat(path, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFREG
    }
}
