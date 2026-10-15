import AppKit
import HyperTransferCore
import SwiftUI

@main
struct HyperTransferApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        if claimSingleProcess() != 0 {
            let me = ProcessInfo.processInfo.processIdentifier
            let others = NSWorkspace.shared.runningApplications.filter {
                $0.processIdentifier != me && $0.executableURL?.lastPathComponent == "HyperTransfer"
            }
            others.first?.activate(options: [.activateAllWindows])
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 960, minHeight: 540)
        }
        .defaultSize(width: 1120, height: 720)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
        Task { @MainActor in
            Self.placeOnFrontScreen()
        }
    }

    @MainActor
    private static func placeOnFrontScreen() {
        let app = NSApplication.shared
        guard let window = app.windows.first(where: { $0.frame.width > 400 && $0.level == .normal }) else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = NSSize(width: min(1120, visible.width - 80), height: min(720, visible.height - 80))
        let frame = NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
        app.activate()
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var fabric: FabricReport?
    @Published var bridge: BridgeDiagnosis?
    @Published var announcement = ""
    @Published var receiptLine = "No copy has finished in this window."
    @Published var localPath = "."
    @Published var listing: DirectoryListing?
    @Published var listingDetail = "Reading the fabric."
    @Published var selected: DirectoryEntry?
    @Published var peerListing: DirectoryListing?
    @Published var peerPath = "."
    @Published var peerSelected: String?
    @Published var previewNote = "No file is open. The transfer hash covers the whole file. This view never does."
    @Published var previewBody = ""
    @Published var peerPhase = "Closed"

    private let localRoot = FileManager.default.homeDirectoryForCurrentUser
    private var peer: PeerService?
    private var peerDevice: String?

    func refresh() async {
        let probed = await Task.detached(priority: .userInitiated) {
            (probeMachine(), probeBridge())
        }.value
        fabric = probed.0
        bridge = probed.1
        selected = nil
        syncPeer(probed.0)
        if peer?.isReady != true {
            peerPhase = phaseOnScreen(phase: peerPhase, diagnosis: bridge)
        }
        await reload()
        if peer?.isReady == true, peer?.listsFolders == true {
            await loadPeer(relative: peerPath)
        }
    }

    private func syncPeer(_ report: FabricReport) {
        guard report.rdmaActive, let device = activeVerbsDevice(report) else {
            peer?.stop()
            peer = nil
            peerDevice = nil
            peerListing = nil
            peerPhase = phaseOnScreen(phase: "Closed", diagnosis: bridge)
            return
        }
        if device == peerDevice, peer?.isAlive == true { return }
        peer?.stop()
        let service = PeerService()
        service.onPhase = { [weak self] text in
            Task { @MainActor in
                guard let self else { return }
                self.peerPhase = phaseOnScreen(phase: text, diagnosis: self.bridge)
                if text.hasPrefix("Queue pair is up"), self.peerListing == nil {
                    if service.listsFolders {
                        await self.loadPeer(relative: self.peerPath)
                    } else {
                        self.peerListing = nil
                        self.peerPhase = olderPeerFolderSentence()
                    }
                }
            }
        }
        peer = service
        peerDevice = device
        peerListing = nil
        peerPhase = phaseOnScreen(phase: "Bringing the queue pair up on \(device).", diagnosis: bridge)
        service.start(device: device)
    }

    func reload() async {
        guard CopyGate.canBrowse(fabric) else {
            listing = nil
            listingDetail = fabric?.summary ?? "The probe has not answered. Nothing is treated as RDMA."
            return
        }
        let root = localRoot
        let path = localPath
        let result: Result<DirectoryListing, Error> = await Task.detached(priority: .userInitiated) {
            Result { try listDirectory(root: root, relative: path) }
        }.value
        switch result {
        case .success(let found):
            listing = found
            listingDetail = found.path == "." ? "Home" : found.path
        case .failure(let error):
            listing = nil
            listingDetail = (error as? TransferError)?.detail ?? "The folder did not open."
        }
    }

    func loadPeer(relative: String) async {
        guard let peer, peer.isReady else { return }
        if !peer.listsFolders {
            peerListing = nil
            peerPhase = olderPeerFolderSentence()
            return
        }
        let service = peer
        let result = await Task.detached(priority: .userInitiated) {
            service.listFolder(relative)
        }.value
        switch result {
        case .success(let found):
            peerListing = found
            peerPath = found.path
            peerSelected = nil
        case .failure(let error):
            announcement = error.detail
        }
    }

    func goPeerUp() async {
        guard let parent = peerListing?.parent else {
            announcement = "This folder is the top of the peer root. It reads the open peer path. A higher folder outside that root can hide files this window will not list."
            return
        }
        await loadPeer(relative: parent)
    }

    func openPeer(_ entry: DirectoryEntry) async {
        if entry.kind == "folder" {
            await loadPeer(relative: entry.relative)
            return
        }
        announcement = "\(entry.name) is on the peer. The copy reads a file selected on this Mac, and it lands in the folder on screen."
    }

    func goUp() async {
        guard let parent = listing?.parent else {
            announcement = "This folder is the top of the root. It reads the open path. A higher folder outside the root can hide files this window will not list."
            return
        }
        localPath = parent
        selected = nil
        await reload()
    }

    func openSelected() async {
        guard CopyGate.canBrowse(fabric) else {
            announcement = CopyGate.refusal(fabric: fabric)
            return
        }
        guard let selected else {
            announcement = "Select a row first. It reads the listing. A closed pane can hide that RDMA is still unreachable."
            return
        }
        if selected.kind == "folder" {
            localPath = selected.relative
            self.selected = nil
            await reload()
            return
        }
        if selected.kind == "file" || selected.kind == "partial" {
            await viewSelected()
            return
        }
        announcement = "That row is \(selected.kind). Links and other entries are listed and not opened."
    }

    func viewSelected() async {
        guard CopyGate.canBrowse(fabric) else {
            announcement = CopyGate.refusal(fabric: fabric)
            return
        }
        guard let selected else {
            announcement = "View reads a file. Select a file first."
            return
        }
        guard selected.kind == "file" || selected.kind == "partial" else {
            announcement = "View reads a file. The selection is \(selected.kind)."
            return
        }
        let root = localRoot
        let relative = selected.relative
        let result: Result<FilePreview, Error> = await Task.detached(priority: .userInitiated) {
            Result { try previewFile(root: root, relative: relative) }
        }.value
        switch result {
        case .success(let viewed):
            previewBody = viewed.body
            let kind = viewed.kind == "hex" ? "Hex, because these bytes are not UTF-8 text." : "Text."
            let tail = viewed.truncated ? " The file continues past this window." : " This is the whole file."
            previewNote = "\(kind) Showing \(viewed.windowBytes) bytes of \(viewed.fileBytes).\(tail) The transfer hash covers the whole file. This view does not."
        case .failure(let error):
            previewBody = ""
            previewNote = (error as? TransferError)?.detail ?? "The file did not open."
        }
    }

    func attemptCopy(folder: Bool, replace: Bool) {
        guard CopyGate.canBrowse(fabric) else {
            receiptLine = CopyGate.refusal(fabric: fabric)
            return
        }
        guard let peer, peer.isReady else {
            receiptLine = bridge?.sentence ?? "RDMA is up and no queue pair is connected. The copy stays closed."
            return
        }
        guard let selected else {
            receiptLine = "Select a row first."
            return
        }
        let sourceName = (selected.relative as NSString).lastPathComponent
        if let block = landingBlock(
            listing: peerListing, sourceName: sourceName, sourceIsFolder: folder, replace: replace
        ) {
            receiptLine = block
            return
        }
        guard let peerListing else {
            receiptLine = "The peer folder is not on screen. The copy stays closed until this window lists where the file will land."
            return
        }
        let service = peer
        let root = localRoot
        let chosen = selected.relative
        let kind = selected.kind
        let folderPath = peerListing.path
        Task.detached {
            let line = copySelection(
                folder: folder, kind: kind, chosen: chosen, peerFolder: folderPath,
                replace: replace, root: root, service: service
            )
            await MainActor.run { self.receiptLine = line }
        }
    }
}

