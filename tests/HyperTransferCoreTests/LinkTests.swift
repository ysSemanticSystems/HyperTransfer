import Foundation
@testable import HyperTransferCore

final class LinkTests {
    func testVpnOnTheDefaultRouteIsNamedWhenNoPeerAnswers() {
        let diagnosis = diagnoseBridge(bridgeFacts(
            services: ["Ethernet", "Wi-Fi", "Thunderbolt Bridge", "ProtonVPN", "Tailscale"],
            tunnels: [TunnelFact(name: "utun3", address: "10.2.0.2")],
            route: "utun3",
            responders: ["fe80::self"]
        ))
        XCTAssertEqual(diagnosis.word, "Unreachable")
        XCTAssertEqual(diagnosis.tone, .unreachable)
        XCTAssertTrue(diagnosis.sentence.contains("ProtonVPN and Tailscale are up"))
        XCTAssertTrue(diagnosis.sentence.contains("utun3 owns the default route"))
        XCTAssertTrue(diagnosis.sentence.contains("not sent through the VPN"))
        XCTAssertFalse(diagnosis.peerSeen)
    }

    func testVpnWithoutTheDefaultRouteIsNamedWhenNoPeerAnswers() {
        let diagnosis = diagnoseBridge(bridgeFacts(
            services: ["Thunderbolt Bridge", "Tailscale"],
            tunnels: [TunnelFact(name: "utun4", address: "100.64.0.1")],
            route: "en0"
        ))
        XCTAssertEqual(diagnosis.word, "Unreachable")
        XCTAssertTrue(diagnosis.sentence.contains("Tailscale is up"))
        XCTAssertTrue(diagnosis.sentence.contains("verbs port stays up"))
        XCTAssertFalse(diagnosis.sentence.contains("default route"))
        XCTAssertTrue(diagnosis.sentence.contains("file stays on this Mac"))
    }

    func testVpnIsNamedWhenTheBridgeStillAnswers() {
        let diagnosis = diagnoseBridge(bridgeFacts(
            services: ["Thunderbolt Bridge", "ProtonVPN"],
            tunnels: [TunnelFact(name: "utun3", address: "10.2.0.2")],
            route: "utun3",
            responders: ["fe80::self", "fe80::peer"]
        ))
        XCTAssertEqual(diagnosis.word, "Reachable")
        XCTAssertEqual(diagnosis.tone, .reachable)
        XCTAssertTrue(diagnosis.peerSeen)
        XCTAssertTrue(diagnosis.sentence.contains("ProtonVPN is up"))
        XCTAssertTrue(diagnosis.sentence.contains("not the VPN"))
    }

    func testNoPeerWithoutAVpnSaysTheNoteIsStillBeingSent() {
        let diagnosis = diagnoseBridge(bridgeFacts(responders: ["fe80::self%bridge0"]))
        XCTAssertEqual(diagnosis.word, "Unreachable")
        XCTAssertTrue(diagnosis.vpnNames.isEmpty)
        XCTAssertTrue(diagnosis.sentence.contains("still being sent"))
        XCTAssertTrue(diagnosis.sentence.contains("until a peer window answers"))
    }

    func testPeerAnswerWithoutAVpnIsUp() {
        let diagnosis = diagnoseBridge(bridgeFacts(responders: ["fe80::peer"]))
        XCTAssertEqual(diagnosis.word, "Up")
        XCTAssertEqual(diagnosis.tone, .up)
        XCTAssertTrue(diagnosis.peerSeen)
        XCTAssertTrue(diagnosis.bridgeReady)
        XCTAssertTrue(diagnosis.sentence.contains("Waiting for its HyperTransfer window"))
    }

    func testMissingThunderboltBridgeServiceIsDown() {
        let diagnosis = diagnoseBridge(bridgeFacts(
            services: ["Ethernet", "Wi-Fi", "ProtonVPN"],
            tunnels: [TunnelFact(name: "utun3", address: "10.2.0.2")]
        ))
        XCTAssertEqual(diagnosis.word, "Down")
        XCTAssertEqual(diagnosis.tone, .down)
        XCTAssertFalse(diagnosis.bridgeReady)
        XCTAssertTrue(diagnosis.sentence.contains("ProtonVPN is up"))
        XCTAssertTrue(diagnosis.sentence.contains("not a network service"))
        XCTAssertTrue(diagnosis.sentence.contains("file stays on this Mac"))
    }

