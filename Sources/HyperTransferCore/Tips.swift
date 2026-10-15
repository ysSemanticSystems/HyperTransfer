import Foundation

public enum Tips {
    public static let refresh = "Read Thunderbolt and the verbs device list again. It reads the live probe. A status of Up on the cable can hide a service that only carries IP until this refresh."
    public static let rdmaStatus = "RDMA status for this Mac. It reads Thunderbolt services and the verbs device list, including a Thunderbolt port in state 4. A green Up on the cable can hide that the file panes are still closed."
    public static let disk = "Free space on the home volume. It reads the volume that holds this home folder. Pressure here can hide a full disk on the peer, which this number does not see."
    public static let glossary = "Open a short description of Thunderbolt, RoCE, InfiniBand, and iWARP. It reads the text in this page, not the live ports. The live status above can hide a port that appears after this page was drawn, until you refresh."
    public static let localUp = "Go up one folder on this Mac. It reads the parent of the open folder. The parent listing can hide a file that arrived after the last refresh."
    public static let peerUp = "Go up one folder on the peer. It reads the parent of the open peer folder. The parent listing can hide a file that arrived after the last refresh."
    public static let hidden = "Show names that start with a dot. It reads this checkbox, not the disk. Hiding those names can hide a file a folder copy will still include."
    public static let open = "Open the selected folder, or view the selected file. It reads the selected row. A folder open can hide a change that happened after the listing was read."
    public static let view = "Show the first 4096 bytes of the selected file. It reads that window only. Bytes past the window can hide a difference the transfer hash would catch."
    public static let bridge = "Thunderbolt bridge path for the 64-byte queue-pair note. It reads network services, tunnel addresses, and replies on the Thunderbolt bridge. A VPN that still lets the bridge answer can hide a peer window that is not open, and a service name can hide a tunnel that is down."
    public static let landsIn = "Folder on the peer that will receive the copy. It reads the peer listing on screen. A path typed by hand can hide a folder this window has not shown, so the copy uses only this listing."
    public static let replace = "Replace a file already at the peer path after the three hashes match. It reads this checkbox. Until the hashes match, the previous file stays, so an early failure can hide that replace has not happened yet."
    public static let copyFile = "Copy the selected file over RDMA. It reads the fabric status and the selected name. A Thunderbolt link that is Up can hide that RDMA is unreachable and this button will not send the file."
    public static let copyFolder = "Copy the selected folder over RDMA, one regular file at a time. It reads the fabric status and the folder listing. A hidden dotfile can hide from the list and still be included, and a symlink is skipped."
    public static let copyReceipt = "Copy the receipt text. It reads the three digests, the times, and the verdict on this page. A grouped hash can hide a mismatch the continuous text still has."

    public static let all: [String] = [
        refresh, rdmaStatus, bridge, disk, glossary, localUp, peerUp, hidden, open, view,
        landsIn, replace, copyFile, copyFolder, copyReceipt,
    ]

    public static func row(_ name: String, kind: String, leavesRoot: Bool) -> String {
        var sentence = "Select \(name) (\(kind)). It reads the directory entry, not the file bytes. A listing can hide a change that happens after this refresh."
        if leavesRoot {
            sentence += " This link leaves the root and will not be opened."
        }
        return sentence
    }

    public static func port(_ port: PortReport) -> String {
        "\(port.word) for \(port.name). It reads the probe for this port. \(port.detail) A cable that reads Up can hide a service that is not RDMA."
    }

    public static func hashField(_ label: String) -> String {
        "The full SHA-512 and BLAKE2b for \(label). It reads the digests for this pass. Selecting a grouped display can hide a group, and this field is the continuous hex."
    }
}

public enum CopyGate {
    public static func refusal(fabric: FabricReport?) -> String {
        guard let fabric else {
            return "The probe has not answered. Nothing is treated as RDMA."
        }
        if !fabric.rdmaActive {
            return fabric.summary
        }
        return "RDMA is up and no queue pair is connected. The copy stays closed."
    }

    public static func canBrowse(_ fabric: FabricReport?) -> Bool {
        fabric?.rdmaActive == true
    }
}
