# Invariants

One catalog. Append an entry when a failure would have to be re-taught. Each active entry names a test that fails if the behavior regresses.

## Entry template

Copy a catalog entry. The id looks like `INV-RDMA-001`. Fields are status, area, failure, lock, ops, paths, and added. A lock names tests that already exist.

## Catalog

### INV-RDMA-001 — The file never rides a kernel socket
- **status**: active
- **area**: rdma
- **failure**: A Thunderbolt IP link, or any other kernel path, is used as the copy and reported as a success
- **lock**: testCoreDoesNotOpenASocket, testAppDoesNotBindAPort, testCopyStaysClosedWithoutRDMA, testCopyStaysClosedWhenRDMAIsUpAndNoPeerExists, testMissingProbeIsClosed
- **ops**: File bytes stay off sockets. UDP 24764 carries the 64-byte queue-pair record and then closes. Copy stays closed until a port is RDMA and a queue pair exists.
- **paths**: Sources/HyperTransferCore/Session.swift, Sources/HyperTransferCore/Tips.swift, Sources/HyperTransfer
- **added**: 2026-10-15

### INV-RDMA-002 — Thunderbolt IP is not an active RDMA port
- **status**: active
- **area**: fabric
- **failure**: A connected Thunderbolt cable that speaks Internet Protocol, or an unrecognized protocol on that cable, opens the file panes or starts a copy
- **lock**: testThunderboltIPIsNotRDMA, testUnknownThunderboltProtocolIsNotRDMA, testEmptyThunderboltBusIsDown, testMalformedThunderboltJSONFailsClosed, testThisMacProbeSeesActiveThunderboltVerbs, testActiveRoCEStaysUpBesideThunderboltIP, testThunderboltIPStaysClosedBesideActiveVerbs
- **ops**: Up on the cable and Unreachable on the IP service can be true together. Copy stays closed until a port's own word is Up and its transport is RDMA.
- **paths**: Sources/HyperTransferCore/Fabric.swift
- **added**: 2026-10-15

### INV-RDMA-003 — A one-sided write is not done until the cookie is visible and the flush agrees
- **status**: active
- **area**: rdma
- **failure**: The receiver hashes or renames a file while the completion record is missing, or while the CPU still sees zeros after the sender was told the write completed
- **lock**: testRecordIs64BytesAndSeparateFromPayload, testShortRecordIsNotANotification, testWrongVersionIsNotANotification, testCookieHiddenDoesNotNotify, testEmptyFileStillNeedsACompletionRecord, testDataHiddenIsWriteIncomplete, testCorruptFlushDoesNotPublish, testTakeBeforeLandIsNotNotified, testFlushBoundariesOfOneSevenEightAndNine, testExactChunkBoundaryDoesNotPostAPhantomEmptyChunk, testBlake2bMatchesTheEmptyAndAbcVectors, testTwoReadsThatDisagreeAreNotTrusted
- **ops**: The completion record is 160 bytes and carries SHA-512 and BLAKE2b. The flush read of the tail happens before that record is published. An empty file still posts the record. A file whose size is an exact chunk does not post a following empty record. Two reads that return different bytes are not digested.
- **paths**: Sources/HyperTransferCore/Protocol.swift, Sources/HyperTransferCore/Session.swift
- **added**: 2026-10-15

### INV-INTEGRITY-001 — Both digests, on three passes, and the finished name waits for them
- **status**: active
- **area**: integrity
- **failure**: A copy is renamed into place when the source changed, the received file differs, the two reads of one pass disagree, or the rename itself failed.
- **lock**: testEmptyFileMatches, testMultichunkMatches, testSparseFileMatchesLogicalBytes, testSourceChangesDuringCopy, testLengthChangeIsNamed, testDestinationMismatchUnit, testLengthMismatchUnit, testReplaceWaitsForAMatch, testRefusesExistingWithoutReplace, testReplaceOnlyAfterMatch, testRenameFailureIsNotAMatch, testPromoteOntoADirectoryFails, testInodeChangeIsNamedWhenBytesMatch, testTwoReadsThatDisagreeAreNotTrusted
- **ops**: The partial name ends in `.ht-partial`. Each pass reads the file twice, at 1 MiB and at 64 KiB + 13 bytes, and compares the bytes. SHA-512 and BLAKE2b both have to match across the before, received, and source-again measurements. The bytes handed to the copy have to match the first measurement. A warm failure leaves the previous file where it was.
- **paths**: Sources/HyperTransferCore/Integrity.swift, Sources/HyperTransferCore/Session.swift
- **added**: 2026-10-15