    func testDisabledThunderboltBridgeServiceIsDown() {
        let diagnosis = diagnoseBridge(bridgeFacts(services: ["*Thunderbolt Bridge", "Ethernet"]))
        XCTAssertEqual(diagnosis.word, "Down")
        XCTAssertTrue(diagnosis.sentence.contains("Thunderbolt Bridge is disabled"))
    }

    func testBridgeInterfaceDownIsDown() {
        let diagnosis = diagnoseBridge(bridgeFacts(bridgeUp: false))
        XCTAssertEqual(diagnosis.word, "Down")
        XCTAssertTrue(diagnosis.sentence.contains("interface is down"))
    }

    func testMissingLinkLocalIsDown() {
        let diagnosis = diagnoseBridge(bridgeFacts(linkLocal: nil))
        XCTAssertEqual(diagnosis.word, "Down")
        XCTAssertTrue(diagnosis.sentence.contains("no IPv6 link-local"))
        XCTAssertFalse(diagnosis.sentence.contains("169.254"))
    }

    func testLinkLocalIPv4OnTheBridgeIsNotAPath() {
        let text = """
        bridge0: flags=8863<UP,BROADCAST,RUNNING,MULTICAST> mtu 1500
        \tinet 169.254.182.97 netmask 0xffff0000 broadcast 169.254.255.255
        \tstatus: active
        """
        let bridge = parseIfconfig(text).first { $0.name == "bridge0" }
        XCTAssertEqual(bridge?.linkLocals, [])
        XCTAssertEqual(bridge?.globals, [])
        XCTAssertEqual(bridge?.up, true)
        XCTAssertEqual(bridge?.inactive, false)
    }

    func testOwnPingReplyIsNotAnotherMac() {
        let diagnosis = diagnoseBridge(bridgeFacts(responders: ["fe80::self", "FE80::SELF"]))
        XCTAssertFalse(diagnosis.peerSeen)
        XCTAssertTrue(diagnosis.sentence.contains("No other Mac answered"))
    }

    func testUtunWithOnlyLinkLocalIsNotAVpn() {
        let text = """
        utun0: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1500
        \tinet6 fe80::1%utun0 prefixlen 64
        utun3: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1380
        \tinet 10.2.0.2 --> 10.2.0.2 netmask 0xffffffff
        en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
        \tinet 192.168.1.20 netmask 0xffffff00 broadcast 192.168.1.255
        """
        let found = tunnels(from: parseIfconfig(text))
        XCTAssertEqual(found.map(\.name), ["utun3"])
        XCTAssertFalse(isVpnServiceName("Ethernet"))
        XCTAssertFalse(isVpnServiceName("Wi-Fi"))
        XCTAssertFalse(isVpnServiceName("Thunderbolt Bridge"))
    }

    func testEnabledVpnServiceWithoutATunnelIsNotUp() {
        let diagnosis = diagnoseBridge(bridgeFacts(services: ["Thunderbolt Bridge", "ProtonVPN", "Tailscale"]))
        XCTAssertTrue(diagnosis.vpnNames.isEmpty)
        XCTAssertTrue(diagnosis.sentence.contains("No other Mac answered"))
        XCTAssertFalse(diagnosis.sentence.contains("ProtonVPN"))
    }

    func testDisabledVpnServiceWithALiveTunnelNamesTheInterface() {
        let diagnosis = diagnoseBridge(bridgeFacts(
            services: ["Thunderbolt Bridge", "*ProtonVPN"],
            tunnels: [TunnelFact(name: "utun8", address: "10.8.0.2")]
        ))
        XCTAssertEqual(diagnosis.vpnNames, ["utun8"])
        XCTAssertTrue(diagnosis.sentence.contains("utun8 is up"))
        XCTAssertFalse(diagnosis.sentence.contains("ProtonVPN"))
    }

    func testTailscaleAndProtonAreBothNamed() {
        let diagnosis = diagnoseBridge(bridgeFacts(
            services: ["Thunderbolt Bridge", "ProtonVPN", "Tailscale"],
            tunnels: [TunnelFact(name: "utun3", address: "10.2.0.2"), TunnelFact(name: "utun4", address: "100.64.0.1")]
        ))
        XCTAssertEqual(diagnosis.vpnNames, ["ProtonVPN", "Tailscale"])
    }

