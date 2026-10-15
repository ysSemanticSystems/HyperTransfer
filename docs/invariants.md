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
- **ops**: The native window does not listen. Copy stays closed until a port is RDMA and a queue pair exists.
- **paths**: Sources/HyperTransferCore/Session.swift, Sources/HyperTransferCore/Tips.swift, Sources/HyperTransfer
- **added**: 2026-10-15

### INV-RDMA-002 — Thunderbolt IP is not an active RDMA port
- **status**: active
- **area**: fabric
- **failure**: A connected Thunderbolt cable that speaks Internet Protocol, or an unrecognized protocol on that cable, opens the file panes or starts a copy
- **lock**: testThunderboltIPIsNotRDMA, testUnknownThunderboltProtocolIsNotRDMA, testEmptyThunderboltBusIsDown, testMalformedThunderboltJSONFailsClosed, testThisMacProbeIsNotRDMA, testActiveRoCEStaysUpBesideThunderboltIP
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

### INV-FABRIC-001 — Transport names stay specific
- **status**: active
- **area**: fabric
- **failure**: iWARP, EFA, or an Ethernet port with no driver name is labeled RoCE, or a down InfiniBand port is treated as active, or state 40 is read as state 4
- **lock**: testRoCEActiveIsUp, testIWARPActiveIsUp, testInfiniBandDownIsNotActive, testEFAIsRDMAAndNotCalledRoCE, testUnreadableEthernetDriverIsNotLabeledRoCE, testThunderboltSysfsActiveIsRDMA, testSysfsReadsAnActiveRoCEPort, testDiskPressureWords, testDiskStatusUsesIntegerBounds, testStateFortyIsNotActive
- **ops**: Only the number before the colon equaling 4 counts as ACTIVE. Disk pressure is Full under 5 percent free and Tight under 15 percent.
- **paths**: Sources/HyperTransferCore/Fabric.swift
- **added**: 2026-10-15

### INV-UI-001 — Every control says what it reads and what that reading can hide
- **status**: active
- **area**: ui
- **failure**: A control has a tooltip that only repeats its label, or help text is a string literal the catalog cannot see
- **lock**: testEveryTipSaysWhatItReadsAndWhatThatCanHide, testWindowPairsHelpWithAnAccessibilityHint, testPreviewIsAWindowWithoutAFileHash, testPreviewOfBinaryIsHex, testBrowseListsKindsAndKeepsHiddenNames, testDiskSpaceNamesThisVolume
- **ops**: Status color keeps its word. Up is green, Reachable is teal, Down is red, Unreachable is orange, Place is neutral. Full and Tight follow the disk colors, red then orange. `.help` and `.accessibilityHint` carry the same sentence.
- **paths**: Sources/HyperTransferCore/Tips.swift, Sources/HyperTransfer/ContentView.swift
- **added**: 2026-10-15
