import Foundation

/// BLAKE2b-512. A different construction from SHA-512, so one collision does not satisfy both.
public struct Blake2b {
    private static let blockSize = 128
    private static let iv: [UInt64] = [
        0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
        0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
    ]
    private static let sigma: [[Int]] = [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
        [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
        [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
        [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
        [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
        [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
        [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
        [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
        [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
        [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
        [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
    ]

    private var h: [UInt64]
    private var t0: UInt64 = 0
    private var t1: UInt64 = 0
    private var buffer = [UInt8](repeating: 0, count: blockSize)
    private var filled = 0
    private var finished = false

    public init() {
        h = Self.iv
        h[0] ^= 0x0101_0040
    }

    public static func hash(_ data: Data) -> Data {
        var hasher = Blake2b()
        hasher.update(data)
        return hasher.finalize()
    }

    public mutating func update(_ data: Data) {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            update(base, count: raw.count)
        }
    }

    public mutating func update(_ bytes: UnsafePointer<UInt8>, count: Int) {
        var offset = 0
        while offset < count {
            if filled == Self.blockSize {
                t0 &+= UInt64(Self.blockSize)
                if t0 < UInt64(Self.blockSize) { t1 &+= 1 }
                compress(last: false)
                filled = 0
            }
            let space = Self.blockSize - filled
            let take = min(space, count - offset)
            buffer.withUnsafeMutableBufferPointer { dest in
                dest.baseAddress!.advanced(by: filled).update(from: bytes.advanced(by: offset), count: take)
            }
            filled += take
            offset += take
        }
    }

    public mutating func finalize() -> Data {
        if !finished {
            if filled == Self.blockSize {
                t0 &+= UInt64(Self.blockSize)
                if t0 < UInt64(Self.blockSize) { t1 &+= 1 }
                compress(last: false)
                filled = 0
                for index in 0..<Self.blockSize { buffer[index] = 0 }
            }
            t0 &+= UInt64(filled)
            if t0 < UInt64(filled) { t1 &+= 1 }
            for index in filled..<Self.blockSize { buffer[index] = 0 }
            compress(last: true)
            finished = true
        }
        var out = Data(count: 64)
        for index in 0..<8 {
            var word = h[index].littleEndian
            withUnsafeBytes(of: &word) { raw in
                out.replaceSubrange((index * 8)..<((index + 1) * 8), with: raw)
            }
        }
        return out
    }

    private mutating func compress(last: Bool) {
        var v = h + Self.iv
        v[12] ^= t0
        v[13] ^= t1
        if last { v[14] ^= ~UInt64(0) }
        var m = [UInt64](repeating: 0, count: 16)
        for index in 0..<16 {
            m[index] = load64(buffer, index * 8)
        }
        for round in 0..<12 {
            let s = Self.sigma[round]
            g(&v, 0, 4, 8, 12, m[s[0]], m[s[1]])
            g(&v, 1, 5, 9, 13, m[s[2]], m[s[3]])
            g(&v, 2, 6, 10, 14, m[s[4]], m[s[5]])
            g(&v, 3, 7, 11, 15, m[s[6]], m[s[7]])
            g(&v, 0, 5, 10, 15, m[s[8]], m[s[9]])
            g(&v, 1, 6, 11, 12, m[s[10]], m[s[11]])
            g(&v, 2, 7, 8, 13, m[s[12]], m[s[13]])
            g(&v, 3, 4, 9, 14, m[s[14]], m[s[15]])
        }
        for index in 0..<8 {
            h[index] ^= v[index] ^ v[index + 8]
        }
    }

    private func g(_ v: inout [UInt64], _ a: Int, _ b: Int, _ c: Int, _ d: Int, _ x: UInt64, _ y: UInt64) {
        v[a] = v[a] &+ v[b] &+ x
        v[d] = (v[d] ^ v[a]).rotateRight(32)
        v[c] = v[c] &+ v[d]
        v[b] = (v[b] ^ v[c]).rotateRight(24)
        v[a] = v[a] &+ v[b] &+ y
        v[d] = (v[d] ^ v[a]).rotateRight(16)
        v[c] = v[c] &+ v[d]
        v[b] = (v[b] ^ v[c]).rotateRight(63)
    }

    private func load64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for shift in 0..<8 {
            value |= UInt64(bytes[offset + shift]) << (shift * 8)
        }
        return value
    }
}

private extension UInt64 {
    func rotateRight(_ count: Int) -> UInt64 {
        (self >> count) | (self << (64 - count))
    }
}