    func testDefaultRouteAloneNamesTheTunnel() {
        let diagnosis = diagnoseBridge(bridgeFacts(route: "utun5"))
        XCTAssertEqual(diagnosis.vpnNames, ["utun5"])
        XCTAssertTrue(diagnosis.sentence.contains("utun5 is up and owns the default route"))
        XCTAssertTrue(diagnosis.sentence.contains("not sent through the VPN"))
    }

    func testProbeFailureDoesNotInventAPeer() {
        let diagnosis = diagnoseBridge(bridgeFacts(responders: ["fe80::peer"], probeFailed: true))
        XCTAssertEqual(diagnosis.word, "Down")
        XCTAssertFalse(diagnosis.peerSeen)
        XCTAssertTrue(diagnosis.sentence.contains("probe did not finish"))
        XCTAssertFalse(diagnosis.sentence.contains("Another Mac answered"))
    }

    func testReplyProbeFailureDoesNotClaimSilence() {
        let diagnosis = diagnoseBridge(bridgeFacts(
            services: ["Thunderbolt Bridge", "ProtonVPN"],
            tunnels: [TunnelFact(name: "utun3", address: "10.2.0.2")],
            replyFailed: true
        ))
        XCTAssertEqual(diagnosis.word, "Unreachable")
        XCTAssertFalse(diagnosis.peerSeen)
        XCTAssertTrue(diagnosis.sentence.contains("ProtonVPN is up"))
        XCTAssertTrue(diagnosis.sentence.contains("reply probe did not finish"))
        XCTAssertFalse(diagnosis.sentence.contains("No other Mac answered"))
    }

    func testWaitingPhaseShowsTheVpnSentence() {
        let diagnosis = diagnoseBridge(bridgeFacts(
            services: ["Thunderbolt Bridge", "ProtonVPN"],
            tunnels: [TunnelFact(name: "utun3", address: "10.2.0.2")],
            route: "utun3"
        ))
        let shown = phaseOnScreen(phase: "Waiting for the peer window on the Thunderbolt bridge.", diagnosis: diagnosis)
        XCTAssertTrue(shown.contains("ProtonVPN"))
        XCTAssertTrue(shown.contains("not sent through the VPN"))
        XCTAssertFalse(shown.contains("Waiting for the peer window"))
    }

    func testBindFailureStaysOnScreen() {
        let diagnosis = diagnoseBridge(bridgeFacts())
        let phase = "The queue-pair record socket did not bind on the Thunderbolt bridge."
        XCTAssertEqual(phaseOnScreen(phase: phase, diagnosis: diagnosis), phase)
    }

    func testQueuePairUpKeepsItsPhase() {
        let diagnosis = diagnoseBridge(bridgeFacts(
            tunnels: [TunnelFact(name: "utun3", address: "10.2.0.2")]
        ))
        let phase = "Queue pair is up on rdma_en3."
        XCTAssertEqual(phaseOnScreen(phase: phase, diagnosis: diagnosis), phase)
    }

    func testParsersReadServicesInterfacesRouteAndPing() {
        let services = parseNetworkServices("""
        An asterisk (*) denotes that a network service is disabled.
        Ethernet
        *Thunderbolt Bridge
        ProtonVPN
        """)
        XCTAssertEqual(services.map(\.name), ["Ethernet", "Thunderbolt Bridge", "ProtonVPN"])
        XCTAssertEqual(services.map(\.enabled), [true, false, true])
        XCTAssertEqual(parseDefaultRoute("   route to: default\ninterface: utun3\n"), "utun3")
        XCTAssertEqual(parsePingResponders("16 bytes from fe80::abcd%bridge0, icmp_seq=0 hlim=64 time=0.1 ms\n16 bytes from fe80::abcd%bridge0, icmp_seq=1\n"), ["fe80::abcd"])
        let inactive = parseIfconfig("en2: flags=8863<UP,BROADCAST,RUNNING> mtu 1500\n\tstatus: inactive\n")
        XCTAssertEqual(inactive.first?.inactive, true)
        XCTAssertEqual(inactive.first?.up, true)
    }

