import Foundation

// MARK: - Response Types

/// Transfer response
public struct TransferResponse: Codable, Sendable {
    /// Status
    public let status: String
    /// Response data
    public let response: TransferResponseData?
}

/// Transfer response data
public struct TransferResponseData: Codable, Sendable {
    /// Response type
    public let type: String
}
