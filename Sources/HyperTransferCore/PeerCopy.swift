import CryptoKit
import Darwin
import Foundation

let fileHeaderLength = 1048
let peerListLength = 65536
let peerAnswerLength = 256
let peerDigestLength = 512
let peerCommitLength = 8
let peerRenameLength = 256

protocol FrameLink: AnyObject {
    func sendFrame(_ data: Data) throws
    func recvFrame(_ count: Int) throws -> Data
}

struct FileOffer: Equatable {
    var relative: String
    var byteCount: UInt64
    var chunkSize: UInt32
    var replace: Bool
}

func encodeFileOffer(_ offer: FileOffer) -> Data? {
    let path = Array(offer.relative.utf8)
    guard path.count <= 1024, offer.chunkSize > 0 else { return nil }
    var data = Data(count: fileHeaderLength)
    data.replaceSubrange(0..<4, with: Data("HTF1".utf8))
    writeInt(UInt16(1), into: &data, at: 4)
    writeInt(UInt16(path.count), into: &data, at: 6)
    writeInt(offer.byteCount, into: &data, at: 8)
    writeInt(offer.chunkSize, into: &data, at: 16)
    data[20] = offer.replace ? 1 : 0
    data.replaceSubrange(24..<(24 + path.count), with: path)
    return data
}

func decodeFileOffer(_ data: Data) -> FileOffer? {
    guard data.count == fileHeaderLength, data.prefix(4).elementsEqual(Data("HTF1".utf8)) else { return nil }
    let version: UInt16 = readInt(data, at: 4)
    let pathLen: UInt16 = readInt(data, at: 6)
    guard version == 1, pathLen <= 1024 else { return nil }
    let path = String(decoding: data.subdata(in: 24..<(24 + Int(pathLen))), as: UTF8.self)
    guard !path.isEmpty else { return nil }
    let chunk: UInt32 = readInt(data, at: 16)
    guard chunk > 0 else { return nil }
    return FileOffer(
        relative: path,
        byteCount: readInt(data, at: 8),
        chunkSize: chunk,
        replace: data[20] == 1
    )
}

func encodeAnswer(ok: Bool, detail: String) -> Data {
    var data = Data(count: peerAnswerLength)
    data.replaceSubrange(0..<4, with: Data("HTKA".utf8))
    data[4] = ok ? 1 : 0
    let bytes = Array(detail.utf8.prefix(240))
    writeInt(UInt16(bytes.count), into: &data, at: 6)
    if !bytes.isEmpty {
        data.replaceSubrange(8..<(8 + bytes.count), with: bytes)
    }
    return data
}

func decodeAnswer(_ data: Data) -> (Bool, String)? {
    guard data.count == peerAnswerLength, data.prefix(4).elementsEqual(Data("HTKA".utf8)) else { return nil }
    let count: UInt16 = readInt(data, at: 6)
    guard count <= 240 else { return nil }
    let detail = String(decoding: data.subdata(in: 8..<(8 + Int(count))), as: UTF8.self)
    return (data[4] == 1, detail)
}

func encodeDigest(ok: Bool, digest: Digest?, detail: String) -> Data {
    var data = Data(count: peerDigestLength)
    data.replaceSubrange(0..<4, with: Data("HTDG".utf8))
    data[4] = ok ? 1 : 0
    if let digest {
        writeInt(UInt64(digest.byteCount), into: &data, at: 8)
        let sha = Array(digest.sha512.utf8.prefix(128))
        let blake = Array(digest.blake2b.utf8.prefix(128))
        data.replaceSubrange(16..<(16 + sha.count), with: sha)
        data.replaceSubrange(144..<(144 + blake.count), with: blake)
    }
    let bytes = Array(detail.utf8.prefix(200))
    writeInt(UInt16(bytes.count), into: &data, at: 272)
    if !bytes.isEmpty {
        data.replaceSubrange(274..<(274 + bytes.count), with: bytes)
    }
    return data
}