    func testThisMacBridgeProbeReturnsAWord() {
        let diagnosis = probeBridge()
        XCTAssertTrue(["Up", "Reachable", "Unreachable", "Down"].contains(diagnosis.word))
        XCTAssertGreaterThan(diagnosis.sentence.count, 40)
        XCTAssertTrue(diagnosis.sentence.contains("Thunderbolt") || diagnosis.sentence.contains("bridge") || diagnosis.sentence.contains("VPN") || diagnosis.sentence.contains("probe"))
    }

    func testASecondProcessCannotOpenThePort() {
        XCTAssertEqual(claimSingleProcess(), 0)
        XCTAssertEqual(singleProcessIsHeld(), 1)
    }

    func testTheWindowClaimsTheProcessBeforeItProbes() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(contentsOf: root.appendingPathComponent("Sources/HyperTransfer/HyperTransferApp.swift"), encoding: .utf8)
        guard let claim = app.range(of: "claimSingleProcess()"),
              let probe = app.range(of: "probeMachine()") else {
            XCTAssertTrue(false, "the window does not claim the process")
            return
        }
        XCTAssertTrue(claim.lowerBound < probe.lowerBound)
        XCTAssertTrue(app.contains("exit(0)"))
        let join = try String(contentsOf: root.appendingPathComponent("Sources/HyperTransferJoin/main.swift"), encoding: .utf8)
        guard let claimJoin = join.range(of: "ht_claim_single()"),
              let openJoin = join.range(of: "ht_open") else {
            XCTAssertTrue(false, "the join tool does not claim the process")
            return
        }
        XCTAssertTrue(claimJoin.lowerBound < openJoin.lowerBound)
        let service = try String(contentsOf: root.appendingPathComponent("Sources/HyperTransferCore/PeerService.swift"), encoding: .utf8)
        XCTAssertTrue(service.contains("will not open it again"))
        XCTAssertTrue(service.contains("portAttempted"))
    }

    func testIPv4MappedGIDIsTheRoute() throws {
        var mapped = [UInt8](repeating: 0, count: 16)
        mapped[10] = 0xff
        mapped[11] = 0xff
        mapped[12] = 169
        mapped[13] = 254
        mapped[14] = 10
        mapped[15] = 1
        XCTAssertTrue(routeGIDIsIPv4Mapped(mapped))
        var linkLocal = [UInt8](repeating: 0, count: 16)
        linkLocal[0] = 0xfe
        linkLocal[1] = 0x80
        XCTAssertFalse(routeGIDIsIPv4Mapped(linkLocal))
        XCTAssertFalse(routeGIDIsIPv4Mapped([UInt8](repeating: 0, count: 16)))
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let verbs = try String(contentsOf: root.appendingPathComponent("Sources/HyperTransferVerbs/VerbsBridge.c"), encoding: .utf8)
        XCTAssertTrue(verbs.contains("ht_gid_is_ipv4_mapped"))
        XCTAssertTrue(verbs.contains("session->ipv4_mapped = 1"))
        XCTAssertFalse(verbs.contains("169.254"))
        XCTAssertFalse(verbs.contains("ifconfig"))
    }

    func testReadyTransitionIsRetriedOnTheSamePair() throws {
        let detail = "The queue pair reached the peer and was not made ready to receive"
        let sentence = introductionRetry(detail)
        XCTAssertEqual(exchangeStep(rc: 2, detail: detail), .retry(sentence))
        XCTAssertTrue(sentence.contains("tried again every second"))
        let diagnosis = diagnoseBridge(bridgeFacts())
        XCTAssertEqual(phaseOnScreen(phase: sentence, diagnosis: diagnosis), sentence)
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let verbs = try String(contentsOf: root.appendingPathComponent("Sources/HyperTransferVerbs/VerbsBridge.c"), encoding: .utf8)
        XCTAssertTrue(verbs.contains("restore_init"))
        XCTAssertTrue(verbs.contains("session->rts = 0"))
        XCTAssertTrue(verbs.contains(detail))
        XCTAssertTrue(verbs.contains("meet_peer"))
        XCTAssertTrue(verbs.contains("session->qp->qp_num > peer->qpn"))
        XCTAssertTrue(verbs.contains("memcmp(session->gid.raw, peer->gid, 16) > 0"))
    }

    func testFirewallBlockIsTriedAgainEverySecond() throws {
        let detail = "macOS has not allowed the incoming connection yet."
        let sentence = introductionRetry(detail)
        XCTAssertTrue(sentence.contains("not allowed the incoming connection"))
        XCTAssertTrue(sentence.contains("tried again every second"))
        let diagnosis = diagnoseBridge(bridgeFacts(
            services: ["Thunderbolt Bridge", "ProtonVPN"],
            tunnels: [TunnelFact(name: "utun3", address: "10.2.0.2")],
            route: "utun3"
        ))
        XCTAssertEqual(phaseOnScreen(phase: sentence, diagnosis: diagnosis), sentence)
        XCTAssertEqual(exchangeStep(rc: 2, detail: detail), .retry(sentence))
        XCTAssertEqual(exchangeStep(rc: 1, detail: detail), .waiting)
        XCTAssertEqual(exchangeStep(rc: 0, detail: ""), .connected)
        guard case .reopen(let reopened) = exchangeStep(rc: -1, detail: "The queue pair did not become ready to send.") else {
            XCTAssertTrue(false, "expected the queue pair to be opened again")
            return
        }
        XCTAssertTrue(reopened.contains("tried again every second"))
        XCTAssertTrue(reopened.contains("ready to send"))
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let service = try String(contentsOf: root.appendingPathComponent("Sources/HyperTransferCore/PeerService.swift"), encoding: .utf8)
        XCTAssertTrue(service.contains("exchangeStep"))
        XCTAssertTrue(service.contains("case .reopen"))
        XCTAssertFalse(service.contains("if rc < 0"))
        let verbs = try String(contentsOf: root.appendingPathComponent("Sources/HyperTransferVerbs/VerbsBridge.c"), encoding: .utf8)
        XCTAssertTrue(verbs.contains("macOS has not allowed the incoming connection yet."))
        XCTAssertTrue(verbs.contains("return 2"))
    }

    func testOlderWindowSentenceKeepsTheCopyClosed() {
        let sentence = olderPeerFolderSentence()
        XCTAssertTrue(sentence.contains("cannot show its folder"))
        XCTAssertTrue(sentence.contains("copy stays closed"))
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/HyperTransferVerbs/VerbsBridge.c")
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        XCTAssertTrue(text.contains("hello->pad[0] = 1"))
        XCTAssertTrue(text.contains("peer_lists"))
        XCTAssertTrue(text.contains("#define HT_SETUP_LEN 64"))
    }
}

