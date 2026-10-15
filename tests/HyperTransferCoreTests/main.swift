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
        attempt("FabricTests.testThisMacProbeIsNotRDMA") { FabricTests().testThisMacProbeIsNotRDMA() }
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
