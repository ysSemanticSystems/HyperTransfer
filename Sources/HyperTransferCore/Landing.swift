import Foundation

public func landingRelative(peerFolder: String, name: String) -> String {
    if peerFolder.isEmpty || peerFolder == "." { return name }
    return peerFolder + "/" + name
}

public func olderPeerFolderSentence() -> String {
    "The other window can receive a file, and it cannot show its folder. The copy stays closed until that folder is on screen."
}

public func landingBlock(listing: DirectoryListing?, sourceName: String, sourceIsFolder: Bool, replace: Bool) -> String? {
    guard let listing else {
        return "The peer folder is not on screen. The copy stays closed until this window lists where the file will land."
    }
    if sourceName.isEmpty || sourceName == "." || sourceName == ".." || sourceName.contains("/") {
        return "The copy name is not a single file name. The copy stays closed."
    }
    let existing = listing.entries.first {
        $0.name.compare(sourceName, options: .caseInsensitive) == .orderedSame
    }
    if existing == nil, listing.truncated {
        return "The peer list stopped early. \(sourceName) is not among the names on screen, so a file already there can stay hidden. The copy stays closed."
    }
    guard let existing else { return nil }
    let shown = existing.name
    if existing.kind == "link" || existing.leavesRoot {
        return "\(shown) is a link in the peer listing. The copy stays closed."
    }
    if existing.kind == "folder" {
        if sourceIsFolder {
            return "\(shown) is already a folder on the peer. Open it before copying, so the names inside are on screen."
        }
        return "\(shown) is a folder in the peer listing. The copy stays closed."
    }
    if sourceIsFolder {
        return "\(shown) is a file in the peer listing. The folder copy stays closed."
    }
    if existing.kind == "file" || existing.kind == "partial" {
        if replace { return nil }
        return "\(shown) is already in this peer folder. It stays until Replace after a match is on, and the three hashes agree."
    }
    return "\(shown) is \(existing.kind) in the peer listing. The copy stays closed."
}