final class LandingTests {
    func testCopyStaysClosedUntilThePeerFolderIsListed() {
        let block = landingBlock(listing: nil, sourceName: "note.txt", sourceIsFolder: false, replace: false)
        XCTAssertTrue(block?.contains("not on screen") == true)
        XCTAssertTrue(block?.contains("copy stays closed") == true)
    }

    func testExistingFileStaysUntilReplace() {
        let listing = DirectoryListing(path: ".", parent: nil, entries: [file("note.txt")], truncated: false)
        let blocked = landingBlock(listing: listing, sourceName: "note.txt", sourceIsFolder: false, replace: false)
        XCTAssertTrue(blocked?.contains("already in this peer folder") == true)
        XCTAssertTrue(blocked?.contains("Replace after a match") == true)
        XCTAssertNil(landingBlock(listing: listing, sourceName: "note.txt", sourceIsFolder: false, replace: true))
    }

    func testHiddenExistingFileIsStillNamed() {
        var hidden = file(".secret")
        hidden.hidden = true
        let listing = DirectoryListing(path: "Docs", parent: ".", entries: [hidden], truncated: false)
        let block = landingBlock(listing: listing, sourceName: ".secret", sourceIsFolder: false, replace: false)
        XCTAssertTrue(block?.contains(".secret") == true)
        XCTAssertTrue(block?.contains("already in this peer folder") == true)
    }

    func testCaseDifferenceNamesThePeerFile() {
        let listing = DirectoryListing(path: ".", parent: nil, entries: [file("Notes.TXT")], truncated: false)
        let block = landingBlock(listing: listing, sourceName: "notes.txt", sourceIsFolder: false, replace: false)
        XCTAssertTrue(block?.contains("Notes.TXT") == true)
    }

    func testFolderAlreadyThereMustBeOpened() {
        let listing = DirectoryListing(path: ".", parent: nil, entries: [folder("Photos")], truncated: false)
        let block = landingBlock(listing: listing, sourceName: "Photos", sourceIsFolder: true, replace: true)
        XCTAssertTrue(block?.contains("Open it before copying") == true)
    }

