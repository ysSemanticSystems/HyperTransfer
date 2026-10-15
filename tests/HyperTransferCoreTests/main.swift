import Foundation

@main
struct HyperTransferChecks {
    static func main() {
        verifyEveryTestIsCalled()
        attempt("BrowseTests.testBrowseRejectsDotDot") { try BrowseTests().testBrowseRejectsDotDot() }
        attempt("BrowseTests.testBrowseRejectsSymlinkEscape") { try BrowseTests().testBrowseRejectsSymlinkEscape() }
        attempt("BrowseTests.testBrowseListsKindsAndKeepsHiddenNames") { try BrowseTests().testBrowseListsKindsAndKeepsHiddenNames() }
        attempt("BrowseTests.testPreviewIsAWindowWithoutAFileHash") { try BrowseTests().testPreviewIsAWindowWithoutAFileHash() }
        attempt("BrowseTests.testPreviewOfBinaryIsHex") { try BrowseTests().testPreviewOfBinaryIsHex() }
        attempt("BrowseTests.testResolvePlaceAllowsANewFinalName") { try BrowseTests().testResolvePlaceAllowsANewFinalName() }
        attempt("BrowseTests.testResolvePlaceRefusesAMissingParent") { try BrowseTests().testResolvePlaceRefusesAMissingParent() }
        attempt("BrowseTests.testPartialFileIsLabeledPartial") { try BrowseTests().testPartialFileIsLabeledPartial() }
        attempt("GateTests.testCopyStaysClosedWithoutRDMA") { GateTests().testCopyStaysClosedWithoutRDMA() }
        attempt("GateTests.testCopyStaysClosedWhenRDMAIsUpAndNoPeerExists") { GateTests().testCopyStaysClosedWhenRDMAIsUpAndNoPeerExists() }
        attempt("GateTests.testMissingProbeIsClosed") { GateTests().testMissingProbeIsClosed() }
        attempt("GateTests.testEveryTipSaysWhatItReadsAndWhatThatCanHide") { GateTests().testEveryTipSaysWhatItReadsAndWhatThatCanHide() }
        attempt("SourceContractTests.testCoreDoesNotOpenASocket") { try SourceContractTests().testCoreDoesNotOpenASocket() }
        attempt("SourceContractTests.testAppDoesNotBindAPort") { try SourceContractTests().testAppDoesNotBindAPort() }
        attempt("SourceContractTests.testWindowPairsHelpWithAnAccessibilityHint") { try SourceContractTests().testWindowPairsHelpWithAnAccessibilityHint() }
        attempt("SourceContractTests.testInvariantsCatalogLocksExist") { try SourceContractTests().testInvariantsCatalogLocksExist() }
        attempt("FabricTests.testDiskPressureWords") { FabricTests().testDiskPressureWords() }
        attempt("FabricTests.testDiskStatusUsesIntegerBounds") { FabricTests().testDiskStatusUsesIntegerBounds() }
        attempt("FabricTests.testDiskSpaceNamesThisVolume") { try FabricTests().testDiskSpaceNamesThisVolume() }
        attempt("FabricTests.testThunderboltIPIsNotRDMA") { FabricTests().testThunderboltIPIsNotRDMA() }
        attempt("FabricTests.testUnknownThunderboltProtocolIsNotRDMA") { FabricTests().testUnknownThunderboltProtocolIsNotRDMA() }
        attempt("FabricTests.testEmptyThunderboltBusIsDown") { FabricTests().testEmptyThunderboltBusIsDown() }
        attempt("FabricTests.testMalformedThunderboltJSONFailsClosed") { FabricTests().testMalformedThunderboltJSONFailsClosed() }
        attempt("FabricTests.testRoCEActiveIsUp") { FabricTests().testRoCEActiveIsUp() }
        attempt("FabricTests.testStateFortyIsNotActive") { FabricTests().testStateFortyIsNotActive() }
        attempt("FabricTests.testIWARPActiveIsUp") { FabricTests().testIWARPActiveIsUp() }
        attempt("FabricTests.testInfiniBandDownIsNotActive") { FabricTests().testInfiniBandDownIsNotActive() }
        attempt("FabricTests.testEFAIsRDMAAndNotCalledRoCE") { FabricTests().testEFAIsRDMAAndNotCalledRoCE() }
        attempt("FabricTests.testUnreadableEthernetDriverIsNotLabeledRoCE") { FabricTests().testUnreadableEthernetDriverIsNotLabeledRoCE() }
        attempt("FabricTests.testThunderboltSysfsActiveIsRDMA") { FabricTests().testThunderboltSysfsActiveIsRDMA() }
        attempt("FabricTests.testActiveRoCEStaysUpBesideThunderboltIP") { FabricTests().testActiveRoCEStaysUpBesideThunderboltIP() }
        attempt("FabricTests.testSysfsReadsAnActiveRoCEPort") { try FabricTests().testSysfsReadsAnActiveRoCEPort() }
        attempt("FabricTests.testAppleThunderboltActiveIsRDMA") { FabricTests().testAppleThunderboltActiveIsRDMA() }
        attempt("FabricTests.testAppleThunderboltDownIsNotRDMA") { FabricTests().testAppleThunderboltDownIsNotRDMA() }
        attempt("FabricTests.testActiveDeferIsNotActive") { FabricTests().testActiveDeferIsNotActive() }
        attempt("FabricTests.testParentheticalStateFortyIsNotActive") { FabricTests().testParentheticalStateFortyIsNotActive() }
        attempt("FabricTests.testThunderboltIPStaysClosedBesideActiveVerbs") { FabricTests().testThunderboltIPStaysClosedBesideActiveVerbs() }
        attempt("FabricTests.testThisMacProbeSeesActiveThunderboltVerbs") { FabricTests().testThisMacProbeSeesActiveThunderboltVerbs() }
        attempt("FabricTests.testVerbsDeviceOpensOnThisMac") { FabricTests().testVerbsDeviceOpensOnThisMac() }
        attempt("LinkTests.testVpnOnTheDefaultRouteIsNamedWhenNoPeerAnswers") { LinkTests().testVpnOnTheDefaultRouteIsNamedWhenNoPeerAnswers() }
        attempt("LinkTests.testVpnWithoutTheDefaultRouteIsNamedWhenNoPeerAnswers") { LinkTests().testVpnWithoutTheDefaultRouteIsNamedWhenNoPeerAnswers() }
        attempt("LinkTests.testVpnIsNamedWhenTheBridgeStillAnswers") { LinkTests().testVpnIsNamedWhenTheBridgeStillAnswers() }
        attempt("LinkTests.testNoPeerWithoutAVpnSaysTheNoteIsStillBeingSent") { LinkTests().testNoPeerWithoutAVpnSaysTheNoteIsStillBeingSent() }
        attempt("LinkTests.testPeerAnswerWithoutAVpnIsUp") { LinkTests().testPeerAnswerWithoutAVpnIsUp() }
        attempt("LinkTests.testMissingThunderboltBridgeServiceIsDown") { LinkTests().testMissingThunderboltBridgeServiceIsDown() }
        attempt("LinkTests.testDisabledThunderboltBridgeServiceIsDown") { LinkTests().testDisabledThunderboltBridgeServiceIsDown() }
        attempt("LinkTests.testBridgeInterfaceDownIsDown") { LinkTests().testBridgeInterfaceDownIsDown() }
        attempt("LinkTests.testMissingLinkLocalIsDown") { LinkTests().testMissingLinkLocalIsDown() }
        attempt("LinkTests.testLinkLocalIPv4OnTheBridgeIsNotAPath") { LinkTests().testLinkLocalIPv4OnTheBridgeIsNotAPath() }
        attempt("LinkTests.testOwnPingReplyIsNotAnotherMac") { LinkTests().testOwnPingReplyIsNotAnotherMac() }
        attempt("LinkTests.testUtunWithOnlyLinkLocalIsNotAVpn") { LinkTests().testUtunWithOnlyLinkLocalIsNotAVpn() }
        attempt("LinkTests.testEnabledVpnServiceWithoutATunnelIsNotUp") { LinkTests().testEnabledVpnServiceWithoutATunnelIsNotUp() }
        attempt("LinkTests.testDisabledVpnServiceWithALiveTunnelNamesTheInterface") { LinkTests().testDisabledVpnServiceWithALiveTunnelNamesTheInterface() }
        attempt("LinkTests.testTailscaleAndProtonAreBothNamed") { LinkTests().testTailscaleAndProtonAreBothNamed() }
        attempt("LinkTests.testDefaultRouteAloneNamesTheTunnel") { LinkTests().testDefaultRouteAloneNamesTheTunnel() }
        attempt("LinkTests.testProbeFailureDoesNotInventAPeer") { LinkTests().testProbeFailureDoesNotInventAPeer() }
        attempt("LinkTests.testReplyProbeFailureDoesNotClaimSilence") { LinkTests().testReplyProbeFailureDoesNotClaimSilence() }
        attempt("LinkTests.testWaitingPhaseShowsTheVpnSentence") { LinkTests().testWaitingPhaseShowsTheVpnSentence() }
        attempt("LinkTests.testBindFailureStaysOnScreen") { LinkTests().testBindFailureStaysOnScreen() }
        attempt("LinkTests.testQueuePairUpKeepsItsPhase") { LinkTests().testQueuePairUpKeepsItsPhase() }
        attempt("LinkTests.testParsersReadServicesInterfacesRouteAndPing") { LinkTests().testParsersReadServicesInterfacesRouteAndPing() }
        attempt("LinkTests.testThisMacBridgeProbeReturnsAWord") { LinkTests().testThisMacBridgeProbeReturnsAWord() }
        attempt("LinkTests.testASecondProcessCannotOpenThePort") { LinkTests().testASecondProcessCannotOpenThePort() }
        attempt("LinkTests.testTheWindowClaimsTheProcessBeforeItProbes") { try LinkTests().testTheWindowClaimsTheProcessBeforeItProbes() }
        attempt("LinkTests.testIPv4MappedGIDIsTheRoute") { try LinkTests().testIPv4MappedGIDIsTheRoute() }
        attempt("LinkTests.testReadyTransitionIsRetriedOnTheSamePair") { try LinkTests().testReadyTransitionIsRetriedOnTheSamePair() }
        attempt("LinkTests.testFirewallBlockIsTriedAgainEverySecond") { try LinkTests().testFirewallBlockIsTriedAgainEverySecond() }
        attempt("LinkTests.testOlderWindowSentenceKeepsTheCopyClosed") { LinkTests().testOlderWindowSentenceKeepsTheCopyClosed() }
        attempt("LandingTests.testCopyStaysClosedUntilThePeerFolderIsListed") { LandingTests().testCopyStaysClosedUntilThePeerFolderIsListed() }
        attempt("LandingTests.testExistingFileStaysUntilReplace") { LandingTests().testExistingFileStaysUntilReplace() }
        attempt("LandingTests.testHiddenExistingFileIsStillNamed") { LandingTests().testHiddenExistingFileIsStillNamed() }
        attempt("LandingTests.testCaseDifferenceNamesThePeerFile") { LandingTests().testCaseDifferenceNamesThePeerFile() }
        attempt("LandingTests.testFolderAlreadyThereMustBeOpened") { LandingTests().testFolderAlreadyThereMustBeOpened() }
        attempt("LandingTests.testFileDoesNotLandOnAPeerFolder") { LandingTests().testFileDoesNotLandOnAPeerFolder() }
        attempt("LandingTests.testFolderDoesNotLandOnAPeerFile") { LandingTests().testFolderDoesNotLandOnAPeerFile() }
        attempt("LandingTests.testTruncatedListBlocksANameThatIsNotShown") { LandingTests().testTruncatedListBlocksANameThatIsNotShown() }
        attempt("LandingTests.testTruncatedListAllowsANameThatIsShown") { LandingTests().testTruncatedListAllowsANameThatIsShown() }
        attempt("LandingTests.testNewNameInAFullListCanLand") { LandingTests().testNewNameInAFullListCanLand() }
        attempt("LandingTests.testLinkNameStaysClosed") { LandingTests().testLinkNameStaysClosed() }
        attempt("LandingTests.testSlashInTheCopyNameStaysClosed") { LandingTests().testSlashInTheCopyNameStaysClosed() }
        attempt("PeerTests.testPeerCopyMatchesAcrossTwoChunks") { try PeerTests().testPeerCopyMatchesAcrossTwoChunks() }
        attempt("PeerTests.testPeerCopyMatchesAnEmptyFile") { try PeerTests().testPeerCopyMatchesAnEmptyFile() }
        attempt("PeerTests.testPeerCopyDoesNotRenameWithoutTheRecord") { try PeerTests().testPeerCopyDoesNotRenameWithoutTheRecord() }
        attempt("PeerTests.testPeerCopyRefusesAPathThatLeavesTheRoot") { try PeerTests().testPeerCopyRefusesAPathThatLeavesTheRoot() }
        attempt("PeerTests.testPeerCopyDoesNotRenameWhenTheSourceChanges") { try PeerTests().testPeerCopyDoesNotRenameWhenTheSourceChanges() }
        attempt("PeerTests.testPeerCopyLeavesAnExistingFile") { try PeerTests().testPeerCopyLeavesAnExistingFile() }
        attempt("PeerTests.testPeerCopyReplacesOnlyAfterTheThreeReadsAgree") { try PeerTests().testPeerCopyReplacesOnlyAfterTheThreeReadsAgree() }
        attempt("PeerTests.testPeerCopyRejectsAnAbsolutePath") { try PeerTests().testPeerCopyRejectsAnAbsolutePath() }
        attempt("PeerTests.testPeerCopyRejectsAShortHeader") { try PeerTests().testPeerCopyRejectsAShortHeader() }
        attempt("PeerTests.testPeerCopyDoesNotRenameACorruptRecord") { try PeerTests().testPeerCopyDoesNotRenameACorruptRecord() }
        attempt("PeerTests.testPeerCopyDoesNotPostAnEmptyRecordAfterAnExactChunk") { try PeerTests().testPeerCopyDoesNotPostAnEmptyRecordAfterAnExactChunk() }
        attempt("PeerTests.testThunderboltFramesRoundTo4096") { PeerTests().testThunderboltFramesRoundTo4096() }
        attempt("PeerTests.testSetupRecordRejectsAnythingBut64Bytes") { PeerTests().testSetupRecordRejectsAnythingBut64Bytes() }
        attempt("PeerTests.testPeerListShowsTheFolderThatWillReceiveTheCopy") { try PeerTests().testPeerListShowsTheFolderThatWillReceiveTheCopy() }
        attempt("PeerTests.testPeerListKeepsAHiddenName") { try PeerTests().testPeerListKeepsAHiddenName() }
        attempt("PeerTests.testPeerListRefusesAPathThatLeavesTheRoot") { try PeerTests().testPeerListRefusesAPathThatLeavesTheRoot() }
        attempt("PeerTests.testPeerListRefusesASymlink") { try PeerTests().testPeerListRefusesASymlink() }
        attempt("PeerTests.testPeerListStopsEarlyWhenThePageIsFull") { PeerTests().testPeerListStopsEarlyWhenThePageIsFull() }
        attempt("PeerTests.testFileHeaderIsNotAPeerList") { PeerTests().testFileHeaderIsNotAPeerList() }
        attempt("SourceContractTests.testQueuePairRecordStays64Bytes") { try SourceContractTests().testQueuePairRecordStays64Bytes() }
        attempt("TransferTests.testRecordIs64BytesAndSeparateFromPayload") { TransferTests().testRecordIs64BytesAndSeparateFromPayload() }
        attempt("TransferTests.testShortRecordIsNotANotification") { TransferTests().testShortRecordIsNotANotification() }
        attempt("TransferTests.testWrongVersionIsNotANotification") { TransferTests().testWrongVersionIsNotANotification() }
        attempt("TransferTests.testTakeBeforeLandIsNotNotified") { TransferTests().testTakeBeforeLandIsNotNotified() }
        attempt("TransferTests.testCookieHiddenDoesNotNotify") { try TransferTests().testCookieHiddenDoesNotNotify() }
        attempt("TransferTests.testEmptyFileStillNeedsACompletionRecord") { try TransferTests().testEmptyFileStillNeedsACompletionRecord() }
        attempt("TransferTests.testDataHiddenIsWriteIncomplete") { try TransferTests().testDataHiddenIsWriteIncomplete() }
        attempt("TransferTests.testCorruptFlushDoesNotPublish") { try TransferTests().testCorruptFlushDoesNotPublish() }
        attempt("TransferTests.testFlushBoundariesOfOneSevenEightAndNine") { try TransferTests().testFlushBoundariesOfOneSevenEightAndNine() }
        attempt("TransferTests.testEmptyFileMatches") { try TransferTests().testEmptyFileMatches() }
        attempt("TransferTests.testMultichunkMatches") { try TransferTests().testMultichunkMatches() }
        attempt("TransferTests.testExactChunkBoundaryDoesNotPostAPhantomEmptyChunk") { try TransferTests().testExactChunkBoundaryDoesNotPostAPhantomEmptyChunk() }
        attempt("TransferTests.testSparseFileMatchesLogicalBytes") { try TransferTests().testSparseFileMatchesLogicalBytes() }
        attempt("TransferTests.testSourceChangesDuringCopy") { try TransferTests().testSourceChangesDuringCopy() }
        attempt("TransferTests.testLengthChangeIsNamed") { try TransferTests().testLengthChangeIsNamed() }
        attempt("TransferTests.testReplaceWaitsForAMatch") { try TransferTests().testReplaceWaitsForAMatch() }
        attempt("TransferTests.testDestinationMismatchUnit") { TransferTests().testDestinationMismatchUnit() }
        attempt("TransferTests.testLengthMismatchUnit") { TransferTests().testLengthMismatchUnit() }
        attempt("TransferTests.testSecondHashAsksCacheAside") { try TransferTests().testSecondHashAsksCacheAside() }
        attempt("TransferTests.testXattrPromotesDataForkAndDoesNotSayMatch") { try TransferTests().testXattrPromotesDataForkAndDoesNotSayMatch() }
        attempt("TransferTests.testProvenanceStampIsNamedAndIsNotTheWord") { try TransferTests().testProvenanceStampIsNamedAndIsNotTheWord() }
        attempt("TransferTests.testRefusesSymlink") { try TransferTests().testRefusesSymlink() }
        attempt("TransferTests.testRefusesFifo") { try TransferTests().testRefusesFifo() }
        attempt("TransferTests.testRefusesExistingWithoutReplace") { try TransferTests().testRefusesExistingWithoutReplace() }
        attempt("TransferTests.testReplaceOnlyAfterMatch") { try TransferTests().testReplaceOnlyAfterMatch() }
        attempt("TransferTests.testRenameFailureIsNotAMatch") { try TransferTests().testRenameFailureIsNotAMatch() }
        attempt("TransferTests.testPromoteOntoADirectoryFails") { try TransferTests().testPromoteOntoADirectoryFails() }
        attempt("TransferTests.testInodeChangeIsNamedWhenBytesMatch") { try TransferTests().testInodeChangeIsNamedWhenBytesMatch() }
        attempt("TransferTests.testDirectoryIncludesDotfile") { try TransferTests().testDirectoryIncludesDotfile() }
        attempt("TransferTests.testDirectorySkipsSymlinkAndIsNotComplete") { try TransferTests().testDirectorySkipsSymlinkAndIsNotComplete() }
        attempt("TransferTests.testRefusesCopyIntoItself") { try TransferTests().testRefusesCopyIntoItself() }
        attempt("TransferTests.testEmptyFolderIsPlaceNotMatch") { try TransferTests().testEmptyFolderIsPlaceNotMatch() }
        attempt("TransferTests.testBlake2bMatchesTheEmptyAndAbcVectors") { TransferTests().testBlake2bMatchesTheEmptyAndAbcVectors() }
        attempt("TransferTests.testTwoReadsThatDisagreeAreNotTrusted") { TransferTests().testTwoReadsThatDisagreeAreNotTrusted() }
        if Expect.failures.isEmpty {
            print("checks passed")
            return
        }
        print("\(Expect.failures.count) checks failed")
        for failure in Expect.failures { print(failure) }
        exit(1)
    }

    private static func verifyEveryTestIsCalled() {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let mainText = (try? String(contentsOf: URL(fileURLWithPath: #filePath), encoding: .utf8)) ?? ""
        let files = (try? FileManager.default.contentsOfDirectory(at: here, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "swift" && file.lastPathComponent != "main.swift" && file.lastPathComponent != "Expect.swift" && file.lastPathComponent != "Support.swift" {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            var className = ""
            for line in text.split(separator: "\n") {
                if line.hasPrefix("final class ") {
                    className = line.dropFirst("final class ".count).split(separator: " ").first.map(String.init) ?? ""
                }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("func test") else { continue }
                let name = trimmed.dropFirst("func ".count).prefix { $0 != "(" }
                let needle = "\(className).\(name)"
                if !mainText.contains(needle) {
                    Expect.fail("\(needle) is not called from the check runner")
                }
            }
        }
    }
}
