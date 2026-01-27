import Foundation

// MARK: - PerpDex Query Response

/// Represents a Perp DEX returned from the perpDexs API
public struct PerpDex: Codable, Sendable {
    /// Short name of the DEX (e.g., "xyz", "flx")
    public let name: String
    /// Full display name of the DEX
    public let fullName: String
    /// Address of the DEX deployer
    public let deployer: String
    /// Address of the oracle updater (if any)
    public let oracleUpdater: String?
    /// Address that receives fees (nil for some DEXes like hyna, abcd)
    public let feeRecipient: String?
    /// Asset to streaming open interest cap mapping: [[asset, cap], ...]
    public let assetToStreamingOiCap: [[String]]
    /// Sub-deployers with their permissions: [[permission, [addresses]], ...]
    public let subDeployers: [[SubDeployerEntry]]
    /// Fee scale for the deployer
    public let deployerFeeScale: String
    /// Timestamp of last fee scale change
    public let lastDeployerFeeScaleChangeTime: String
    /// Asset to funding multiplier mapping: [[asset, multiplier], ...]
    public let assetToFundingMultiplier: [[String]]
    /// Asset to funding interest rate mapping: [[asset, rate], ...]
    public let assetToFundingInterestRate: [[String]]
}

/// Sub-deployer entry that can be either a string (permission name) or an array of addresses
public enum SubDeployerEntry: Codable, Sendable {
    case string(String)
    case addresses([String])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let arrayValue = try? container.decode([String].self) {
            self = .addresses(arrayValue)
        } else {
            throw DecodingError.typeMismatch(
                Self.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected String or [String]"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .addresses(let value):
            try container.encode(value)
        }
    }
}

// MARK: - PerpDex Input Schema

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

// MARK: - Multi-Sig Signers Response

/// Response from userToMultiSigSigners API
public struct MultiSigSignersResponse: Codable, Sendable {
    public let signers: [String]
    public let threshold: Int
}

// MARK: - Deploy Auction Status

/// Gas auction status for perp or spot deployment
public struct GasAuction: Codable, Sendable {
    /// Start time in seconds since epoch
    public let startTimeSeconds: Int64
    /// Duration of the auction in seconds
    public let durationSeconds: Int64
    /// Starting gas price
    public let startGas: String
    /// Current gas price (nil if auction hasn't started or ended)
    public let currentGas: String?
    /// Ending gas price (nil if auction is still in progress)
    public let endGas: String?
}

/// Response from perpDeployAuctionStatus API
public typealias PerpDeployAuctionStatus = GasAuction

/// Response from spotDeployState API
public struct SpotDeployState: Codable, Sendable {
    /// Deployment states
    public let states: [SpotDeployStateEntry]
    /// Gas auction information
    public let gasAuction: GasAuction
}

/// Individual spot deploy state entry
public struct SpotDeployStateEntry: Codable, Sendable {
    public let token: String
    public let spec: SpotDeploySpec
    public let gasAuction: GasAuction?
}

/// Spot deploy specification
public struct SpotDeploySpec: Codable, Sendable {
    public let name: String
    public let szDecimals: Int
    public let weiDecimals: Int
}

// MARK: - DEX Abstraction State

/// User DEX abstraction state
public struct UserDexAbstractionState: Codable, Sendable {
    /// Whether DEX abstraction is enabled
    public let enabled: Bool
    /// The DEX being used for abstraction
    public let dex: String?
}

// MARK: - User Portfolio History

/// Portfolio history data for a specific time period
public struct UserPortfolioPeriodData: Codable, Sendable {
    /// Account value history: [[timestamp, value], ...]
    public let accountValueHistory: [[UserPortfolioHistoryEntry]]
    /// PnL history: [[timestamp, pnl], ...]
    public let pnlHistory: [[UserPortfolioHistoryEntry]]
    /// Trading volume
    public let vlm: String
}

/// Portfolio history entry that can be either a timestamp (Int64) or a value (String)
public enum UserPortfolioHistoryEntry: Codable, Sendable {
    case timestamp(Int64)
    case value(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int64.self) {
            self = .timestamp(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .value(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                Self.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected Int64 or String"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .timestamp(let value):
            try container.encode(value)
        case .value(let value):
            try container.encode(value)
        }
    }
}

/// Portfolio period entry: [period_name, data]
public struct UserPortfolioEntry: Codable, Sendable {
    /// Period name (e.g., "day", "week", "month", "allTime")
    public let period: String
    /// Portfolio data for this period
    public let data: UserPortfolioPeriodData

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        period = try container.decode(String.self)
        data = try container.decode(UserPortfolioPeriodData.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(period)
        try container.encode(data)
    }
}

/// User portfolio history response is an array of period entries
public typealias UserPortfolioHistory = [UserPortfolioEntry]
