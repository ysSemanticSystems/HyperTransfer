import Foundation
@testable import HyperTransferCore

final class PeerTests {
    func testPeerCopyMatchesAcrossTwoChunks() throws {
        try withTemp { root in
            let sourceRoot = root.appendingPathComponent("src", isDirectory: true)
            let destRoot = root.appendingPathComponent("dst", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destRoot, withIntermediateDirectories: true)
            let file = try plainFile(sourceRoot, "note.txt", Data("hello".utf8))
            let (sender, receiver) = duplex()
            let done = DispatchSemaphore(value: 0)
            let box = ErrorBox()
            DispatchQueue.global().async {
                do {
                    let header = try receiver.recvFrame(fileHeaderLength)
                    _ = try receiveFile(link: receiver, root: destRoot, header: header)
                } catch {
                    box.error = error
                }
                done.signal()
            }
            let receipt = sendFile(link: sender, source: file, relative: "note.txt", replace: false, chunkSize: 4)
            done.wait()
            XCTAssertNil(box.error)
            XCTAssertEqual(receipt.word, "Match")
            XCTAssertEqual(try Data(contentsOf: destRoot.appendingPathComponent("note.txt")), Data("hello".utf8))
        }
    }

    func testPeerCopyMatchesAnEmptyFile() throws {
        try withTemp { root in
            let sourceRoot = root.appendingPathComponent("src", isDirectory: true)
            let destRoot = root.appendingPathComponent("dst", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destRoot, withIntermediateDirectories: true)
            let file = try plainFile(sourceRoot, "empty.txt", Data())
            let (sender, receiver) = duplex()
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                if let header = try? receiver.recvFrame(fileHeaderLength) {
                    _ = try? receiveFile(link: receiver, root: destRoot, header: header)
                }
                done.signal()
            }
            let receipt = sendFile(link: sender, source: file, relative: "empty.txt", replace: false, chunkSize: 4)
            done.wait()
            XCTAssertEqual(receipt.word, "Match")
            XCTAssertEqual(try Data(contentsOf: destRoot.appendingPathComponent("empty.txt")), Data())
        }
    }

    func testPeerCopyDoesNotRenameWithoutTheRecord() throws {
        try withTemp { root in
            let sourceRoot = root.appendingPathComponent("src", isDirectory: true)
            let destRoot = root.appendingPathComponent("dst", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destRoot, withIntermediateDirectories: true)
            let file = try plainFile(sourceRoot, "note.txt", Data("hello".utf8))
            let (sender, inner) = duplex()
            let receiver = DropRecord(inner: inner)
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                if let header = try? receiver.recvFrame(fileHeaderLength) {
                    _ = try? receiveFile(link: receiver, root: destRoot, header: header)
                }
                done.signal()
            }
            let receipt = sendFile(link: sender, source: file, relative: "note.txt", replace: false, chunkSize: 8)
            done.wait()
            XCTAssertEqual(receipt.word, "Down")
            XCTAssertFalse(FileManager.default.fileExists(atPath: destRoot.appendingPathComponent("note.txt").path))
        }
    }

    func testPeerCopyRefusesAPathThatLeavesTheRoot() throws {
        try withTemp { root in
            guard let header = encodeFileOffer(FileOffer(relative: "../outside.txt", byteCount: 0, chunkSize: 4, replace: false)) else {
                XCTFail("header")
                return
            }
            let link = CaptureLink()
            XCTAssertThrowsError(try receiveFile(link: link, root: root, header: header))
            guard let answer = link.sent.first else {
                XCTFail("no answer")
                return
            }
            XCTAssertEqual(decodeAnswer(answer)?.0, false)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("outside.txt").path))
        }
    }

    func testPeerCopyDoesNotRenameWhenTheSourceChanges() throws {
        try withTemp { root in
            let sourceRoot = root.appendingPathComponent("src", isDirectory: true)
            let destRoot = root.appendingPathComponent("dst", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destRoot, withIntermediateDirectories: true)
            let file = try plainFile(sourceRoot, "note.txt", Data("hello".utf8))
            let (sender, receiver) = duplex()
            let changing = MutateOnDigest(inner: sender, file: file)
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                if let header = try? receiver.recvFrame(fileHeaderLength) {
                    _ = try? receiveFile(link: receiver, root: destRoot, header: header)
                }
                done.signal()
            }
            let receipt = sendFile(link: changing, source: file, relative: "note.txt", replace: false, chunkSize: 8)
            done.wait()
            XCTAssertEqual(receipt.word, "Down")
            XCTAssertFalse(FileManager.default.fileExists(atPath: destRoot.appendingPathComponent("note.txt").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: destRoot.appendingPathComponent("note.txt.ht-partial").path))
        }
    }

    func testPeerCopyLeavesAnExistingFile() throws {
        try withTemp { root in
            let sourceRoot = root.appendingPathComponent("src", isDirectory: true)
            let destRoot = root.appendingPathComponent("dst", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destRoot, withIntermediateDirectories: true)
            let file = try plainFile(sourceRoot, "note.txt", Data("hello".utf8))
            try Data("old".utf8).write(to: destRoot.appendingPathComponent("note.txt"))
            let (sender, receiver) = duplex()
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                if let header = try? receiver.recvFrame(fileHeaderLength) {
                    _ = try? receiveFile(link: receiver, root: destRoot, header: header)
                }
                done.signal()
            }
            let receipt = sendFile(link: sender, source: file, relative: "note.txt", replace: false, chunkSize: 8)
            done.wait()
            XCTAssertEqual(receipt.word, "Down")
            XCTAssertEqual(try Data(contentsOf: destRoot.appendingPathComponent("note.txt")), Data("old".utf8))
        }
    }

    func testPeerCopyReplacesOnlyAfterTheThreeReadsAgree() throws {
        try withTemp { root in
            let sourceRoot = root.appendingPathComponent("src", isDirectory: true)
            let destRoot = root.appendingPathComponent("dst", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destRoot, withIntermediateDirectories: true)
            let file = try plainFile(sourceRoot, "note.txt", Data("hello".utf8))
            try Data("old".utf8).write(to: destRoot.appendingPathComponent("note.txt"))
            let (sender, receiver) = duplex()
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                if let header = try? receiver.recvFrame(fileHeaderLength) {
                    _ = try? receiveFile(link: receiver, root: destRoot, header: header)
                }
                done.signal()
            }
            let receipt = sendFile(link: sender, source: file, relative: "note.txt", replace: true, chunkSize: 8)
            done.wait()
            XCTAssertEqual(receipt.word, "Match")
            XCTAssertEqual(try Data(contentsOf: destRoot.appendingPathComponent("note.txt")), Data("hello".utf8))
        }
    }

    func testPeerCopyRejectsAnAbsolutePath() throws {
        try withTemp { root in
            guard let header = encodeFileOffer(FileOffer(relative: "/tmp/outside.txt", byteCount: 0, chunkSize: 4, replace: false)) else {
                XCTFail("header")
                return
            }
            let link = CaptureLink()
            XCTAssertThrowsError(try receiveFile(link: link, root: root, header: header))
            guard let answer = link.sent.first else {
                XCTFail("no answer")
                return
            }
            XCTAssertEqual(decodeAnswer(answer)?.0, false)
        }
    }

    func testPeerCopyRejectsAShortHeader() throws {
        try withTemp { root in
            let link = CaptureLink()
            XCTAssertThrowsError(try receiveFile(link: link, root: root, header: Data(count: 10)))
            guard let answer = link.sent.first else {
                XCTFail("no answer")
                return
            }
            XCTAssertEqual(decodeAnswer(answer)?.0, false)
            XCTAssertNil(decodeFileOffer(Data(count: 10)))
        }
    }

    func testPeerCopyDoesNotRenameACorruptRecord() throws {
        try withTemp { root in
            let sourceRoot = root.appendingPathComponent("src", isDirectory: true)
            let destRoot = root.appendingPathComponent("dst", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destRoot, withIntermediateDirectories: true)
            let file = try plainFile(sourceRoot, "note.txt", Data("hello".utf8))
            let (sender, inner) = duplex()
            let receiver = CorruptRecord(inner: inner)
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                if let header = try? receiver.recvFrame(fileHeaderLength) {
                    _ = try? receiveFile(link: receiver, root: destRoot, header: header)
                }
                done.signal()
            }
            let receipt = sendFile(link: sender, source: file, relative: "note.txt", replace: false, chunkSize: 8)
            done.wait()
            XCTAssertEqual(receipt.word, "Down")
            XCTAssertFalse(FileManager.default.fileExists(atPath: destRoot.appendingPathComponent("note.txt").path))
        }
    }

    func testPeerCopyDoesNotPostAnEmptyRecordAfterAnExactChunk() throws {
        try withTemp { root in
            let sourceRoot = root.appendingPathComponent("src", isDirectory: true)
            let destRoot = root.appendingPathComponent("dst", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destRoot, withIntermediateDirectories: true)
            let file = try plainFile(sourceRoot, "note.txt", Data("abcd".utf8))
            let (inner, receiver) = duplex()
            let sender = CountRecords(inner: inner)
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                if let header = try? receiver.recvFrame(fileHeaderLength) {
                    _ = try? receiveFile(link: receiver, root: destRoot, header: header)
                }
                done.signal()
            }
            let receipt = sendFile(link: sender, source: file, relative: "note.txt", replace: false, chunkSize: 4)
            done.wait()
            XCTAssertEqual(receipt.word, "Match")
            XCTAssertEqual(sender.records, 1)
        }
    }

    func testThunderboltFramesRoundTo4096() {
        XCTAssertEqual(thunderboltWireLength(0), 4096)
        XCTAssertEqual(thunderboltWireLength(1), 4096)
        XCTAssertEqual(thunderboltWireLength(160), 4096)
        XCTAssertEqual(thunderboltWireLength(4096), 4096)
        XCTAssertEqual(thunderboltWireLength(4097), 8192)
        XCTAssertEqual(thunderboltWireLength(1024 * 1024), 1024 * 1024)
    }

    func testSetupRecordRejectsAnythingBut64Bytes() {
        XCTAssertFalse(queuePairRecordAccepted(Data()))
        XCTAssertFalse(queuePairRecordAccepted(Data(count: 63)))
        XCTAssertFalse(queuePairRecordAccepted(Data(count: 65)))
        XCTAssertFalse(queuePairRecordAccepted(Data(count: 1024 * 1024)))
        var foreign = Data(count: 64)
        foreign[0] = 0x41
        XCTAssertFalse(queuePairRecordAccepted(foreign))
        var hello = Data(count: 64)
        hello.replaceSubrange(0..<4, with: Data("HTQ1".utf8))
        XCTAssertTrue(queuePairRecordAccepted(hello))
        hello.replaceSubrange(0..<4, with: Data("HTGO".utf8))
        XCTAssertFalse(queuePairRecordAccepted(hello))
    }

    func testPeerListShowsTheFolderThatWillReceiveTheCopy() throws {
        try withTemp { root in
            let dest = root.appendingPathComponent("dst", isDirectory: true)
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            _ = try plainFile(dest, "note.txt", Data("hello".utf8))
            try FileManager.default.createDirectory(at: dest.appendingPathComponent("Photos"), withIntermediateDirectories: true)
            let (sender, receiver) = duplex()
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                if let header = try? receiver.recvFrame(fileHeaderLength) {
                    try? answerPeerList(link: receiver, root: dest, header: header)
                }
                done.signal()
            }
            let listing = try requestPeerList(link: sender, relative: ".")
            done.wait()
            XCTAssertEqual(listing.path, ".")
            XCTAssertTrue(listing.entries.contains { $0.name == "note.txt" && $0.kind == "file" })
            XCTAssertTrue(listing.entries.contains { $0.name == "Photos" && $0.kind == "folder" })
            XCTAssertFalse(listing.truncated)
        }
    }

    func testPeerListKeepsAHiddenName() throws {
        try withTemp { root in
            let dest = root.appendingPathComponent("dst", isDirectory: true)
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            _ = try plainFile(dest, ".secret", Data("x".utf8))
            let (sender, receiver) = duplex()
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                if let header = try? receiver.recvFrame(fileHeaderLength) {
                    try? answerPeerList(link: receiver, root: dest, header: header)
                }
                done.signal()
            }
            let listing = try requestPeerList(link: sender, relative: ".")
            done.wait()
            XCTAssertTrue(listing.entries.contains { $0.name == ".secret" && $0.hidden })
        }
    }

    func testPeerListRefusesAPathThatLeavesTheRoot() throws {
        XCTAssertNil(encodeListRequest("../out"))
        XCTAssertNil(encodeListRequest("/tmp/out"))
        XCTAssertNil(encodeListRequest("Docs/../../out"))
        XCTAssertNotNil(encodeListRequest("."))
        try withTemp { root in
            let dest = root.appendingPathComponent("dst", isDirectory: true)
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            var header = Data(count: fileHeaderLength)
            header.replaceSubrange(0..<4, with: Data("HTLS".utf8))
            header[4] = 1
            let path = Array("../out".utf8)
            header[6] = UInt8(path.count)
            header.replaceSubrange(8..<(8 + path.count), with: path)
            let (sender, receiver) = duplex()
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                if let got = try? receiver.recvFrame(fileHeaderLength) {
                    try? answerPeerList(link: receiver, root: dest, header: got)
                }
                done.signal()
            }
            try sender.sendFrame(header)
            let page = try sender.recvFrame(peerListLength)
            done.wait()
            let decoded = decodePeerList(page)
            XCTAssertEqual(decoded?.ok, false)
            XCTAssertTrue(decoded?.detail.contains("leaves the peer root") == true)
        }
    }

    func testPeerListRefusesASymlink() throws {
        try withTemp { root in
            let dest = root.appendingPathComponent("dst", isDirectory: true)
            let outside = root.appendingPathComponent("outside", isDirectory: true)
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: dest.appendingPathComponent("jump"), withDestinationURL: outside)
            let (sender, receiver) = duplex()
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                if let header = try? receiver.recvFrame(fileHeaderLength) {
                    try? answerPeerList(link: receiver, root: dest, header: header)
                }
                done.signal()
            }
            XCTAssertThrowsError(try requestPeerList(link: sender, relative: "jump"))
            done.wait()
        }
    }

    func testPeerListStopsEarlyWhenThePageIsFull() {
        let entries = (0..<400).map { index in
            DirectoryEntry(
                name: String(repeating: "n", count: 180) + "\(index)",
                kind: "file", size: 1, modified: nil, hidden: false,
                relative: "f\(index)", leavesRoot: false
            )
        }
        let page = decodePeerList(encodePeerList(
            ok: true, path: ".", parent: nil, entries: entries, detail: "", truncated: false
        ))
        XCTAssertEqual(page?.ok, true)
        XCTAssertEqual(page?.truncated, true)
        XCTAssertTrue((page?.entries.count ?? 400) < 400)
        XCTAssertGreaterThan(page?.entries.count ?? 0, 0)
        XCTAssertTrue(page?.detail.contains("stopped early") == true)
    }

    func testFileHeaderIsNotAPeerList() {
        let request = encodeListRequest("Docs")
        XCTAssertNil(decodeFileOffer(request ?? Data()))
        let offer = encodeFileOffer(FileOffer(relative: "Docs/a.txt", byteCount: 1, chunkSize: 4, replace: false))
        XCTAssertNil(decodePeerList(offer ?? Data()))
        XCTAssertEqual(offer?.prefix(4), Data("HTF1".utf8))
        XCTAssertEqual(request?.prefix(4), Data("HTLS".utf8))
    }
}