func decodeDigest(_ data: Data) -> (Bool, Digest?, String)? {
    guard data.count == peerDigestLength, data.prefix(4).elementsEqual(Data("HTDG".utf8)) else { return nil }
    let count: UInt16 = readInt(data, at: 272)
    guard count <= 200 else { return nil }
    let detail = String(decoding: data.subdata(in: 274..<(274 + Int(count))), as: UTF8.self)
    guard data[4] == 1 else { return (false, nil, detail) }
    let byteCount: UInt64 = readInt(data, at: 8)
    let sha = String(decoding: data.subdata(in: 16..<144), as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    let blake = String(decoding: data.subdata(in: 144..<272), as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    guard sha.count == 128, blake.count == 128 else { return (false, nil, detail) }
    return (true, Digest(sha512: sha, blake2b: blake, byteCount: Int(byteCount), cache: "stepped-aside"), detail)
}

func encodeCommit(promote: Bool) -> Data {
    var data = Data(count: peerCommitLength)
    data.replaceSubrange(0..<4, with: Data("HTCM".utf8))
    data[4] = promote ? 1 : 0
    return data
}

func decodeCommit(_ data: Data) -> Bool? {
    guard data.count == peerCommitLength, data.prefix(4).elementsEqual(Data("HTCM".utf8)) else { return nil }
    return data[4] == 1
}

func encodeRename(ok: Bool, detail: String) -> Data {
    var data = Data(count: peerRenameLength)
    data.replaceSubrange(0..<4, with: Data("HTRN".utf8))
    data[4] = ok ? 1 : 0
    let bytes = Array(detail.utf8.prefix(240))
    writeInt(UInt16(bytes.count), into: &data, at: 6)
    if !bytes.isEmpty {
        data.replaceSubrange(8..<(8 + bytes.count), with: bytes)
    }
    return data
}

func decodeRename(_ data: Data) -> (Bool, String)? {
    guard data.count == peerRenameLength, data.prefix(4).elementsEqual(Data("HTRN".utf8)) else { return nil }
    let count: UInt16 = readInt(data, at: 6)
    guard count <= 240 else { return nil }
    let detail = String(decoding: data.subdata(in: 8..<(8 + Int(count))), as: UTF8.self)
    return (data[4] == 1, detail)
}

func sendFile(link: FrameLink, source: URL, relative: String, replace: Bool, chunkSize: Int = defaultChunkSize) -> Receipt {
    let destination = URL(fileURLWithPath: relative)
    let started = DispatchTime.now().uptimeNanoseconds
    do {
        let before = try hashFile(at: source, dropCache: false)
        guard let offer = encodeFileOffer(FileOffer(
            relative: relative,
            byteCount: UInt64(before.digest.byteCount),
            chunkSize: UInt32(chunkSize),
            replace: replace
        )) else {
            return peerDown(source, destination, "The peer path does not fit in the queue-pair header.")
        }
        try link.sendFrame(offer)
        let answerData = try link.recvFrame(peerAnswerLength)
        guard let answer = decodeAnswer(answerData) else {
            return peerDown(source, destination, "The peer did not accept the header.")
        }
        guard answer.0 else {
            return peerDown(source, destination, answer.1)
        }
        let fd = Darwin.open(source.path, O_RDONLY)
        if fd < 0 { return peerDown(source, destination, "The copy could not open the source.") }
        defer { Darwin.close(fd) }
        var sentSHA = SHA512()
        var sentBlake = Blake2b()
        var offset = 0
        var index: UInt32 = 0
        var written = 0
        while true {
            let payload = try readUpTo(fd, chunkSize)
            if payload.isEmpty && offset > 0 { break }
            if !payload.isEmpty {
                try link.sendFrame(payload)
            }
            let record = Completion.build(chunkIndex: index, offset: UInt64(offset), payload: payload)
            try link.sendFrame(record)
            sentSHA.update(data: payload)
            sentBlake.update(payload)
            written += payload.count
            offset += payload.count
            index += 1
            if payload.count < chunkSize { break }
        }
        let sent = Digest(
            sha512: sentSHA.finalize().hex,
            blake2b: sentBlake.finalize().hexString,
            byteCount: written,
            cache: "posted-bytes"
        )
        let digestData = try link.recvFrame(peerDigestLength)
        let parsed = decodeDigest(digestData)
        guard let parsed, parsed.0, let destDigest = parsed.1 else {
            return peerDown(source, destination, parsed?.2 ?? "The received file was not hashed.")
        }
        let after = try hashFile(at: source, dropCache: true)
        let notes = fileNotes(at: source)
        let verdict = judge(before: before.digest, destination: destDigest, after: after.digest)
        let promote = verdict.match && sent.sameBytes(as: before.digest)
        try link.sendFrame(encodeCommit(promote: promote))
        let renameData = try link.recvFrame(peerRenameLength)
        guard let rename = decodeRename(renameData) else {
            return peerDown(source, destination, "The peer did not say whether the finished name was written.")
        }
        let seconds = Double(DispatchTime.now().uptimeNanoseconds &- started) / 1_000_000_000
        if !promote {
            return Receipt(
                source: source.path, destination: relative, promoted: false, code: verdict.code,
                word: "Down", tone: .down, summary: verdict.summary, before: before.digest,
                destinationHash: destDigest, after: after.digest, byteCount: written,
                transferSeconds: seconds, hashBeforeSeconds: before.seconds, hashDestinationSeconds: 0,
                hashAfterSeconds: after.seconds, rateBytesPerSecond: seconds > 0 ? Double(written) / seconds : nil,
                sampleShort: written > 0 && seconds < 0.001, sync: "", metadataLeftBehind: notes.leftBehind,
                inodeChanged: false, partial: nil, osStamps: notes.stamps, sent: sent
            )
        }
        if !rename.0 {
            return Receipt(
                source: source.path, destination: relative, promoted: false, code: .renameFailed,
                word: "Down", tone: .down,
                summary: "SHA-512 and BLAKE2b match. The finished name was not written (\(rename.1)). The partial file is still beside it.",
                before: before.digest, destinationHash: destDigest, after: after.digest, byteCount: written,
                transferSeconds: seconds, hashBeforeSeconds: before.seconds, hashDestinationSeconds: 0,
                hashAfterSeconds: after.seconds, rateBytesPerSecond: seconds > 0 ? Double(written) / seconds : nil,
                sampleShort: written > 0 && seconds < 0.001, sync: "", metadataLeftBehind: notes.leftBehind,
                inodeChanged: false, partial: nil, osStamps: notes.stamps, sent: sent
            )
        }
        var summary = notes.leftBehind.isEmpty
            ? verdict.summary
            : "SHA-512 and BLAKE2b match on the data fork. Left behind: \(notes.leftBehind.joined(separator: ", "))."
        if !notes.stamps.isEmpty {
            summary += " Kept by this Mac, and not part of the hash: \(notes.stamps.joined(separator: ", "))."
        }
        return Receipt(
            source: source.path, destination: relative, promoted: true,
            code: notes.leftBehind.isEmpty ? .match : .dataForkMatches,
            word: notes.leftBehind.isEmpty ? "Match" : "Data fork",
            tone: notes.leftBehind.isEmpty ? .up : .place,
            summary: summary, before: before.digest, destinationHash: destDigest, after: after.digest,
            byteCount: written, transferSeconds: seconds, hashBeforeSeconds: before.seconds,
            hashDestinationSeconds: 0, hashAfterSeconds: after.seconds,
            rateBytesPerSecond: seconds > 0 ? Double(written) / seconds : nil,
            sampleShort: written > 0 && seconds < 0.001, sync: "", metadataLeftBehind: notes.leftBehind,
            inodeChanged: false, partial: nil, osStamps: notes.stamps, sent: sent
        )
    } catch let error as TransferError {
        return peerDown(source, destination, error.detail)
    } catch {
        return peerDown(source, destination, "The copy stopped while moving bytes.")
    }
}

func servePeerHeader(link: FrameLink, root: URL, header: Data) throws -> String {
    if header.prefix(4).elementsEqual(Data("HTLS".utf8)) {
        try answerPeerList(link: link, root: root, header: header)
        return "Listed a folder."
    }
    return try receiveFile(link: link, root: root, header: header)
}

func requestPeerList(link: FrameLink, relative: String) throws -> DirectoryListing {
    guard let request = encodeListRequest(relative) else {
        throw TransferError.refused("The peer path does not fit in the list request.")
    }
    try link.sendFrame(request)
    let raw = try link.recvFrame(peerListLength)
    guard let page = decodePeerList(raw) else {
        throw TransferError.refused("The peer list was not a directory page.")
    }
    guard page.ok else {
        throw TransferError.refused(page.detail.isEmpty ? "The peer folder did not list." : page.detail)
    }
    return DirectoryListing(path: page.path, parent: page.parent, entries: page.entries, truncated: page.truncated)
}

func answerPeerList(link: FrameLink, root: URL, header: Data) throws {
    let page: Data
    do {
        let relative = try decodeListRequest(header)
        let listing = try listDirectory(root: root, relative: relative)
        page = encodePeerList(
            ok: true, path: listing.path, parent: listing.parent, entries: listing.entries,
            detail: "", truncated: false
        )
    } catch let error as TransferError {
        page = encodePeerList(ok: false, path: ".", parent: nil, entries: [], detail: error.detail, truncated: false)
    } catch {
        page = encodePeerList(ok: false, path: ".", parent: nil, entries: [], detail: "The peer folder did not list.", truncated: false)
    }
    try link.sendFrame(page)
}

func encodeListRequest(_ relative: String) -> Data? {
    let path = relative.isEmpty ? "." : relative
    if path != ".", path.hasPrefix("/") || path.contains("\0") { return nil }
    if path != "." {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        if parts.contains(where: { $0 == ".." || $0.isEmpty }) { return nil }
    }
    let bytes = Array(path.utf8)
    guard bytes.count <= 1024 else { return nil }
    var data = Data(count: fileHeaderLength)
    data.replaceSubrange(0..<4, with: Data("HTLS".utf8))
    writeInt(UInt16(1), into: &data, at: 4)
    writeInt(UInt16(bytes.count), into: &data, at: 6)
    data.replaceSubrange(8..<(8 + bytes.count), with: bytes)
    return data
}

func decodeListRequest(_ data: Data) throws -> String {
    guard data.count == fileHeaderLength, data.prefix(4).elementsEqual(Data("HTLS".utf8)) else {
        throw TransferError.refused("The list request was not accepted.")
    }
    let version: UInt16 = readInt(data, at: 4)
    let pathLen: UInt16 = readInt(data, at: 6)
    guard version == 1, Int(pathLen) <= 1024, 8 + Int(pathLen) <= data.count else {
        throw TransferError.refused("The list request was not accepted.")
    }
    let bytes = data.subdata(in: 8..<(8 + Int(pathLen)))
    guard !bytes.contains(0) else {
        throw TransferError.refused("The list request was not accepted.")
    }
    let path = pathLen == 0 ? "." : String(decoding: bytes, as: UTF8.self)
    if path != "." {
        if path.hasPrefix("/") {
            throw TransferError.refused("That path leaves the peer root.")
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        if parts.contains(where: { $0 == ".." || $0.isEmpty }) {
            throw TransferError.refused("That path leaves the peer root.")
        }
    }
    return path
}

struct PeerListPage: Equatable {
    var ok: Bool
    var path: String
    var parent: String?
    var truncated: Bool
    var detail: String
    var entries: [DirectoryEntry]
}

func encodePeerList(ok: Bool, path: String, parent: String?, entries: [DirectoryEntry], detail: String, truncated: Bool) -> Data {
    var kept = entries
    var stopped = truncated
    var note = String(detail.prefix(400))
    var body = pageJSON(ok: ok, path: path, parent: parent, truncated: stopped, detail: note, entries: kept)
    while body.count > peerListLength - 8, !kept.isEmpty {
        kept.removeLast()
        stopped = true
        if note.isEmpty { note = "The list stopped early." }
        body = pageJSON(ok: ok, path: path, parent: parent, truncated: true, detail: note, entries: kept)
    }
    if body.count > peerListLength - 8 {
        body = pageJSON(ok: false, path: path, parent: parent, truncated: true, detail: "The peer list did not fit.", entries: [])
    }
    var data = Data(count: peerListLength)
    data.replaceSubrange(0..<4, with: Data("HTLR".utf8))
    writeInt(UInt32(body.count), into: &data, at: 4)
    data.replaceSubrange(8..<(8 + body.count), with: body)
    return data
}

func decodePeerList(_ data: Data) -> PeerListPage? {
    guard data.count == peerListLength, data.prefix(4).elementsEqual(Data("HTLR".utf8)) else { return nil }
    let length: UInt32 = readInt(data, at: 4)
    guard length > 0, Int(length) <= peerListLength - 8 else { return nil }
    let body = data.subdata(in: 8..<(8 + Int(length)))
    guard let json = try? JSONDecoder().decode(PageBody.self, from: body) else { return nil }
    let entries = json.entries.map {
        DirectoryEntry(
            name: $0.name, kind: $0.kind, size: $0.size, modified: $0.modified,
            hidden: $0.hidden, relative: $0.relative, leavesRoot: $0.leavesRoot
        )
    }
    return PeerListPage(
        ok: json.ok, path: json.path, parent: json.parent, truncated: json.truncated,
        detail: json.detail, entries: entries
    )
}

private struct PageBody: Codable {
    var ok: Bool
    var path: String
    var parent: String?
    var truncated: Bool
    var detail: String
    var entries: [PageEntry]
}

private struct PageEntry: Codable {
    var name: String
    var kind: String
    var size: Int?
    var modified: String?
    var hidden: Bool
    var relative: String
    var leavesRoot: Bool
}

private func pageJSON(ok: Bool, path: String, parent: String?, truncated: Bool, detail: String, entries: [DirectoryEntry]) -> Data {
    let body = PageBody(
        ok: ok, path: path, parent: parent, truncated: truncated, detail: detail,
        entries: entries.map {
            PageEntry(
                name: $0.name, kind: $0.kind, size: $0.size, modified: $0.modified,
                hidden: $0.hidden, relative: $0.relative, leavesRoot: $0.leavesRoot
            )
        }
    )
    return (try? JSONEncoder().encode(body)) ?? Data()
}

func receiveFile(link: FrameLink, root: URL, header: Data) throws -> String {
    guard let offer = decodeFileOffer(header) else {
        try link.sendFrame(encodeAnswer(ok: false, detail: "The file header was not accepted."))
        throw TransferError.refused("The file header was not accepted.")
    }
    let destination: URL
    do {
        destination = try resolvePlace(root: root, relative: offer.relative)
    } catch let error as TransferError {
        try link.sendFrame(encodeAnswer(ok: false, detail: error.detail))
        throw error
    }
    if destination.exists && !offer.replace {
        let detail = "A file is already at the destination. It was left in place."
        try link.sendFrame(encodeAnswer(ok: false, detail: detail))
        throw TransferError(.exists, detail)
    }
    if isSymlink(destination) || (destination.exists && destination.isDirectory) {
        let detail = "The destination is not a regular file. It was left in place."
        try link.sendFrame(encodeAnswer(ok: false, detail: detail))
        throw TransferError.refused(detail)
    }
    try link.sendFrame(encodeAnswer(ok: true, detail: ""))
    let partial = destination.deletingLastPathComponent().appendingPathComponent(destination.lastPathComponent + ".ht-partial")
    let fd = Darwin.open(partial.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    if fd < 0 {
        let detail = "The copy could not open the partial file."
        try link.sendFrame(encodeDigest(ok: false, digest: nil, detail: detail))
        throw TransferError(.ioError, detail)
    }
    defer { Darwin.close(fd) }
    var reported = false
    var remaining = Int(offer.byteCount)
    var index: UInt32 = 0
    do {
        while true {
            let expect = min(Int(offer.chunkSize), remaining)
            let payload = expect > 0 ? try link.recvFrame(expect) : Data()
            let record = try link.recvFrame(Completion.length)
            let visible = try takeChunk(cookie: record, payload: payload, chunkIndex: index)
            if !visible.isEmpty { try writeAll(fd, visible) }
            remaining -= visible.count
            index += 1
            if remaining == 0 || visible.count < Int(offer.chunkSize) { break }
        }
        let sync = syncFile(fd)
        let hashed = try hashFile(at: partial, dropCache: true)
        try link.sendFrame(encodeDigest(ok: true, digest: hashed.digest, detail: sync))
        reported = true
        let commitData = try link.recvFrame(peerCommitLength)
        guard let promote = decodeCommit(commitData) else {
            throw TransferError.notNotified("The commit was not a completion of the three reads.")
        }
        if !promote {
            try link.sendFrame(encodeRename(ok: false, detail: "The three reads did not agree. The partial file is still beside the finished name."))
            return "The three reads did not agree. \(offer.relative) was not renamed."
        }
        if let renameError = promotePartial(partial: partial, destination: destination) {
            try link.sendFrame(encodeRename(ok: false, detail: renameError))
            return "The finished name was not written (\(renameError))."
        }
        try link.sendFrame(encodeRename(ok: true, detail: ""))
        return "Received \(offer.relative)."
    } catch let error as TransferError {
        if !reported {
            try? link.sendFrame(encodeDigest(ok: false, digest: nil, detail: error.detail))
        }
        throw error
    }
}

private func peerDown(_ source: URL, _ destination: URL, _ summary: String) -> Receipt {
    Receipt(
        source: source.path, destination: destination.path, promoted: false, code: .downCode(summary),
        word: "Down", tone: .down, summary: summary, before: nil, destinationHash: nil, after: nil,
        byteCount: 0, transferSeconds: 0, hashBeforeSeconds: 0, hashDestinationSeconds: 0,
        hashAfterSeconds: 0, rateBytesPerSecond: nil, sampleShort: false, sync: "",
        metadataLeftBehind: [], inodeChanged: false, partial: nil, osStamps: [], sent: nil
    )
}

private extension TransferCode {
    static func downCode(_ summary: String) -> TransferCode {
        if summary.contains("already at the destination") { return .exists }
        if summary.contains("not notified") || summary.contains("completion") { return .notNotified }
        return .ioError
    }
}

private func readUpTo(_ fd: Int32, _ count: Int) throws -> Data {
    var data = Data()
    while data.count < count {
        let piece = try readSome(fd, count - data.count)
        if piece.isEmpty { break }
        data.append(piece)
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
                throw TransferError(.ioError, "The copy write failed.")
            }
            written += n
        }
    }
}

private func writeInt<T: FixedWidthInteger>(_ value: T, into data: inout Data, at offset: Int) {
    var little = value.littleEndian
    withUnsafeBytes(of: &little) { raw in
        data.replaceSubrange(offset..<(offset + raw.count), with: raw)
    }
}

private func readInt<T: FixedWidthInteger>(_ data: Data, at offset: Int) -> T {
    let width = MemoryLayout<T>.size
    return data.subdata(in: offset..<(offset + width)).withUnsafeBytes { raw in
        T(littleEndian: raw.load(as: T.self))
    }
}

private extension URL {
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
    var isDirectory: Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue && !isSymlink(self)
    }
}
