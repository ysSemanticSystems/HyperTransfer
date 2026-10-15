import CryptoKit
import Foundation

/// A one-sided RDMA write does not tap the receiver on the shoulder.
/// The record is that tap. The flush read of the tail happens first,
/// because a completed write can still be invisible to the other CPU.
/// The record carries SHA-512 and BLAKE2b so one collision is not enough.
public enum Completion {
    public static let length = 160
    public static let magic = Data([0x48, 0x54, 0x43, 0x31])

    public struct Record: Equatable, Sendable {
        public var chunkIndex: UInt32
        public var offset: UInt64
        public var byteCount: UInt64
        public var sha512: Data
        public var blake2b: Data
    }

    public static func build(chunkIndex: UInt32, offset: UInt64, payload: Data) -> Data {
        var data = Data(count: length)
        data.replaceSubrange(0..<4, with: magic)
        write(UInt16(2), into: &data, at: 4)
        write(UInt16(0), into: &data, at: 6)
        write(chunkIndex, into: &data, at: 8)
        write(UInt32(0), into: &data, at: 12)
        write(offset, into: &data, at: 16)
        write(UInt64(payload.count), into: &data, at: 24)
        data.replaceSubrange(32..<96, with: Data(SHA512.hash(data: payload)))
        data.replaceSubrange(96..<160, with: Blake2b.hash(payload))
        return data
    }

    public static func parse(_ raw: Data) throws -> Record {
        guard raw.count == length else {
            throw TransferError.notNotified("The completion record is not 160 bytes, so the receiver was not notified.")
        }
        let version: UInt16 = read(raw, at: 4)
        guard raw.prefix(4).elementsEqual(magic), version == 2 else {
            throw TransferError.notNotified("No completion record is visible yet. The receiver was not notified.")
        }
        return Record(
            chunkIndex: read(raw, at: 8),
            offset: read(raw, at: 16),
            byteCount: read(raw, at: 24),
            sha512: raw.subdata(in: 32..<96),
            blake2b: raw.subdata(in: 96..<160)
        )
    }
}

public func takeChunk(cookie: Data, payload: Data, chunkIndex: UInt32) throws -> Data {
    let record = try Completion.parse(cookie)
    guard record.chunkIndex == chunkIndex else {
        throw TransferError.notNotified(
            "The visible completion is for chunk \(record.chunkIndex), not chunk \(chunkIndex)."
        )
    }
    guard UInt64(payload.count) == record.byteCount else {
        throw TransferError.writeIncomplete(
            "The CPU-visible length does not match the completion record. The write is incomplete."
        )
    }
    let sha = Data(SHA512.hash(data: payload))
    let blake = Blake2b.hash(payload)
    guard sha == record.sha512, blake == record.blake2b else {
        throw TransferError.writeIncomplete(
            "The CPU-visible bytes do not match the completion record. The write is incomplete."
        )
    }
    return payload
}

public protocol ChunkEndpoint: AnyObject {
    func land(chunkIndex: UInt32, offset: UInt64, payload: Data) throws
    func cpuCookie() -> Data
    func cpuPayload(offset: Int, count: Int) -> Data
    var lastRecord: Data { get }
}

public enum ChunkVisibility: Sendable {
    case fenced
    case dataHidden
    case cookieHidden
}

public final class ByteWindow: @unchecked Sendable {
    private var nic = Data()
    private var cpu = Data()

    public init() {}

    public func nicWrite(offset: Int, data: Data) {
        grow(&nic, to: offset + data.count)
        nic.replaceSubrange(offset..<(offset + data.count), with: data)
    }

    public func nicRead(offset: Int, count: Int) -> Data {
        grow(&nic, to: offset + count)
        return nic.subdata(in: offset..<(offset + count))
    }

    public func publish(offset: Int, count: Int) {
        grow(&nic, to: offset + count)
        grow(&cpu, to: offset + count)
        cpu.replaceSubrange(offset..<(offset + count), with: nic.subdata(in: offset..<(offset + count)))
    }

    public func cpuRead(offset: Int, count: Int) -> Data {
        grow(&cpu, to: offset + count)
        return cpu.subdata(in: offset..<(offset + count))
    }

    private func grow(_ buffer: inout Data, to end: Int) {
        if end > buffer.count {
            buffer.append(Data(count: end - buffer.count))
        }
    }
}

public final class ScriptedEndpoint: ChunkEndpoint, @unchecked Sendable {
    public let visibility: ChunkVisibility
    public let corruptFlush: Bool
    public let dataWindow = ByteWindow()
    public let cookieWindow = ByteWindow()
    public private(set) var lastRecord = Data()

    public init(visibility: ChunkVisibility = .fenced, corruptFlush: Bool = false) {
        self.visibility = visibility
        self.corruptFlush = corruptFlush
    }

    public func land(chunkIndex: UInt32, offset: UInt64, payload: Data) throws {
        let start = Int(offset)
        if !payload.isEmpty {
            dataWindow.nicWrite(offset: start, data: payload)
            let tailCount = min(8, payload.count)
            var tail = dataWindow.nicRead(offset: start + payload.count - tailCount, count: tailCount)
            if corruptFlush, let first = tail.first {
                tail[0] = first ^ 0xFF
            }
            let expected = payload.suffix(tailCount)
            guard tail.elementsEqual(expected) else {
                throw TransferError.flush(
                    "The flush read of the tail does not match the bytes just written. The chunk was not published."
                )
            }
        }
        let record = Completion.build(chunkIndex: chunkIndex, offset: offset, payload: payload)
        cookieWindow.nicWrite(offset: 0, data: record)
        lastRecord = record
        switch visibility {
        case .cookieHidden:
            if !payload.isEmpty {
                dataWindow.publish(offset: start, count: payload.count)
            }
        case .dataHidden:
            cookieWindow.publish(offset: 0, count: Completion.length)
        case .fenced:
            if !payload.isEmpty {
                dataWindow.publish(offset: start, count: payload.count)
            }
            cookieWindow.publish(offset: 0, count: Completion.length)
        }
    }

    public func cpuCookie() -> Data {
        cookieWindow.cpuRead(offset: 0, count: Completion.length)
    }

    public func cpuPayload(offset: Int, count: Int) -> Data {
        dataWindow.cpuRead(offset: offset, count: count)
    }
}

private func write<T: FixedWidthInteger>(_ value: T, into data: inout Data, at offset: Int) {
    var little = value.littleEndian
    withUnsafeBytes(of: &little) { raw in
        data.replaceSubrange(offset..<(offset + raw.count), with: raw)
    }
}

private func read<T: FixedWidthInteger>(_ data: Data, at offset: Int) -> T {
    let width = MemoryLayout<T>.size
    let slice = data.subdata(in: offset..<(offset + width))
    return slice.withUnsafeBytes { raw in
        T(littleEndian: raw.load(as: T.self))
    }
}