private final class ErrorBox: @unchecked Sendable {
    var error: Error?
}

private func duplex() -> (Duplex, Duplex) {
    let aToB = FramePipe()
    let bToA = FramePipe()
    return (Duplex(outbound: aToB, inbound: bToA), Duplex(outbound: bToA, inbound: aToB))
}

private final class FramePipe: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [Data] = []
    private let signal = DispatchSemaphore(value: 0)

    func send(_ data: Data) {
        lock.lock()
        frames.append(data)
        lock.unlock()
        signal.signal()
    }

    func recv(_ count: Int) throws -> Data {
        signal.wait()
        lock.lock()
        let data = frames.removeFirst()
        lock.unlock()
        guard data.count == count else {
            throw TransferError(.ioError, "A frame of \(data.count) bytes arrived where \(count) were required.")
        }
        return data
    }
}

private final class Duplex: FrameLink, @unchecked Sendable {
    let outbound: FramePipe
    let inbound: FramePipe
    init(outbound: FramePipe, inbound: FramePipe) {
        self.outbound = outbound
        self.inbound = inbound
    }
    func sendFrame(_ data: Data) throws { outbound.send(data) }
    func recvFrame(_ count: Int) throws -> Data { try inbound.recv(count) }
}

private final class MutateOnDigest: FrameLink, @unchecked Sendable {
    let inner: FrameLink
    let file: URL
    init(inner: FrameLink, file: URL) {
        self.inner = inner
        self.file = file
    }
    func sendFrame(_ data: Data) throws { try inner.sendFrame(data) }
    func recvFrame(_ count: Int) throws -> Data {
        let data = try inner.recvFrame(count)
        if count == peerDigestLength {
            try Data("changed-under-the-copy".utf8).write(to: file)
        }
        return data
    }
}

