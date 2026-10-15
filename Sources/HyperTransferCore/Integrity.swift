import CryptoKit
import Darwin
import Foundation

public struct Digest: Equatable, Sendable {
    public var sha512: String
    public var blake2b: String
    public var byteCount: Int
    public var cache: String

    public init(sha512: String, blake2b: String, byteCount: Int, cache: String) {
        self.sha512 = sha512
        self.blake2b = blake2b
        self.byteCount = byteCount
        self.cache = cache
    }

    public func sameBytes(as other: Digest) -> Bool {
        sha512 == other.sha512 && blake2b == other.blake2b && byteCount == other.byteCount
    }

    public static func of(_ payload: Data, cache: String) -> Digest {
        Digest(
            sha512: SHA512.hash(data: payload).hex,
            blake2b: Blake2b.hash(payload).hexString,
            byteCount: payload.count,
            cache: cache
        )
    }
}

public struct HashRead: Equatable, Sendable {
    public var digest: Digest
    public var seconds: Double
}

public struct Verdict: Equatable, Sendable {
    public var code: TransferCode
    public var match: Bool
    public var summary: String
}

public struct FileNotes: Equatable, Sendable {
    public var leftBehind: [String]
    public var stamps: [String]
}

/// This Mac stamps `com.apple.provenance` onto a new file and puts it back if removed.
public let osStamps: Set<String> = ["com.apple.provenance"]

public let emptySHA512 = "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"
public let emptyBlake2b = "786a02f742015903c6c6fd852552d272912f4740e15847618a86e217f71f5419d25e1031afee585313896444934eb04b903a685b1448b755d56f701afe9be2ce"

public let wideReadSize = 1024 * 1024
public let narrowReadSize = 64 * 1024 + 13

public func hashFile(at url: URL, dropCache: Bool) throws -> HashRead {
    let started = DispatchTime.now().uptimeNanoseconds
    let wide = Darwin.open(url.path, O_RDONLY)
    if wide < 0 {
        throw TransferError(.ioError, errnoString("The hash could not open the file"))
    }
    defer { Darwin.close(wide) }
    let narrow = Darwin.open(url.path, O_RDONLY)
    if narrow < 0 {
        throw TransferError(.ioError, errnoString("The second read could not open the file"))
    }
    defer { Darwin.close(narrow) }

    let narrowCache = askCacheAside(narrow)
    var wideCache = "left-alone"
    if dropCache {
        wideCache = askCacheAside(wide)
        if wideCache != "stepped-aside" || narrowCache != "stepped-aside" {
            throw TransferError(
                .ioError,
                "The second measurement could not ask the cache to step aside (\(wideCache); \(narrowCache))."
            )
        }
    }
    let cache = dropCache ? "stepped-aside" : (narrowCache == "stepped-aside" ? "cache-and-media" : narrowCache)

    let folded = try stableDigest(
        readA: { try readSome(wide, $0) },
        readB: { try readSome(narrow, $0) }
    )
    let seconds = Double(DispatchTime.now().uptimeNanoseconds &- started) / 1_000_000_000
    return HashRead(
        digest: Digest(sha512: folded.sha512, blake2b: folded.blake2b, byteCount: folded.byteCount, cache: cache),
        seconds: seconds
    )
}

public func stableDigest(
    readA: (Int) throws -> Data,
    readB: (Int) throws -> Data
) throws -> (sha512: String, blake2b: String, byteCount: Int) {
    var holdA = Data()
    var holdB = Data()
    var sha = SHA512()
    var blake = Blake2b()
    var count = 0
    var eofA = false
    var eofB = false
    while true {
        if !eofA && holdA.count < narrowReadSize {
            let chunk = try readA(wideReadSize)
            if chunk.isEmpty { eofA = true } else { holdA.append(chunk) }
        }
        if !eofB && holdB.count < narrowReadSize {
            let chunk = try readB(narrowReadSize)
            if chunk.isEmpty { eofB = true } else { holdB.append(chunk) }
        }
        let available = min(holdA.count, holdB.count)
        if available == 0 {
            if eofA && eofB && holdA.isEmpty && holdB.isEmpty { break }
            throw TransferError(
                .mediaDisagreed,
                "The two reads of this file did not end on the same byte. The digest was not trusted."
            )
        }
        if !holdA.prefix(available).elementsEqual(holdB.prefix(available)) {
            throw TransferError(
                .mediaDisagreed,
                "Two reads of this file returned different bytes. The digest was not trusted."
            )
        }
        let agreed = holdA.prefix(available)
        sha.update(data: agreed)
        blake.update(Data(agreed))
        count += available
        holdA.removeFirst(available)
        holdB.removeFirst(available)
    }
    return (sha.finalize().hex, blake.finalize().hexString, count)
}