private func copySelection(
    folder: Bool,
    kind: String,
    chosen: String,
    peerFolder: String,
    replace: Bool,
    root: URL,
    service: PeerService
) -> String {
    if folder {
        guard kind == "folder" else { return "Select a folder. The selection is \(kind)." }
        let folderName = (chosen as NSString).lastPathComponent
        let prefix = landingRelative(peerFolder: peerFolder, name: folderName)
        do {
            let files = try filesInside(root: root, relative: chosen)
            if files.isEmpty { return "The folder has no regular files." }
            var lines: [String] = []
            for file in files {
                let source = try resolveInside(root: root, relative: file)
                let inside = String(file.dropFirst(chosen.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let relative = inside.isEmpty ? prefix : prefix + "/" + inside
                lines.append(service.copyFile(source: source, relative: relative, replace: replace).summary)
            }
            return lines.joined(separator: " ")
        } catch let error as TransferError {
            return error.detail
        } catch {
            return "The folder copy did not start."
        }
    }
    guard kind == "file" || kind == "partial" else { return "Select a file. The selection is \(kind)." }
    do {
        let source = try resolveInside(root: root, relative: chosen)
        let name = (chosen as NSString).lastPathComponent
        let relative = landingRelative(peerFolder: peerFolder, name: name)
        return service.copyFile(source: source, relative: relative, replace: replace).summary
    } catch let error as TransferError {
        return error.detail
    } catch {
        return "The copy did not start."
    }
}

private func filesInside(root: URL, relative: String) throws -> [String] {
    var found: [String] = []
    func walk(_ path: String) throws {
        let listing = try listDirectory(root: root, relative: path)
        for entry in listing.entries where entry.kind == "folder" {
            try walk(entry.relative)
        }
        for entry in listing.entries where entry.kind == "file" {
            found.append(entry.relative)
        }
    }
    try walk(relative)
    return found
}
