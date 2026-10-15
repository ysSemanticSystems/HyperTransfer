import CryptoKit
import Darwin
import Foundation
@testable import HyperTransferCore

final class TransferTests {
    func testRecordIs64BytesAndSeparateFromPayload() {
        let payload = Data("PAYLOAD-BYTES-NOT-IN-COOKIE".utf8)
        let record = Completion.build(chunkIndex: 3, offset: 4096, payload: payload)
        XCTAssertEqual(record.count, Completion.length)
        XCTAssertEqual(Completion.length, 160)
        XCTAssertFalse(record.range(of: payload) != nil)
        XCTAssertEqual(record.prefix(4), Completion.magic)
        XCTAssertEqual(record[4], 2)
        XCTAssertEqual(record[5], 0)
        let parsed = try? Completion.parse(record)
        XCTAssertEqual(parsed?.chunkIndex, 3)
        XCTAssertEqual(parsed?.offset, 4096)
        XCTAssertEqual(parsed?.byteCount, UInt64(payload.count))
        XCTAssertEqual(parsed?.sha512, Data(SHA512.hash(data: payload)))
        XCTAssertEqual(parsed?.blake2b, Blake2b.hash(payload))
    }

    func testShortRecordIsNotANotification() {
        XCTAssertThrowsError(try Completion.parse(Data(repeating: 0, count: 63))) { error in
            XCTAssertEqual((error as? TransferError)?.code, .notNotified)
        }
    }

    func testWrongVersionIsNotANotification() {
        var record = Completion.build(chunkIndex: 0, offset: 0, payload: Data())
        record[4] = 9
        XCTAssertThrowsError(try Completion.parse(record)) { error in
            XCTAssertEqual((error as? TransferError)?.code, .notNotified)
        }
    }

    func testTakeBeforeLandIsNotNotified() {
        let endpoint = ScriptedEndpoint()
        XCTAssertThrowsError(try takeChunk(cookie: endpoint.cpuCookie(), payload: endpoint.cpuPayload(offset: 0, count: 4), chunkIndex: 0)) { error in
            XCTAssertEqual((error as? TransferError)?.code, .notNotified)
        }
    }