private final class CorruptRecord: FrameLink, @unchecked Sendable {
    let inner: FrameLink
    init(inner: FrameLink) { self.inner = inner }
    func sendFrame(_ data: Data) throws { try inner.sendFrame(data) }
    func recvFrame(_ count: Int) throws -> Data {
        var data = try inner.recvFrame(count)
        if count == Completion.length, !data.isEmpty {
            data[0] ^= 0xFF
        }
        return data
    }
}

private final class CountRecords: FrameLink, @unchecked Sendable {
    let inner: FrameLink
    var records = 0
    init(inner: FrameLink) { self.inner = inner }
    func sendFrame(_ data: Data) throws {
        if data.count == Completion.length { records += 1 }
        try inner.sendFrame(data)
    }
    func recvFrame(_ count: Int) throws -> Data { try inner.recvFrame(count) }
}

private final class DropRecord: FrameLink, @unchecked Sendable {
    let inner: FrameLink
    private var recvs = 0
    init(inner: FrameLink) { self.inner = inner }
    func sendFrame(_ data: Data) throws { try inner.sendFrame(data) }
    func recvFrame(_ count: Int) throws -> Data {
        recvs += 1
        if recvs == 2 {
            throw TransferError.notNotified("The completion record did not arrive.")
        }
        return try inner.recvFrame(count)
    }
}

private final class CaptureLink: FrameLink {
    var sent: [Data] = []
    func sendFrame(_ data: Data) throws { sent.append(data) }
    func recvFrame(_ count: Int) throws -> Data {
        throw TransferError(.ioError, "The receiver stopped.")
    }
}
