import Foundation
@testable import HyperTransferCore

final class BrowseTests {
    func testBrowseRejectsDotDot() throws {
        try withTemp { root in
            let base = root.appendingPathComponent("root", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            XCTAssertThrowsError(try resolveInside(root: base, relative: "../outside")) { error in
                XCTAssertEqual((error as? TransferError)?.code, .refused)
            }
            XCTAssertThrowsError(try resolveInside(root: base, relative: "/etc/passwd"))
        }
    }

    func testBrowseRejectsSymlinkEscape() throws {
        try withTemp { root in
            let base = root.appendingPathComponent("root", isDirectory: true)
            let outside = root.appendingPathComponent("outside", isDirectory: true)
            _ = try plainFile(outside, "secret", Data("no".utf8))
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: base.appendingPathComponent("link"), withDestinationURL: outside.appendingPathComponent("secret"))
            XCTAssertThrowsError(try resolveInside(root: base, relative: "link"))
            let listing = try listDirectory(root: base, relative: ".")
            let link = listing.entries.first { $0.name == "link" }
            XCTAssertEqual(link?.kind, "link")
            XCTAssertEqual(link?.leavesRoot, true)
        }
    }

    func testBrowseListsKindsAndKeepsHiddenNames() throws {
        try withTemp { root in
            let base = root.appendingPathComponent("root", isDirectory: true)
            _ = try plainFile(base, ".secret", Data("h".utf8))
            _ = try plainFile(base, "note.txt", Data("hello".utf8))
            try FileManager.default.createDirectory(at: base.appendingPathComponent("folder"), withIntermediateDirectories: true)
            let listing = try listDirectory(root: base, relative: ".")
            let names = Dictionary(uniqueKeysWithValues: listing.entries.map { ($0.name, $0) })
            XCTAssertEqual(names[".secret"]?.hidden, true)
            XCTAssertEqual(names["note.txt"]?.kind, "file")
            XCTAssertEqual(names["folder"]?.kind, "folder")
            XCTAssertEqual(listing.entries.first?.kind, "folder")
        }
    }

    func testPreviewIsAWindowWithoutAFileHash() throws {
        try withTemp { root in
            let base = root.appendingPathComponent("root", isDirectory: true)
            _ = try plainFile(base, "note.txt", Data("hello ".utf8) + Data(repeating: 0x78, count: 5000))
            let viewed = try previewFile(root: base, relative: "note.txt", limit: 16)
            XCTAssertEqual(viewed.windowBytes, 16)
            XCTAssertTrue(viewed.truncated)
            XCTAssertGreaterThan(viewed.fileBytes, 16)
            XCTAssertEqual(viewed.kind, "text")
            XCTAssertEqual(viewed.body, "hello xxxxxxxxxx")
        }
    }

    func testPreviewOfBinaryIsHex() throws {
        try withTemp { root in
            let base = root.appendingPathComponent("root", isDirectory: true)
            _ = try plainFile(base, "bin.dat", Data([0xFF, 0x00, 0xFE]))
            let viewed = try previewFile(root: base, relative: "bin.dat")
            XCTAssertEqual(viewed.kind, "hex")
            XCTAssertEqual(viewed.body, "ff00fe")
            XCTAssertFalse(viewed.truncated)
        }
    }