public func judge(before: Digest, destination: Digest, after: Digest) -> Verdict {
    guard before.sha512.count == 128, before.blake2b.count == 128,
          destination.sha512.count == 128, destination.blake2b.count == 128,
          after.sha512.count == 128, after.blake2b.count == 128 else {
        return Verdict(code: .algorithm, match: false, summary: "The three reads did not all carry SHA-512 and BLAKE2b.")
    }
    if Set([before.byteCount, destination.byteCount, after.byteCount]).count != 1 {
        return Verdict(
            code: .length,
            match: false,
            summary: "Lengths differ. Before \(before.byteCount) bytes, received file \(destination.byteCount) bytes, source again \(after.byteCount) bytes."
        )
    }
    let sourceSame = before.sameBytes(as: after)
    let destinationMatchesBefore = destination.sameBytes(as: before)
    let destinationMatchesAfter = destination.sameBytes(as: after)
    if sourceSame && destinationMatchesBefore {
        return Verdict(code: .match, match: true, summary: "SHA-512 and BLAKE2b match on all three reads.")
    }
    if !sourceSame && destinationMatchesBefore {
        return Verdict(
            code: .sourceChanged,
            match: false,
            summary: "The source changed after the first hash. The received file matches the earlier bytes. The source file does not."
        )
    }
    if !sourceSame && destinationMatchesAfter {
        return Verdict(
            code: .sourceChanged,
            match: false,
            summary: "The source changed during the copy. The received file matches the source as it is now, not the hash taken before the transfer."
        )
    }
    if !sourceSame {
        return Verdict(
            code: .sourceChanged,
            match: false,
            summary: "The source changed, and the received file matches neither reading."
        )
    }
    return Verdict(
        code: .destinationDiffers,
        match: false,
        summary: "The source stayed the same. The received file does not match it."
    )
}

public func fileNotes(at url: URL) -> FileNotes {
    let names = (try? listXattrs(url)) ?? []
    var left = names.filter { !osStamps.contains($0) }.map { "xattr:\($0)" }
    let stamps = names.filter { osStamps.contains($0) }.map { "xattr:\($0)" }
    let fork = resourceForkSize(url)
    if fork > 0 {
        left.append("resource-fork:\(fork)")
    }
    return FileNotes(leftBehind: left, stamps: stamps)
}

public func writeXattr(at url: URL, name: String, value: Data) throws {
    let rc = value.withUnsafeBytes { raw -> Int32 in
        guard let base = raw.baseAddress else {
            return setxattr(url.path, name, nil, 0, 0, 0)
        }
        return setxattr(url.path, name, base, raw.count, 0, 0)
    }
    if rc != 0 {
        throw TransferError(.ioError, errnoString("The attribute was not written"))
    }
}

public func syncFile(_ fd: Int32) -> String {
    if Darwin.fsync(fd) != 0 {
        return "fsync: \(String(cString: strerror(errno)))"
    }
    if fcntl(fd, F_FULLFSYNC) == -1 {
        return "fsync: \(String(cString: strerror(errno)))"
    }
    return "full"
}

public func promotePartial(partial: URL, destination: URL) -> String? {
    if Darwin.rename(partial.path, destination.path) == 0 {
        return nil
    }
    return String(cString: strerror(errno))
}

func askCacheAside(_ fd: Int32) -> String {
    if fcntl(fd, F_NOCACHE, 1) == -1 {
        return "could-not: \(String(cString: strerror(errno)))"
    }
    return "stepped-aside"
}

func listXattrs(_ url: URL) throws -> [String] {
    let size = listxattr(url.path, nil, 0, 0)
    if size < 0 {
        throw TransferError(.ioError, errnoString("Attributes could not be listed"))
    }
    if size == 0 { return [] }
    var buffer = [CChar](repeating: 0, count: size)
    let got = buffer.withUnsafeMutableBufferPointer { pointer -> ssize_t in
        listxattr(url.path, pointer.baseAddress, size, 0)
    }
    if got < 0 {
        throw TransferError(.ioError, errnoString("Attributes could not be listed"))
    }
    let bytes = buffer.prefix(got).map { UInt8(bitPattern: $0) }
    return bytes.split(separator: 0).compactMap { slice in
        String(bytes: slice, encoding: .utf8)
    }.sorted()
}

func resourceForkSize(_ url: URL) -> Int {
    let fork = url.path + "/..namedfork/rsrc"
    var info = stat()
    if stat(fork, &info) != 0 { return 0 }
    return Int(info.st_size)
}

func readEINTR(_ fd: Int32, _ buffer: UnsafeMutablePointer<UInt8>, _ capacity: Int) -> Int {
    while true {
        let n = Darwin.read(fd, buffer, capacity)
        if n < 0 && errno == EINTR { continue }
        return n
    }
}

func errnoString(_ prefix: String) -> String {
    "\(prefix) (\(String(cString: strerror(errno))))."
}

func readSome(_ fd: Int32, _ max: Int) throws -> Data {
    if max <= 0 { return Data() }
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: max)
    defer { buffer.deallocate() }
    let count = readEINTR(fd, buffer, max)
    if count < 0 {
        throw TransferError(.ioError, errnoString("The hash read failed"))
    }
    if count == 0 { return Data() }
    return Data(bytes: buffer, count: count)
}

extension SHA512.Digest {
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
