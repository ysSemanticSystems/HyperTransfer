import Foundation
import HyperTransferVerbs

public final class PeerService: @unchecked Sendable {
    public var onPhase: (@Sendable (String) -> Void)?

    private let lock = NSLock()
    private var phaseText = "Bringing the queue pair up."
    private var ready = false
    private var stopped = false
    private var running = false
    private var pending: Pending?
    private var listWait: ListJob?
    public private(set) var listsFolders = false
    private let queue = DispatchQueue(label: "hypertransfer.peer")
    private static let gate = NSLock()
    nonisolated(unsafe) private static var portAttempted = false

    public init() {}

    public var phase: String {
        lock.lock()
        defer { lock.unlock() }
        return phaseText
    }

    public var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ready
    }

    public var isAlive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    public func start(device: String) {
        lock.lock()
        stopped = false
        running = true
        lock.unlock()
        queue.async { [weak self] in
            self?.run(device: device)
        }
    }

    public func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    public func copyFile(source: URL, relative: String, replace: Bool) -> Receipt {
        lock.lock()
        if !ready {
            lock.unlock()
            return closed("RDMA is up and no queue pair is connected. The copy stays closed.", source, relative)
        }
        if pending != nil {
            lock.unlock()
            return closed("A copy is already moving on this queue pair.", source, relative)
        }
        let box = Pending(source: source, relative: relative, replace: replace)
        pending = box
        lock.unlock()
        box.semaphore.wait()
        return box.receipt ?? closed("The copy did not finish.", source, relative)
    }

    public func listFolder(_ relative: String) -> Result<DirectoryListing, TransferError> {
        lock.lock()
        if !ready {
            lock.unlock()
            return .failure(TransferError(.ioError, "RDMA is up and no queue pair is connected. The peer folder stays closed."))
        }
        if !listsFolders {
            lock.unlock()
            return .failure(TransferError(.refused, olderPeerFolderSentence()))
        }
        if listWait != nil {
            lock.unlock()
            return .failure(TransferError(.ioError, "A folder list is already in progress."))
        }
        let job = ListJob(relative: relative)
        listWait = job
        lock.unlock()
        job.semaphore.wait()
        if let listing = job.listing { return .success(listing) }
        return .failure(TransferError(.ioError, job.detail ?? "The peer folder did not list."))
    }

    private func run(device: String) {
        defer {
            lock.lock()
            running = false
            ready = false
            listsFolders = false
            lock.unlock()
        }
        var session = openOnce(device)
        if session == nil || isStopped { return }
        defer { if let session { ht_close(session) } }
        publish("Waiting for the peer window on the Thunderbolt bridge.")
        while !isStopped {
            guard let open = session else { return }
            let rc = ht_exchange(open, 1000)
            if rc == 0 { break }
            let detail = String(cString: ht_last_error(open))
            switch exchangeStep(rc: rc, detail: detail) {
            case .connected:
                break
            case .waiting:
                if phase.contains("tried again") {
                    publish("Waiting for the peer window on the Thunderbolt bridge.")
                }
                continue
            case .retry(let sentence):
                publish(sentence)
                Thread.sleep(forTimeInterval: 1)
            case .reopen(let sentence):
                publish("\(sentence) This window will not open the port again.")
                ht_close(open)
                session = nil
                return
            }
        }
        if isStopped { return }
        guard let readySession = session else { return }
        let link = VerbsLink(session: readySession)
        markReady(device, lists: ht_peer_lists(readySession) != 0)
        while !isStopped {
            if let job = takePending() {
                publish("Copying \(job.relative).")
                job.receipt = sendFile(link: link, source: job.source, relative: job.relative, replace: job.replace)
                publish("Queue pair is up on \(device).")
                job.semaphore.signal()
                continue
            }
            if let job = takeList() {
                do {
                    job.listing = try requestPeerList(link: link, relative: job.relative)
                } catch let error as TransferError {
                    job.detail = error.detail
                } catch {
                    job.detail = "The peer folder did not list."
                }
                job.semaphore.signal()
                continue
            }
            do {
                guard let header = try link.recvFrame(fileHeaderLength, timeout: 200) else { continue }
                let summary = try servePeerHeader(link: link, root: FileManager.default.homeDirectoryForCurrentUser, header: header)
                if summary != "Listed a folder." { publish(summary) }
            } catch {
                publish((error as? TransferError)?.detail ?? "The receive stopped.")
            }
        }
    }

    private func openOnce(_ device: String) -> OpaquePointer? {
        let box = OpenBox()
        let done = DispatchSemaphore(value: 0)
        Self.gate.lock()
        if Self.portAttempted {
            Self.gate.unlock()
            publish("This window will not open the port again.")
            return nil
        }
        Self.portAttempted = true
        Self.gate.unlock()
        DispatchQueue.global(qos: .userInitiated).async {
            box.session = device.withCString { ht_open($0) }
            done.signal()
        }
        if done.wait(timeout: .now() + 8) == .timedOut {
            publish("The Thunderbolt port is not answering. This window will not open it again.")
            return nil
        }
        guard let session = box.session else {
            publish(String(cString: ht_last_error(nil)))
            return nil
        }
        return session
    }

    private func markReady(_ device: String, lists: Bool) {
        lock.lock()
        ready = true
        listsFolders = lists
        lock.unlock()
        publish("Queue pair is up on \(device).")
    }

    private func takeList() -> ListJob? {
        lock.lock()
        defer { lock.unlock() }
        let job = listWait
        listWait = nil
        return job
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    private func takePending() -> Pending? {
        lock.lock()
        defer { lock.unlock() }
        let job = pending
        pending = nil
        return job
    }

    private func publish(_ text: String) {
        lock.lock()
        phaseText = text
        lock.unlock()
        onPhase?(text)
    }

    private func closed(_ summary: String, _ source: URL, _ relative: String) -> Receipt {
        Receipt(
            source: source.path, destination: relative, promoted: false, code: .ioError,
            word: "Down", tone: .down, summary: summary, before: nil, destinationHash: nil,
            after: nil, byteCount: 0, transferSeconds: 0, hashBeforeSeconds: 0,
            hashDestinationSeconds: 0, hashAfterSeconds: 0, rateBytesPerSecond: nil,
            sampleShort: false, sync: "", metadataLeftBehind: [], inodeChanged: false,
            partial: nil, osStamps: [], sent: nil
        )
    }
}