    func testResolvePlaceAllowsANewFinalName() throws {
        try withTemp { root in
            let base = root.appendingPathComponent("peer", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let place = try resolvePlace(root: base, relative: "note.txt")
            XCTAssertEqual(place.lastPathComponent, "note.txt")
            XCTAssertFalse(FileManager.default.fileExists(atPath: place.path))
        }
    }

    func testResolvePlaceRefusesAMissingParent() throws {
        try withTemp { root in
            let base = root.appendingPathComponent("peer", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            XCTAssertThrowsError(try resolvePlace(root: base, relative: "missing/note.txt"))
        }
    }

    func testPartialFileIsLabeledPartial() throws {
        try withTemp { root in
            let base = root.appendingPathComponent("root", isDirectory: true)
            _ = try plainFile(base, "note.txt.ht-partial", Data("x".utf8))
            let listing = try listDirectory(root: base, relative: ".")
            XCTAssertEqual(listing.entries.first?.kind, "partial")
        }
    }
}

final class GateTests {
    func testCopyStaysClosedWithoutRDMA() {
        let report = buildReport(ports: parseThunderbolt(connectedThunderbolt), verbsLibrary: nil, disk: sampleDisk())
        XCTAssertFalse(CopyGate.canBrowse(report))
        XCTAssertTrue(CopyGate.refusal(fabric: report).contains("unreachable"))
    }

    func testCopyStaysClosedWhenRDMAIsUpAndNoPeerExists() {
        let roce = classifyVerbsPort(name: "mlx5_0/1", linkLayer: "Ethernet", state: "4: ACTIVE", driver: "mlx5_core", sysfsPath: "/sys/class/infiniband/mlx5_0")
        let report = buildReport(ports: [roce], verbsLibrary: nil, disk: sampleDisk())
        XCTAssertTrue(CopyGate.canBrowse(report))
        XCTAssertTrue(CopyGate.refusal(fabric: report).contains("no queue pair"))
    }

    func testMissingProbeIsClosed() {
        XCTAssertFalse(CopyGate.canBrowse(nil))
        XCTAssertTrue(CopyGate.refusal(fabric: nil).contains("Nothing is treated as RDMA"))
    }

    func testEveryTipSaysWhatItReadsAndWhatThatCanHide() {
        for tip in Tips.all {
            XCTAssertGreaterThan(tip.count, 40, tip)
            XCTAssertTrue(tip.lowercased().contains("read"), tip)
            XCTAssertTrue(tip.lowercased().contains("hide"), tip)
        }
        let dynamic = Tips.row("Notes", kind: "File", leavesRoot: false)
        XCTAssertTrue(dynamic.lowercased().contains("read"))
        XCTAssertTrue(dynamic.lowercased().contains("hide"))
        let port = classifyVerbsPort(name: "mlx5_0/1", linkLayer: "Ethernet", state: "4: ACTIVE", driver: "mlx5_core", sysfsPath: "/sys")
        let portTip = Tips.port(port)
        XCTAssertTrue(portTip.lowercased().contains("read"))
        XCTAssertTrue(portTip.lowercased().contains("hide"))
    }
}

final class SourceContractTests {
    func testCoreDoesNotOpenASocket() throws {
        let root = repoRoot().appendingPathComponent("Sources/HyperTransferCore")
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let banned = ["import Network", "URLSession", "NWConnection", "NWListener", "CFSocket", "Darwin.socket("]
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for word in banned {
                XCTAssertFalse(text.contains(word), "\(file.lastPathComponent) contains \(word)")
            }
        }
    }

    func testAppDoesNotBindAPort() throws {
        let root = repoRoot().appendingPathComponent("Sources")
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let item = enumerator?.nextObject() as? URL {
            guard item.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: item, encoding: .utf8)
            XCTAssertFalse(text.contains("8819"), item.lastPathComponent)
            XCTAssertFalse(text.contains(".help(\""), "\(item.lastPathComponent) has a literal help string")
        }
    }

    func testWindowPairsHelpWithAnAccessibilityHint() throws {
        let view = repoRoot().appendingPathComponent("Sources/HyperTransfer/ContentView.swift")
        let text = try String(contentsOf: view, encoding: .utf8)
        let help = text.components(separatedBy: ".help(").count - 1
        let hint = text.components(separatedBy: ".accessibilityHint(").count - 1
        XCTAssertGreaterThan(help, 8)
        XCTAssertEqual(help, hint)
    }

    func testInvariantsCatalogLocksExist() throws {
        let text = try String(contentsOf: repoRoot().appendingPathComponent("docs/invariants.md"), encoding: .utf8)
        let tests = try definedTests()
        let pattern = #"### (INV-[A-Z]+-\d+)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        XCTAssertFalse(matches.isEmpty)
        var seen = Set<String>()
        for match in matches {
            let ident = String(text[Range(match.range(at: 1), in: text)!])
            XCTAssertTrue(seen.insert(ident).inserted)
            let start = text.index(text.startIndex, offsetBy: match.range.location)
            let rest = text[start...]
            let bodyEnd = rest.dropFirst().range(of: "\n### ")?.lowerBound ?? rest.endIndex
            let body = rest[..<bodyEnd]
            guard body.contains("**status**: active") else { continue }
            guard let lockRange = body.range(of: "**lock**: ") else {
                XCTFail("\(ident) has no lock")
                continue
            }
            let lockLine = body[lockRange.upperBound...].prefix { $0 != "\n" }
            let names = lockLine.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            XCTAssertFalse(names.isEmpty, ident)
            for name in names {
                XCTAssertTrue(tests.contains(name), "\(ident) missing \(name)")
            }
        }
    }

    private func definedTests() throws -> Set<String> {
        let root = repoRoot().appendingPathComponent("Tests")
        var names = Set<String>()
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        let regex = try NSRegularExpression(pattern: #"func (test[A-Za-z0-9_]+)\("#)
        while let item = enumerator?.nextObject() as? URL {
            guard item.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: item, encoding: .utf8)
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                names.insert(String(text[Range(match.range(at: 1), in: text)!]))
            }
        }
        return names
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
