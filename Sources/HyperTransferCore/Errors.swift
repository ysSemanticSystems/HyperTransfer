import Foundation

public enum StatusTone: String, Equatable, Sendable {
    case up
    case reachable
    case down
    case unreachable
    case place
}

public enum TransferCode: String, Equatable, Sendable {
    case match
    case dataForkMatches = "data-fork-matches"
    case sourceChanged = "source-changed"
    case destinationDiffers = "destination-differs"
    case length
    case algorithm
    case flush
    case notNotified = "not-notified"
    case writeIncomplete = "write-incomplete"
    case renameFailed = "rename-failed"
    case refused
    case exists
    case missing
    case ioError = "io-error"
    case mediaDisagreed = "media-disagreed"
    case sentDisagreed = "sent-disagreed"
    case empty
    case incomplete
}

public struct TransferError: Error, Equatable, Sendable {
    public var code: TransferCode
    public var detail: String

    public init(_ code: TransferCode, _ detail: String) {
        self.code = code
        self.detail = detail
    }

    public static func notNotified(_ detail: String) -> TransferError {
        TransferError(.notNotified, detail)
    }

    public static func writeIncomplete(_ detail: String) -> TransferError {
        TransferError(.writeIncomplete, detail)
    }

    public static func flush(_ detail: String) -> TransferError {
        TransferError(.flush, detail)
    }

    public static func refused(_ detail: String) -> TransferError {
        TransferError(.refused, detail)
    }
}