### INV-INTEGRITY-002 — The second source read asks the cache to step aside
- **status**: active
- **area**: integrity
- **failure**: The source-again hash is a replay of the page cache and the receipt does not say so
- **lock**: testSecondHashAsksCacheAside
- **ops**: On this Mac the second read sets F_NOCACHE. A disk with its own buffer can still agree with itself. The receipt names the cache state.
- **paths**: Sources/HyperTransferCore/Integrity.swift
- **added**: 2026-10-15

### INV-INTEGRITY-003 — A data-fork match is not the word Match
- **status**: active
- **area**: integrity
- **failure**: Extended attributes or a resource fork are dropped, and the receipt still says Match. Or `com.apple.provenance` steals the word Match from every file on this Mac.
- **lock**: testXattrPromotesDataForkAndDoesNotSayMatch, testProvenanceStampIsNamedAndIsNotTheWord
- **ops**: The bytes are renamed into place. Another attribute makes the word Data fork. `com.apple.provenance` is named and does not take that word.
- **paths**: Sources/HyperTransferCore/Integrity.swift, Sources/HyperTransferCore/Session.swift
- **added**: 2026-10-15

### INV-INTEGRITY-004 — Special files, escapes, and a copy into itself stay refused
- **status**: active
- **area**: integrity
- **failure**: A symlink is followed, a path climbs out of the root, or a folder is copied into itself
- **lock**: testRefusesSymlink, testRefusesFifo, testBrowseRejectsDotDot, testBrowseRejectsSymlinkEscape, testRefusesCopyIntoItself, testDirectorySkipsSymlinkAndIsNotComplete, testDirectoryIncludesDotfile, testEmptyFolderIsPlaceNotMatch, testResolvePlaceAllowsANewFinalName, testResolvePlaceRefusesAMissingParent, testPartialFileIsLabeledPartial
- **ops**: Hidden names can be filtered in the list. A folder copy still includes them. Symlinks are listed, skipped, and not followed.
- **paths**: Sources/HyperTransferCore/Browse.swift, Sources/HyperTransferCore/Session.swift
- **added**: 2026-10-15

### INV-FABRIC-002 — A Thunderbolt verbs port in state 4 is RDMA
- **status**: active
- **area**: fabric
- **failure**: `ibv_devinfo` shows `PORT_ACTIVE (4)` on a Thunderbolt link layer and the file panes stay closed, or protocol 1 on the cable is treated as that port, or a parenthetical state 40 is read as state 4
- **lock**: testAppleThunderboltActiveIsRDMA, testAppleThunderboltDownIsNotRDMA, testParentheticalStateFortyIsNotActive, testThunderboltIPStaysClosedBesideActiveVerbs, testThisMacProbeSeesActiveThunderboltVerbs
- **ops**: The cable row can stay Up and the IP row Unreachable while `rdma_enN/1` is Up. Copy stays closed until that verbs port's own word is Up.
- **paths**: Sources/HyperTransferCore/Fabric.swift
- **added**: 2026-10-15

### INV-RDMA-004 — The queue-pair datagram is 64 bytes and is not the file
- **status**: active
- **area**: rdma
- **failure**: The setup socket accepts anything but the 64-byte record, or the finished name is written before the completion record is visible
- **lock**: testQueuePairRecordStays64Bytes, testPeerCopyDoesNotRenameWithoutTheRecord, testPeerCopyMatchesAcrossTwoChunks, testPeerCopyMatchesAnEmptyFile, testPeerCopyRefusesAPathThatLeavesTheRoot, testVerbsDeviceOpensOnThisMac
- **ops**: UDP 24764 on the Thunderbolt bridge carries the queue-pair record only, then the socket closes. File bytes are verbs sends. The receiver renames only after the record matches and the sender's three reads agree.
- **paths**: Sources/HyperTransferVerbs/VerbsBridge.c, Sources/HyperTransferCore/PeerCopy.swift, Sources/HyperTransferCore/PeerService.swift
- **added**: 2026-10-15

### INV-RDMA-005 — The far side renames only after the record and the three reads
- **status**: active
- **area**: rdma
- **failure**: A peer copy renames the finished name when the source changed, the completion record is corrupt, an exact chunk posts an empty record, or an existing file is replaced before the three reads agree
- **lock**: testPeerCopyDoesNotRenameWhenTheSourceChanges, testPeerCopyLeavesAnExistingFile, testPeerCopyReplacesOnlyAfterTheThreeReadsAgree, testPeerCopyRejectsAnAbsolutePath, testPeerCopyRejectsAShortHeader, testPeerCopyDoesNotRenameACorruptRecord, testPeerCopyDoesNotPostAnEmptyRecordAfterAnExactChunk
- **ops**: The receiver posts the receive. It writes the partial only after the 160-byte record matches the visible bytes. The sender commits the rename only when the before, received, and source-again digests agree. A path that leaves the root is refused before any payload is posted.
- **paths**: Sources/HyperTransferCore/PeerCopy.swift
- **added**: 2026-10-15

