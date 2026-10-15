import AppKit
import HyperTransferCore
import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var showHidden = false
    @State private var replace = false
    @State private var destination = ""
    @State private var fabricOpen = false
    @State private var glossaryOpen = false
    @State private var hovered: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            hairline
            panes
            if previewIsOpen {
                hairline
                previewDrawer
            }
            hairline
            copyBar
            hairline
            statusBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
        .preferredColorScheme(.dark)
        .task { await model.refresh() }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button("Open") { Task { await model.openSelected() } }
                .buttonStyle(ToolbarButtonStyle())
                .help(Tips.open)
                .accessibilityHint(Tips.open)
                .keyboardShortcut("o", modifiers: .command)
            Button("View") { Task { await model.viewSelected() } }
                .buttonStyle(ToolbarButtonStyle())
                .help(Tips.view)
                .accessibilityHint(Tips.view)
            Toggle("Show hidden names", isOn: $showHidden)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .help(Tips.hidden)
                .accessibilityHint(Tips.hidden)
            Spacer(minLength: 12)
            fabricButton
            diskStatus
            Button("Refresh") { Task { await model.refresh() } }
                .buttonStyle(ToolbarButtonStyle())
                .help(Tips.refresh)
                .accessibilityHint(Tips.refresh)
                .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Palette.panel)
    }

    private var panes: some View {
        HStack(spacing: 0) {
            browser("This Mac", tip: Tips.localUp)
            Rectangle().fill(Palette.line).frame(width: 1)
            browser("Peer", tip: Tips.peerUp)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func browser(_ title: String, tip: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(pathLine(title))
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button("Up") { Task { await model.goUp() } }
                    .buttonStyle(ToolbarButtonStyle())
                    .help(tip)
                    .accessibilityHint(tip)
                    .accessibilityLabel("Up, \(title)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Palette.panel)
            hairline
            if title == "This Mac", let listing = model.listing {
                let rows = listing.entries.filter { showHidden || !$0.hidden }
                columnHeader
                hairline
                if rows.isEmpty {
                    emptyState("No names to show.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { entry in
                                fileRow(entry)
                            }
                        }
                    }
                }
            } else {
                emptyState(emptyMessage(title))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }

    private var columnHeader: some View {
        fileLine(symbol: nil, name: "Name", date: "Date Modified", size: "Size", kind: "Kind", header: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Palette.panel)
    }

    private func fileRow(_ entry: DirectoryEntry) -> some View {
        let selected = model.selected?.relative == entry.relative
        let hot = hovered == entry.relative
        return Button {
            model.selected = entry
        } label: {
            fileLine(
                symbol: symbolName(entry.kind),
                name: entry.name,
                date: dateText(entry.modified),
                size: sizeText(entry.size),
                kind: kindWord(entry.kind),
                header: false
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .background(rowFill(selected: selected, hot: hot))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Tips.row(entry.name, kind: entry.kind, leavesRoot: entry.leavesRoot))
        .accessibilityHint(Tips.row(entry.name, kind: entry.kind, leavesRoot: entry.leavesRoot))
        .accessibilityLabel(entry.name)
        .accessibilityValue(selected ? "Selected" : entry.kind)
        .onHover { hovering in
            hovered = hovering ? entry.relative : (hovered == entry.relative ? nil : hovered)
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            model.selected = entry
            Task { await model.openSelected() }
        })
    }

    private func fileLine(symbol: String?, name: String, date: String, size: String, kind: String, header: Bool) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(symbol == "folder.fill" ? Palette.brass : Palette.muted)
                        .frame(width: 16)
                }
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(date)
                .lineLimit(1)
                .frame(width: 148, alignment: .leading)
            Text(size)
                .lineLimit(1)
                .frame(width: 72, alignment: .trailing)
            Text(kind)
                .lineLimit(1)
                .frame(width: 64, alignment: .leading)
        }
        .font(.system(size: header ? 11 : 13, weight: header ? .semibold : .regular))
        .foregroundStyle(header ? Palette.muted : Palette.text)
    }

    private var previewDrawer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.previewNote)
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
                .lineLimit(2)
            ScrollView {
                Text(model.previewBody.isEmpty ? " " : model.previewBody)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(height: 96)
            .accessibilityLabel("First bytes of the selected file. This window is not the transfer hash.")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.inset)
    }

    private var copyBar: some View {
        HStack(spacing: 10) {
            Text("Peer path")
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
            TextField("Same path on the peer", text: $destination)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 8)
                .frame(minHeight: 26)
                .background(Palette.inset, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.line))
                .help(Tips.destination)
                .accessibilityHint(Tips.destination)
                .accessibilityLabel("Peer path")
            Toggle("Replace after a match", isOn: $replace)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .help(Tips.replace)
                .accessibilityHint(Tips.replace)
            Button("Copy file") { model.attemptCopy() }
                .buttonStyle(ToolbarButtonStyle(prominent: true))
                .help(Tips.copyFile)
                .accessibilityHint(Tips.copyFile)
            Button("Copy folder") { model.attemptCopy() }
                .buttonStyle(ToolbarButtonStyle(prominent: true))
                .help(Tips.copyFolder)
                .accessibilityHint(Tips.copyFolder)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Palette.panel)
    }

    private var statusBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if statusText != model.receiptLine {
                    Text(statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(2)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Text(model.receiptLine)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Copy receipt") {
                if model.receiptLine == "No copy has finished in this window." {
                    model.announcement = model.receiptLine
                } else {
                    copyToPasteboard(model.receiptLine)
                    model.announcement = "Receipt copied."
                }
            }
            .buttonStyle(ToolbarButtonStyle())
            .help(Tips.copyReceipt)
            .accessibilityHint(Tips.copyReceipt)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Palette.panel)
    }

    private var fabricButton: some View {
        Button {
            fabricOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                wordCapsule(model.fabric?.rdmaWord ?? "Place", tone: model.fabric?.rdmaTone ?? .place)
                Text("RDMA")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.text)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.muted)
            }
        }
        .buttonStyle(.plain)
        .help(Tips.rdmaStatus)
        .accessibilityHint(Tips.rdmaStatus)
        .accessibilityLabel("RDMA \(model.fabric?.rdmaWord ?? "Place")")
        .popover(isPresented: $fabricOpen, arrowEdge: .top) {
            fabricPopover
        }
    }

    private var diskStatus: some View {
        HStack(spacing: 6) {
            wordCapsule(model.fabric?.disk.word ?? "Place", tone: model.fabric?.disk.tone ?? .place)
            Text("Disk")
                .font(.system(size: 12))
                .foregroundStyle(Palette.text)
        }
        .help(diskTip)
        .accessibilityHint(diskTip)
        .accessibilityLabel("Home disk \(model.fabric?.disk.word ?? "Place")")
    }

    private var fabricPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.fabric?.summary ?? "Reading the fabric.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let fabric = model.fabric {
                    ForEach(Array(fabric.ports.enumerated()), id: \.offset) { _, port in
                        portRow(port)
                    }
                }
                DisclosureGroup(isExpanded: $glossaryOpen) {
                    VStack(alignment: .leading, spacing: 8) {
                        glossary("Thunderbolt.", "A cable can be up and still only speak Internet Protocol. That service is a fast kernel path. It is not RDMA, so this window leaves it unused. An unrecognized protocol on the same cable is left unused too.")
                        glossary("RoCE.", "RDMA over Ethernet. The port has to be ACTIVE. On a lossy network the link can still deliver the bytes by retrying, and that cost shows up as time, not as a failed hash.")
                        glossary("InfiniBand.", "Native RDMA. A port that is not ACTIVE often means the cable or the subnet manager is missing. Down stays down until that port says ACTIVE.")
                        glossary("iWARP.", "RDMA mapped onto TCP. The connection rides TCP. Once the queue pair is up, the file writes are still RDMA. EFA is RDMA as well, and it is not labeled RoCE.")
                    }
                    .padding(.top, 6)
                } label: {
                    Text("Transports this window understands")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                }
                .help(Tips.glossary)
                .accessibilityHint(Tips.glossary)
            }
            .padding(16)
        }
        .frame(minWidth: 420, maxWidth: 420, maxHeight: 380)
        .background(Palette.background)
    }

    private var hairline: some View {
        Rectangle().fill(Palette.line).frame(height: 1)
    }

    private var previewIsOpen: Bool {
        !model.previewNote.hasPrefix("No file is open.")
    }

    private var statusText: String {
        if !model.announcement.isEmpty { return model.announcement }
        guard let listing = model.listing else { return "Closed" }
        let shown = listing.entries.filter { showHidden || !$0.hidden }.count
        return shown == 1 ? "1 item" : "\(shown) items"
    }

    private var diskTip: String {
        if let detail = model.fabric?.disk.detail {
            return "Home disk is \(model.fabric?.disk.word ?? "Place"). It reads the home volume. \(detail) Pressure here can hide a full disk on the peer."
        }
        return Tips.disk
    }

    private func pathLine(_ title: String) -> String {
        if title == "Peer" {
            return CopyGate.canBrowse(model.fabric) ? "No queue pair" : "Closed"
        }
        if model.listing == nil { return "Closed" }
        return model.listingDetail
    }

    private func emptyMessage(_ title: String) -> String {
        if title == "Peer", CopyGate.canBrowse(model.fabric) {
            return CopyGate.refusal(fabric: model.fabric)
        }
        if title == "This Mac", model.listing == nil {
            return model.fabric?.summary ?? "Reading the fabric."
        }
        return "Closed"
    }

    private func emptyState(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rowFill(selected: Bool, hot: Bool) -> Color {
        if selected { return Palette.brass.opacity(0.34) }
        if hot { return Color.white.opacity(0.05) }
        return Color.clear
    }

    private func wordCapsule(_ word: String, tone: StatusTone) -> some View {
        Text(word)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Palette.ink(tone))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Palette.fill(tone), in: Capsule())
    }

    private func portRow(_ port: PortReport) -> some View {
        HStack(alignment: .top, spacing: 8) {
            wordCapsule(port.word, tone: port.tone)
                .help(Tips.port(port))
                .accessibilityHint(Tips.port(port))
                .accessibilityLabel("\(port.name) \(port.word)")
            VStack(alignment: .leading, spacing: 2) {
                Text("\(port.name) · \(port.transport)")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                Text(port.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func glossary(_ title: String, _ body: String) -> some View {
        Text("\(title) \(body)")
            .font(.system(size: 12))
            .foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func symbolName(_ kind: String) -> String {
        switch kind {
        case "folder": "folder.fill"
        case "link": "link"
        default: "doc"
        }
    }

    private func kindWord(_ kind: String) -> String {
        switch kind {
        case "folder": "Folder"
        case "file": "File"
        case "partial": "Partial"
        case "link": "Link"
        default: "Other"
        }
    }

    private func dateText(_ raw: String?) -> String {
        guard let raw, let date = ColumnFormat.parser.date(from: raw) else { return "—" }
        return ColumnFormat.display.string(from: date)
    }

    private func sizeText(_ bytes: Int?) -> String {
        guard let bytes else { return "—" }
        return ColumnFormat.bytes.string(fromByteCount: Int64(bytes))
    }

    private func copyToPasteboard(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }
}

@MainActor
private enum ColumnFormat {
    static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

private enum Palette {
    static let background = Color(red: 0.078, green: 0.086, blue: 0.110)
    static let panel = Color(red: 0.110, green: 0.122, blue: 0.153)
    static let inset = Color(red: 0.063, green: 0.071, blue: 0.094)
    static let line = Color(red: 0.204, green: 0.220, blue: 0.267)
    static let muted = Color(red: 0.788, green: 0.761, blue: 0.706)
    static let text = Color(red: 0.953, green: 0.937, blue: 0.894)
    static let brass = Color(red: 0.769, green: 0.647, blue: 0.455)
    static let onBrass = Color(red: 0.102, green: 0.078, blue: 0.047)

    static func fill(_ tone: StatusTone) -> Color {
        switch tone {
        case .up: Color(red: 0.490, green: 0.808, blue: 0.627)
        case .reachable: Color(red: 0.494, green: 0.804, blue: 0.784)
        case .down: Color(red: 0.941, green: 0.659, blue: 0.635)
        case .unreachable: Color(red: 0.941, green: 0.769, blue: 0.541)
        case .place: Color(red: 0.788, green: 0.808, blue: 0.847)
        }
    }

    static func ink(_ tone: StatusTone) -> Color {
        switch tone {
        case .up: Color(red: 0.063, green: 0.133, blue: 0.086)
        case .reachable: Color(red: 0.055, green: 0.141, blue: 0.141)
        case .down: Color(red: 0.239, green: 0.071, blue: 0.063)
        case .unreachable: Color(red: 0.227, green: 0.141, blue: 0.047)
        case .place: Color(red: 0.110, green: 0.125, blue: 0.157)
        }
    }
}

private struct ToolbarButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: prominent ? .semibold : .medium))
            .foregroundStyle(prominent ? Palette.onBrass : Palette.text)
            .padding(.horizontal, 10)
            .frame(minHeight: 26)
            .background(
                prominent
                    ? Palette.brass.opacity(configuration.isPressed ? 0.75 : 1)
                    : Color.white.opacity(configuration.isPressed ? 0.1 : 0.05),
                in: RoundedRectangle(cornerRadius: 6)
            )
    }
}