    func testCookieHiddenDoesNotNotify() throws {
        try withTemp { root in
            let source = try plainFile(root, "source.bin", Data("visible-bytes".utf8))
            let dest = root.appendingPathComponent("dest.bin")
            let receipt = transferFile(source: source, destination: dest, endpoint: ScriptedEndpoint(visibility: .cookieHidden))
            XCTAssertEqual(receipt.code, .notNotified)
            XCTAssertFalse(receipt.promoted)
            XCTAssertEqual(receipt.word, "Down")
            XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path + ".ht-partial"))
        }
    }

    func testEmptyFileStillNeedsACompletionRecord() throws {
        try withTemp { root in
            let source = try plainFile(root, "empty.bin", Data())
            let dest = root.appendingPathComponent("out.bin")
            let receipt = transferFile(source: source, destination: dest, endpoint: ScriptedEndpoint(visibility: .cookieHidden))
            XCTAssertEqual(receipt.code, .notNotified)
            XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
        }
    }

    func testDataHiddenIsWriteIncomplete() throws {
        try withTemp { root in
            let source = try plainFile(root, "source.bin", Data("abcdefghij".utf8))
            let dest = root.appendingPathComponent("dest.bin")
            let receipt = transferFile(source: source, destination: dest, endpoint: ScriptedEndpoint(visibility: .dataHidden), chunkSize: 4)
            XCTAssertEqual(receipt.code, .writeIncomplete)
            XCTAssertFalse(receipt.promoted)
            XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
        }
    }

    func testCorruptFlushDoesNotPublish() throws {
        try withTemp { root in
            let source = try plainFile(root, "source.bin", Data("abcdefghij".utf8))
            let dest = root.appendingPathComponent("dest.bin")
            let endpoint = ScriptedEndpoint(corruptFlush: true)
            let receipt = transferFile(source: source, destination: dest, endpoint: endpoint)
            XCTAssertEqual(receipt.code, .flush)
            XCTAssertFalse(receipt.promoted)
            XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
            XCTAssertNotEqual(endpoint.cpuCookie().prefix(4), Completion.magic)
        }
    }

    func testFlushBoundariesOfOneSevenEightAndNine() throws {
        for count in [1, 7, 8, 9] {
            try withTemp { root in
                let payload = Data(repeating: 0xAB, count: count)
                let source = try plainFile(root, "b.bin", payload)
                let dest = root.appendingPathComponent("out.bin")
                let receipt = transferFile(source: source, destination: dest, endpoint: ScriptedEndpoint())
                XCTAssertEqual(receipt.code, .match, "count \(count) \(receipt.summary)")
                XCTAssertEqual(try Data(contentsOf: dest), payload)
            }
        }
    }

    func testEmptyFileMatches() throws {
        try withTemp { root in
            let source = try plainFile(root, "empty.bin", Data())
            let dest = root.appendingPathComponent("out.bin")
            let receipt = transferFile(source: source, destination: dest, endpoint: ScriptedEndpoint())
            XCTAssertEqual(receipt.code, .match)
            XCTAssertEqual(receipt.word, "Match")
            XCTAssertEqual(receipt.tone, .up)
            XCTAssertTrue(receipt.promoted)
            XCTAssertEqual(try Data(contentsOf: dest), Data())
            XCTAssertEqual(receipt.before?.sha512, emptySHA512)
            XCTAssertEqual(receipt.before?.blake2b, emptyBlake2b)
            XCTAssertEqual(receipt.destinationHash?.sha512, emptySHA512)
            XCTAssertEqual(receipt.destinationHash?.blake2b, emptyBlake2b)
            XCTAssertEqual(receipt.after?.sha512, receipt.before?.sha512)
            XCTAssertEqual(receipt.after?.blake2b, receipt.before?.blake2b)
            XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path + ".ht-partial"))
        }
    }

    func testMultichunkMatches() throws {
        try withTemp { root in
            let payload = Data("abcdefghij".utf8)
            let source = try plainFile(root, "source.bin", payload)
            let dest = root.appendingPathComponent("out.bin")
            let receipt = transferFile(source: source, destination: dest, endpoint: ScriptedEndpoint(), chunkSize: 4)
            XCTAssertEqual(receipt.code, .match)
            XCTAssertEqual(try Data(contentsOf: dest), payload)
            XCTAssertEqual(receipt.byteCount, payload.count)
            XCTAssertEqual(receipt.before?.sha512, receipt.destinationHash?.sha512)
            XCTAssertEqual(receipt.after?.blake2b, receipt.before?.blake2b)
        }
    }

    func testExactChunkBoundaryDoesNotPostAPhantomEmptyChunk() throws {
        try withTemp { root in
            let payload = Data(repeating: 0x11, count: 8)
            let source = try plainFile(root, "exact.bin", payload)
            let dest = root.appendingPathComponent("out.bin")
            let endpoint = ScriptedEndpoint()
            let receipt = transferFile(source: source, destination: dest, endpoint: endpoint, chunkSize: 8)
            XCTAssertEqual(receipt.code, .match)
            XCTAssertEqual(try Data(contentsOf: dest), payload)
            let record = try Completion.parse(endpoint.lastRecord)
            XCTAssertEqual(record.byteCount, 8)
            XCTAssertEqual(record.chunkIndex, 0)
        }
    }

    func testSparseFileMatchesLogicalBytes() throws {
        try withTemp { root in
            let source = root.appendingPathComponent("hole.bin")
            let fd = Darwin.open(source.path, O_CREAT | O_WRONLY, 0o644)
            XCTAssertGreaterThanOrEqual(fd, 0)
            _ = Darwin.lseek(fd, 1024 * 1024, SEEK_SET)
            _ = Darwin.write(fd, "tail", 4)
            Darwin.close(fd)
            let logical = try Data(contentsOf: source)
            let dest = root.appendingPathComponent("out.bin")
            let receipt = transferFile(source: source, destination: dest, endpoint: ScriptedEndpoint(), chunkSize: 256 * 1024)
            XCTAssertEqual(receipt.code, .match, receipt.summary)
            XCTAssertEqual(try Data(contentsOf: dest), logical)
            XCTAssertEqual(try Data(contentsOf: dest).count, logical.count)
        }
    }

    func testSourceChangesDuringCopy() throws {
        try withTemp { root in
            let source = try plainFile(root, "source.bin", Data("alpha-alpha".utf8))
            let dest = root.appendingPathComponent("out.bin")
            let receipt = transferFile(source: source, destination: dest, endpoint: ScriptedEndpoint(), afterFirstHash: { path in
                try? Data("bravo-bravo".utf8).write(to: path)
            })
            XCTAssertEqual(receipt.code, .sourceChanged)
            XCTAssertFalse(receipt.promoted)
            XCTAssertEqual(receipt.word, "Down")
            XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
            XCTAssertTrue(receipt.summary.contains("source as it is now"))
        }
    }

    func testLengthChangeIsNamed() throws {
        try withTemp { root in
            let source = try plainFile(root, "source.bin", Data("alpha".utf8))
            let dest = root.appendingPathComponent("out.bin")
            let receipt = transferFile(source: source, destination: dest, endpoint: ScriptedEndpoint(), afterFirstHash: { path in
                try? Data("bravo-bravo".utf8).write(to: path)
            })
            XCTAssertEqual(receipt.code, .length)
            XCTAssertFalse(receipt.promoted)
            XCTAssertTrue(receipt.summary.contains("Lengths differ"))
        }
    }

    func testReplaceWaitsForAMatch() throws {
        try withTemp { root in
            let source = try plainFile(root, "source.bin", Data("alpha-alpha".utf8))
            let dest = try plainFile(root, "out.bin", Data("old-dest-contents".utf8))
            let receipt = transferFile(source: source, destination: dest, endpoint: ScriptedEndpoint(), replace: true, afterFirstHash: { path in
                try? Data("bravo-bravo".utf8).write(to: path)
            })
            XCTAssertFalse(receipt.promoted)
            XCTAssertEqual(try Data(contentsOf: dest), Data("old-dest-contents".utf8))
        }
    }

    func testDestinationMismatchUnit() {
        let before = Digest.of(Data("same".utf8), cache: "left-alone")
        let other = Digest.of(Data("xxxx".utf8), cache: "left-alone")
        let verdict = judge(before: before, destination: other, after: before)
        XCTAssertEqual(verdict.code, .destinationDiffers)
        XCTAssertTrue(verdict.summary.lowercased().contains("source stayed the same"))
    }

    func testLengthMismatchUnit() {
        let before = Digest.of(Data("abcd".utf8), cache: "left-alone")
        let short = Digest(sha512: before.sha512, blake2b: before.blake2b, byteCount: 2, cache: "left-alone")
        let verdict = judge(before: before, destination: short, after: before)
        XCTAssertEqual(verdict.code, .length)
        XCTAssertTrue(verdict.summary.contains("2 bytes"))
    }

    func testSecondHashAsksCacheAside() throws {
        try withTemp { root in
            let path = try plainFile(root, "file.bin", Data("abc".utf8))
            let first = try hashFile(at: path, dropCache: false)
            let second = try hashFile(at: path, dropCache: true)
            XCTAssertEqual(first.digest.cache, "cache-and-media")
            XCTAssertEqual(first.digest.sha512, second.digest.sha512)
            XCTAssertEqual(first.digest.blake2b, second.digest.blake2b)
            XCTAssertEqual(second.digest.cache, "stepped-aside")
        }
    }

    func testXattrPromotesDataForkAndDoesNotSayMatch() throws {
        try withTemp { root in
            let source = try plainFile(root, "source.bin", Data("payload".utf8))
            try writeXattr(at: source, name: "com.hypertransfer.test", value: Data("yes".utf8))
            let dest = root.appendingPathComponent("out.bin")
            let receipt = transferFile(source: source, destination: dest, endpoint: ScriptedEndpoint())
            XCTAssertTrue(receipt.promoted)
            XCTAssertEqual(receipt.code, .dataForkMatches)
            XCTAssertEqual(receipt.word, "Data fork")
            XCTAssertNotEqual(receipt.word, "Match")
            XCTAssertEqual(receipt.tone, .place)
            XCTAssertTrue(receipt.summary.contains("com.hypertransfer.test"))
            XCTAssertEqual(try Data(contentsOf: dest), Data("payload".utf8))
            XCTAssertTrue(receipt.metadataLeftBehind.contains("xattr:com.hypertransfer.test"))
            XCTAssertFalse(receipt.osStamps.joined(separator: " ").contains("com.hypertransfer.test"))
        }
    }

    func testProvenanceStampIsNamedAndIsNotTheWord() throws {
        try withTemp { root in
            let source = try plainFile(root, "source.bin", Data("payload".utf8))
            let dest = root.appendingPathComponent("out.bin")
            let receipt = transferFile(source: source, destination: dest, endpoint: ScriptedEndpoint())
            if receipt.osStamps.contains("xattr:com.apple.provenance") {
                XCTAssertEqual(receipt.word, "Match")
                XCTAssertTrue(receipt.summary.contains("com.apple.provenance"))
            }
        }
    }

    func testRefusesSymlink() throws {
        try withTemp { root in
            let real = try plainFile(root, "real.bin", Data("data".utf8))
            let link = root.appendingPathComponent("link.bin")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
            let dest = root.appendingPathComponent("out.bin")
            let receipt = transferFile(source: link, destination: dest, endpoint: ScriptedEndpoint())
            XCTAssertEqual(receipt.code, .refused)
            XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path + ".ht-partial"))
        }
    }

    func testRefusesFifo() throws {
        try withTemp { root in
            let fifo = root.appendingPathComponent("pipe")
            XCTAssertEqual(Darwin.mkfifo(fifo.path, 0o644), 0)
            let receipt = transferFile(source: fifo, destination: root.appendingPathComponent("out.bin"), endpoint: ScriptedEndpoint())
            XCTAssertEqual(receipt.code, .refused)
        }
    }

    func testRefusesExistingWithoutReplace() throws {
        try withTemp { root in
            let source = try plainFile(root, "source.bin", Data("new".utf8))
            let dest = try plainFile(root, "out.bin", Data("keep".utf8))
            let receipt = transferFile(source: source, destination: dest, endpoint: ScriptedEndpoint(), replace: false)
            XCTAssertEqual(receipt.code, .exists)
            XCTAssertEqual(try Data(contentsOf: dest), Data("keep".utf8))
            XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path + ".ht-partial"))
        }
    }

    func testReplaceOnlyAfterMatch() throws {
        try withTemp { root in
            let source = try plainFile(root, "source.bin", Data("new".utf8))
            let dest = try plainFile(root, "out.bin", Data("old".utf8))
            let receipt = transferFile(source: source, destination: dest, endpoint: ScriptedEndpoint(), replace: true)
            XCTAssertEqual(receipt.code, .match)
            XCTAssertEqual(try Data(contentsOf: dest), Data("new".utf8))
        }
    }

    func testRenameFailureIsNotAMatch() throws {
        try withTemp { root in
            let source = try plainFile(root, "source.bin", Data("new".utf8))
            let dest = root.appendingPathComponent("out.bin")
            let receipt = transferFile(source: source, destination: dest, endpoint: ScriptedEndpoint(), promote: { _, _ in "Permission denied" })
            XCTAssertFalse(receipt.promoted)
            XCTAssertEqual(receipt.code, .renameFailed)
            XCTAssertEqual(receipt.word, "Down")
            XCTAssertTrue(receipt.summary.contains("Permission denied"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
        }
    }

    func testPromoteOntoADirectoryFails() throws {
        try withTemp { root in
            let partial = try plainFile(root, "file.ht-partial", Data("abc".utf8))
            let dest = root.appendingPathComponent("dest", isDirectory: true)
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let error = promotePartial(partial: partial, destination: dest)
            XCTAssertNotNil(error)
            XCTAssertTrue(FileManager.default.fileExists(atPath: partial.path))
        }
    }

    func testInodeChangeIsNamedWhenBytesMatch() throws {
        try withTemp { root in
            let source = try plainFile(root, "source.bin", Data("same-bytes".utf8))
            let receipt = transferFile(source: source, destination: root.appendingPathComponent("out.bin"), endpoint: ScriptedEndpoint(), afterFirstHash: { path in
                let other = path.deletingLastPathComponent().appendingPathComponent("replacement.bin")
                try? Data(contentsOf: path).write(to: other)
                try? FileManager.default.removeItem(at: path)
                try? FileManager.default.moveItem(at: other, to: path)
            })
            XCTAssertEqual(receipt.code, .match, receipt.summary)
            XCTAssertTrue(receipt.inodeChanged)
            XCTAssertTrue(receipt.summary.contains("inode changed"))
        }
    }

    func testDirectoryIncludesDotfile() throws {
        try withTemp { root in
            let source = root.appendingPathComponent("src", isDirectory: true)
            _ = try plainFile(source, ".secret", Data("hidden".utf8))
            _ = try plainFile(source, "visible.txt", Data("shown".utf8))
            let dest = root.appendingPathComponent("dst", isDirectory: true)
            let result = transferDirectory(source: source, destination: dest, endpointFactory: { ScriptedEndpoint() })
            XCTAssertEqual(result.code, .match, result.summary)
            XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent(".secret")), Data("hidden".utf8))
            XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("visible.txt")), Data("shown".utf8))
        }
    }

    func testDirectorySkipsSymlinkAndIsNotComplete() throws {
        try withTemp { root in
            let outside = root.appendingPathComponent("outside", isDirectory: true)
            _ = try plainFile(outside, "secret", Data("nope".utf8))
            let source = root.appendingPathComponent("src", isDirectory: true)
            _ = try plainFile(source, "ok.txt", Data("yes".utf8))
            try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("link.txt"), withDestinationURL: outside.appendingPathComponent("secret"))
            try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("linkdir"), withDestinationURL: outside)
            let dest = root.appendingPathComponent("dst", isDirectory: true)
            let result = transferDirectory(source: source, destination: dest, endpointFactory: { ScriptedEndpoint() })
            XCTAssertEqual(result.code, .incomplete)
            XCTAssertEqual(result.word, "Down")
            XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("ok.txt")), Data("yes".utf8))
            XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent("secret").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent("linkdir/secret").path))
            XCTAssertTrue(result.skipped.contains { $0.reason.contains("symlink") })
        }
    }

    func testRefusesCopyIntoItself() throws {
        try withTemp { root in
            let source = root.appendingPathComponent("src", isDirectory: true)
            _ = try plainFile(source, "a.txt", Data("a".utf8))
            let result = transferDirectory(source: source, destination: source.appendingPathComponent("nested"), endpointFactory: { ScriptedEndpoint() })
            XCTAssertEqual(result.code, .refused)
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.appendingPathComponent("nested").path))
        }
    }

    func testEmptyFolderIsPlaceNotMatch() throws {
        try withTemp { root in
            let source = root.appendingPathComponent("src", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            let result = transferDirectory(source: source, destination: root.appendingPathComponent("dst"), endpointFactory: { ScriptedEndpoint() })
            XCTAssertEqual(result.code, .empty)
            XCTAssertEqual(result.word, "Place")
            XCTAssertNotEqual(result.word, "Match")
        }
    }

    func testBlake2bMatchesTheEmptyAndAbcVectors() {
        XCTAssertEqual(Blake2b.hash(Data()).hexString, emptyBlake2b)
        let abc = Blake2b.hash(Data("abc".utf8)).hexString
        XCTAssertEqual(abc, "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923")
        XCTAssertEqual(SHA512.hash(data: Data()).hex, emptySHA512)
        let block = Data(repeating: 0x61, count: 128)
        let once = Blake2b.hash(block)
        var streamed = Blake2b()
        streamed.update(block.prefix(40))
        streamed.update(block.suffix(from: 40))
        XCTAssertEqual(streamed.finalize(), once)
    }

    func testTwoReadsThatDisagreeAreNotTrusted() {
        let original = Data("abcdefghij-0123456789".utf8)
        var flipped = original
        flipped[3] ^= 0xFF
        let left = Cursor(original)
        let right = Cursor(flipped)
        XCTAssertThrowsError(try stableDigest(readA: { left.read($0) }, readB: { right.read($0) })) { error in
            XCTAssertEqual((error as? TransferError)?.code, .mediaDisagreed)
        }
    }
}

private final class Cursor {
    private let data: Data
    private var offset = 0
    init(_ data: Data) { self.data = data }
    func read(_ count: Int) -> Data {
        if offset >= data.count { return Data() }
        let end = min(data.count, offset + count)
        let slice = data.subdata(in: offset..<end)
        offset = end
        return slice
    }
}