### INV-FABRIC-003 — Thunderbolt frame size and the setup record stay exact
- **status**: active
- **area**: fabric
- **failure**: A message is posted at a length the peer did not post, a datagram other than the 64-byte HTQ1 record is accepted as the queue pair, or state 5 is treated as active
- **lock**: testThunderboltFramesRoundTo4096, testSetupRecordRejectsAnythingBut64Bytes, testActiveDeferIsNotActive
- **ops**: Posted lengths round up to a multiple of 4096. The setup record is 64 bytes and its magic is HTQ1. PORT_ACTIVE_DEFER (5) is Down.
- **paths**: Sources/HyperTransferVerbs/VerbsBridge.c, Sources/HyperTransferCore/Fabric.swift
- **added**: 2026-10-15

### INV-FABRIC-001 — Transport names stay specific
- **status**: active
- **area**: fabric
- **failure**: iWARP, EFA, or an Ethernet port with no driver name is labeled RoCE, or a down InfiniBand port is treated as active, or state 40 is read as state 4
- **lock**: testRoCEActiveIsUp, testIWARPActiveIsUp, testInfiniBandDownIsNotActive, testEFAIsRDMAAndNotCalledRoCE, testUnreadableEthernetDriverIsNotLabeledRoCE, testThunderboltSysfsActiveIsRDMA, testSysfsReadsAnActiveRoCEPort, testDiskPressureWords, testDiskStatusUsesIntegerBounds, testStateFortyIsNotActive
- **ops**: Only the number before the colon equaling 4 counts as ACTIVE. Disk pressure is Full under 5 percent free and Tight under 15 percent.
- **paths**: Sources/HyperTransferCore/Fabric.swift
- **added**: 2026-10-15

### INV-FABRIC-004 — A VPN or a missing Thunderbolt bridge is named while the queue pair is down
- **status**: active
- **area**: fabric
- **failure**: The window waits for a peer with no mention of the VPN, the missing Thunderbolt Bridge service, a disabled service, a down interface, a missing link-local address, or a reply that is only this Mac
- **lock**: testVpnOnTheDefaultRouteIsNamedWhenNoPeerAnswers, testVpnWithoutTheDefaultRouteIsNamedWhenNoPeerAnswers, testVpnIsNamedWhenTheBridgeStillAnswers, testNoPeerWithoutAVpnSaysTheNoteIsStillBeingSent, testPeerAnswerWithoutAVpnIsUp, testMissingThunderboltBridgeServiceIsDown, testDisabledThunderboltBridgeServiceIsDown, testBridgeInterfaceDownIsDown, testMissingLinkLocalIsDown, testLinkLocalIPv4OnTheBridgeIsNotAPath, testOwnPingReplyIsNotAnotherMac, testUtunWithOnlyLinkLocalIsNotAVpn, testEnabledVpnServiceWithoutATunnelIsNotUp, testDisabledVpnServiceWithALiveTunnelNamesTheInterface, testTailscaleAndProtonAreBothNamed, testDefaultRouteAloneNamesTheTunnel, testProbeFailureDoesNotInventAPeer, testReplyProbeFailureDoesNotClaimSilence, testWaitingPhaseShowsTheVpnSentence, testBindFailureStaysOnScreen, testQueuePairUpKeepsItsPhase, testParsersReadServicesInterfacesRouteAndPing, testThisMacBridgeProbeReturnsAWord
- **ops**: The 64-byte note stays on the Thunderbolt bridge. A tunnel with a global address, or a tunnel that owns the default route, is named. The file is not sent through the VPN. A service name with no tunnel address is not treated as up. This Mac's own ping reply is not another Mac.
- **paths**: Sources/HyperTransferCore/LinkPath.swift, Sources/HyperTransfer/ContentView.swift
- **added**: 2026-10-15

### INV-RDMA-008 — One process opens the Thunderbolt port
- **status**: active
- **area**: rdma
- **failure**: A second HyperTransfer opens the verbs device, or a port that did not answer is opened again
- **lock**: testASecondProcessCannotOpenThePort, testTheWindowClaimsTheProcessBeforeItProbes
- **ops**: The second launch brings the existing window forward and exits before any verbs call. The port is opened once. If that open does not answer within 8 seconds, it is not opened again. `ibv_devinfo` is stopped if it does not return within 5 seconds.
- **paths**: Sources/HyperTransfer/HyperTransferApp.swift, Sources/HyperTransferCore/PeerService.swift, Sources/HyperTransferVerbs/VerbsBridge.c, Sources/HyperTransferJoin/main.swift
- **added**: 2026-10-15