private final class OpenBox: @unchecked Sendable {
    var session: OpaquePointer?
}

private final class ListJob {
    let relative: String
    let semaphore = DispatchSemaphore(value: 0)
    var listing: DirectoryListing?
    var detail: String?
    init(relative: String) { self.relative = relative }
}

private final class Pending {
    let source: URL
    let relative: String
    let replace: Bool
    let semaphore = DispatchSemaphore(value: 0)
    var receipt: Receipt?
    init(source: URL, relative: String, replace: Bool) {
        self.source = source
        self.relative = relative
        self.replace = replace
    }
}

private final class VerbsLink: FrameLink {
    let session: OpaquePointer

    init(session: OpaquePointer) {
        self.session = session
    }

    func sendFrame(_ data: Data) throws {
        let rc = data.withUnsafeBytes { raw in
            ht_send(session, raw.baseAddress, UInt32(data.count))
        }
        if rc != 0 {
            throw TransferError(.ioError, String(cString: ht_last_error(session)))
        }
    }

    func recvFrame(_ count: Int) throws -> Data {
        guard let data = try recvFrame(count, timeout: -1) else {
            throw TransferError(.ioError, "The queue pair wait ended.")
        }
        return data
    }

    func recvFrame(_ count: Int, timeout: Int32) throws -> Data? {
        var data = Data(count: count)
        let rc: Int32 = data.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            guard let base = raw.baseAddress else { return -1 }
            return ht_recv(session, base, UInt32(count), timeout)
        }
        if rc == 1 { return nil }
        if rc != 0 {
            throw TransferError(.ioError, String(cString: ht_last_error(session)))
        }
        return data
    }
}

public func claimSingleProcess() -> Int32 { ht_claim_single() }

public func singleProcessIsHeld() -> Int32 { ht_single_is_held() }

public func routeGIDIsIPv4Mapped(_ raw: [UInt8]) -> Bool {
    guard raw.count == 16 else { return false }
    return raw.withUnsafeBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return false }
        return ht_gid_is_ipv4_mapped(base) != 0
    }
}

public func thunderboltWireLength(_ length: UInt32) -> UInt32 {
    ht_wire_len(length)
}

public func queuePairRecordAccepted(_ bytes: Data) -> Bool {
    bytes.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return false }
        return ht_setup_record_ok(base, UInt32(bytes.count)) != 0
    }
}

public func verbsQueuePairOpens(device: String) -> Bool {
    guard let session = device.withCString({ ht_open($0) }) else { return false }
    ht_close(session)
    return true
}