    func testFileDoesNotLandOnAPeerFolder() {
        let listing = DirectoryListing(path: ".", parent: nil, entries: [folder("Photos")], truncated: false)
        let block = landingBlock(listing: listing, sourceName: "Photos", sourceIsFolder: false, replace: true)
        XCTAssertTrue(block?.contains("is a folder") == true)
        XCTAssertTrue(block?.contains("copy stays closed") == true)
    }

    func testFolderDoesNotLandOnAPeerFile() {
        let listing = DirectoryListing(path: ".", parent: nil, entries: [file("Photos")], truncated: false)
        let block = landingBlock(listing: listing, sourceName: "Photos", sourceIsFolder: true, replace: true)
        XCTAssertTrue(block?.contains("is a file") == true)
    }

    func testTruncatedListBlocksANameThatIsNotShown() {
        let listing = DirectoryListing(path: ".", parent: nil, entries: [file("shown.txt")], truncated: true)
        let block = landingBlock(listing: listing, sourceName: "hidden-past-the-window.txt", sourceIsFolder: false, replace: true)
        XCTAssertTrue(block?.contains("stopped early") == true)
        XCTAssertTrue(block?.contains("stay hidden") == true)
    }

    func testTruncatedListAllowsANameThatIsShown() {
        let listing = DirectoryListing(path: "Incoming", parent: ".", entries: [file("shown.txt")], truncated: true)
        XCTAssertNil(landingBlock(listing: listing, sourceName: "shown.txt", sourceIsFolder: false, replace: true))
        XCTAssertEqual(landingRelative(peerFolder: "Incoming", name: "shown.txt"), "Incoming/shown.txt")
    }

    func testNewNameInAFullListCanLand() {
        let listing = DirectoryListing(path: ".", parent: nil, entries: [file("other.txt")], truncated: false)
        XCTAssertNil(landingBlock(listing: listing, sourceName: "note.txt", sourceIsFolder: false, replace: false))
        XCTAssertEqual(landingRelative(peerFolder: ".", name: "note.txt"), "note.txt")
        XCTAssertEqual(landingRelative(peerFolder: "Docs", name: "note.txt"), "Docs/note.txt")
    }

    func testLinkNameStaysClosed() {
        var link = file("alias")
        link.kind = "link"
        link.leavesRoot = true
        let listing = DirectoryListing(path: ".", parent: nil, entries: [link], truncated: false)
        let block = landingBlock(listing: listing, sourceName: "alias", sourceIsFolder: false, replace: true)
        XCTAssertTrue(block?.contains("is a link") == true)
    }

    func testSlashInTheCopyNameStaysClosed() {
        let listing = DirectoryListing(path: ".", parent: nil, entries: [], truncated: false)
        XCTAssertTrue(landingBlock(listing: listing, sourceName: "../out", sourceIsFolder: false, replace: false)?.contains("single file name") == true)
        XCTAssertTrue(landingBlock(listing: listing, sourceName: "..", sourceIsFolder: false, replace: false)?.contains("single file name") == true)
    }

    private func file(_ name: String) -> DirectoryEntry {
        DirectoryEntry(name: name, kind: "file", size: 4, modified: nil, hidden: false, relative: name, leavesRoot: false)
    }

    private func folder(_ name: String) -> DirectoryEntry {
        DirectoryEntry(name: name, kind: "folder", size: nil, modified: nil, hidden: false, relative: name, leavesRoot: false)
    }
}

private func bridgeFacts(
    services: [String] = ["Thunderbolt Bridge"],
    bridgeUp: Bool = true,
    linkLocal: String? = "fe80::self",
    tunnels: [TunnelFact] = [],
    route: String? = nil,
    responders: [String] = [],
    replyFailed: Bool = false,
    probeFailed: Bool = false
) -> BridgeFacts {
    BridgeFacts(
        probeFailed: probeFailed,
        serviceLines: services,
        bridgeUp: bridgeUp,
        linkLocal: linkLocal,
        tunnels: tunnels,
        defaultRoute: route,
        responders: responders,
        selfAddress: "fe80::self",
        replyProbeFailed: replyFailed
    )
}
