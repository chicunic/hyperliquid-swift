import Foundation

/// Input schema for Perp Dex registration
public struct PerpDexSchemaInput: Sendable, Encodable {
    public let fullName: String
    public let collateralToken: Int
    public let oracleUpdater: String?

    public init(fullName: String, collateralToken: Int, oracleUpdater: String?) {
        self.fullName = fullName
        self.collateralToken = collateralToken
        self.oracleUpdater = oracleUpdater
    }
}

/// Multi-sig user configuration
public struct MultiSigSignerConfig: Sendable, Encodable {
    public let authorizedUsers: [String]
    public let threshold: Int

    public init(authorizedUsers: [String], threshold: Int) {
        self.authorizedUsers = authorizedUsers
        self.threshold = threshold
    }
}