### INV-RDMA-007 — The route GID is the IPv4-mapped address
- **status**: active
- **area**: rdma
- **failure**: The ready transition is programmed with the link-local GID at index 0 while an IPv4-mapped GID is present, or the window asks the user to assign an address
- **lock**: testIPv4MappedGIDIsTheRoute
- **ops**: `::ffff:` is preferred when the port already has it. A fe80 GID is the route when it is the only one. No address is requested.
- **paths**: Sources/HyperTransferVerbs/VerbsBridge.c
- **added**: 2026-10-15

### INV-RDMA-006 — A refused ready transition keeps the same queue pair
- **status**: active
- **area**: rdma
- **failure**: The kernel refuses INIT to ready-to-receive, the queue pair is destroyed, and the next hello cannot meet the peer that is still holding the old number
- **lock**: testReadyTransitionIsRetriedOnTheSamePair
- **ops**: After the peer note arrives, the ready step is retried on that pair. The higher queue-pair number waits so the kernel waits overlap. A later hello from a rebuilt peer starts that series again. A missed go-ahead clears the remembered peer.
- **paths**: Sources/HyperTransferVerbs/VerbsBridge.c, Sources/HyperTransferCore/LinkPath.swift
- **added**: 2026-10-15

### INV-FABRIC-005 — A refused network allowance keeps the queue-pair note trying
- **status**: active
- **area**: fabric
- **failure**: The first blocked send or bind, including macOS waiting for Allow, ends the introduction and leaves no further attempt
- **lock**: testFirewallBlockIsTriedAgainEverySecond
- **ops**: A missing allowance, a failed send, and a failed bind try again every second. The sentence stays on screen and names the allowance when macOS refused the socket. A queue pair that cannot become ready is opened again. A quiet wait with no peer also continues.
- **paths**: Sources/HyperTransferCore/PeerService.swift, Sources/HyperTransferCore/LinkPath.swift, Sources/HyperTransferVerbs/VerbsBridge.c
- **added**: 2026-10-15

### INV-UI-002 — A copy lands only in a peer folder this window has listed
- **status**: active
- **area**: ui
- **failure**: A typed path, an unlisted folder, a truncated page, a hidden name, or a case-different name can receive a copy the window has not shown
- **lock**: testCopyStaysClosedUntilThePeerFolderIsListed, testExistingFileStaysUntilReplace, testHiddenExistingFileIsStillNamed, testCaseDifferenceNamesThePeerFile, testFolderAlreadyThereMustBeOpened, testFileDoesNotLandOnAPeerFolder, testFolderDoesNotLandOnAPeerFile, testTruncatedListBlocksANameThatIsNotShown, testTruncatedListAllowsANameThatIsShown, testNewNameInAFullListCanLand, testLinkNameStaysClosed, testSlashInTheCopyNameStaysClosed, testPeerListShowsTheFolderThatWillReceiveTheCopy, testPeerListKeepsAHiddenName, testPeerListRefusesAPathThatLeavesTheRoot, testPeerListRefusesASymlink, testPeerListStopsEarlyWhenThePageIsFull, testFileHeaderIsNotAPeerList, testOlderWindowSentenceKeepsTheCopyClosed
- **ops**: The peer pane lists the peer home folder over the queue pair. The copy uses that folder and the selected name. An older window, whose setup pad is 0, cannot show the folder, and the copy stays closed.
- **paths**: Sources/HyperTransferCore/Landing.swift, Sources/HyperTransferCore/PeerCopy.swift, Sources/HyperTransferVerbs/VerbsBridge.c
- **added**: 2026-10-15

### INV-UI-001 — Every control says what it reads and what that reading can hide
- **status**: active
- **area**: ui
- **failure**: A control has a tooltip that only repeats its label, or help text is a string literal the catalog cannot see
- **lock**: testEveryTipSaysWhatItReadsAndWhatThatCanHide, testWindowPairsHelpWithAnAccessibilityHint, testPreviewIsAWindowWithoutAFileHash, testPreviewOfBinaryIsHex, testBrowseListsKindsAndKeepsHiddenNames, testDiskSpaceNamesThisVolume
- **ops**: Status color keeps its word. Up is green, Reachable is teal, Down is red, Unreachable is orange, Place is neutral. Full and Tight follow the disk colors, red then orange. `.help` and `.accessibilityHint` carry the same sentence.
- **paths**: Sources/HyperTransferCore/Tips.swift, Sources/HyperTransfer/ContentView.swift
- **added**: 2026-10-15
