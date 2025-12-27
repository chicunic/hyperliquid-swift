import Foundation

// MARK: - Perp Market Types

/// Perpetual asset information
public struct AssetInfo: Codable, Sendable {
    /// Asset name (e.g., "BTC", "ETH")
    public let name: String
    /// Number of decimals for size
    public let szDecimals: Int
}

/// Perpetual market metadata
public struct Meta: Codable, Sendable {
    /// List of all perpetual assets
    public let universe: [AssetInfo]
}

/// Perpetual asset context (real-time market data)
public struct PerpAssetCtx: Codable, Sendable {
    /// Current funding rate
    public let funding: String
    /// Open interest
    public let openInterest: String
    /// Previous day's price
    public let prevDayPx: String
    /// 24h notional volume
    public let dayNtlVlm: String
    /// Premium
    public let premium: String?
    /// Oracle price
    public let oraclePx: String
    /// Mark price
    public let markPx: String
    /// Mid price (can be null if no liquidity)
    public let midPx: String?
    /// Impact prices [bid impact, ask impact]
    public let impactPxs: [String]?
    /// 24h base volume
    public let dayBaseVlm: String?
}

/// Combined perpetual metadata and asset contexts
public struct MetaAndAssetCtxs: Sendable {
    public let meta: Meta
    public let assetCtxs: [PerpAssetCtx]
}

// MARK: - Spot Market Types

/// EVM contract information (can be a string address or an object with address and decimals)
public enum EVMContract: Codable, Sendable {
    case address(String)
    case full(EvmContractInfo)

    public struct EvmContractInfo: Codable, Sendable {
        public let address: String
        public let evm_extra_wei_decimals: Int?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Try to decode as string first
        if let address = try? container.decode(String.self) {
            self = .address(address)
            return
        }
        // Try to decode as object
        let info = try container.decode(EvmContractInfo.self)
        self = .full(info)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .address(addr):
            try container.encode(addr)
        case let .full(info):
            try container.encode(info)
        }
    }

    /// Get the address regardless of format
    public var address: String {
        switch self {
        case let .address(addr): addr
        case let .full(info): info.address
        }
    }
}

/// Spot token information
public struct SpotTokenInfo: Codable, Sendable {
    /// Token name
    public let name: String
    /// Size decimals
    public let szDecimals: Int
    /// Wei decimals
    public let weiDecimals: Int
    /// Token index
    public let index: Int
    /// Token ID
    public let tokenId: String
    /// Whether this is the canonical token
    public let isCanonical: Bool
    /// EVM contract (optional, can be string or object)
    public let evmContract: EVMContract?
    /// Full name (optional)
    public let fullName: String?
    /// Deployer trading fee share (optional)
    public let deployerTradingFeeShare: String?
}

/// Spot asset (trading pair) information
public struct SpotAssetInfo: Codable, Sendable {
    /// Asset name (e.g., "PURR/USDC")
    public let name: String
    /// Token indices [base, quote]
    public let tokens: [Int]
    /// Asset index
    public let index: Int
    /// Whether this is the canonical pair
    public let isCanonical: Bool
}

/// Spot market metadata
public struct SpotMeta: Codable, Sendable {
    /// List of all spot trading pairs
    public let universe: [SpotAssetInfo]
    /// List of all tokens
    public let tokens: [SpotTokenInfo]
}

/// Spot asset context (real-time market data)
public struct SpotAssetCtx: Codable, Sendable {
    /// 24h notional volume
    public let dayNtlVlm: String
    /// Mark price
    public let markPx: String
    /// Mid price (can be null)
    public let midPx: String?
    /// Previous day's price
    public let prevDayPx: String
    /// Circulating supply
    public let circulatingSupply: String
    /// Coin name
    public let coin: String
}

/// Combined spot metadata and asset contexts
public struct SpotMetaAndAssetCtxs: Sendable {
    public let meta: SpotMeta
    public let assetCtxs: [SpotAssetCtx]
}

// MARK: - Order Book Types

/// Single level in the order book
public struct L2Level: Codable, Sendable {
    /// Price
    public let px: String
    /// Size
    public let sz: String
    /// Number of orders at this level
    public let n: Int
}

/// Order book snapshot
public struct L2Book: Codable, Sendable {
    /// Coin name
    public let coin: String
    /// Order book levels: [bids, asks]
    public let levels: [[L2Level]]
    /// Timestamp
    public let time: Int64
}

// MARK: - Candle Types

/// OHLCV candle data
public struct Candle: Codable, Sendable {
    /// Open time (milliseconds)
    public let t: Int64
    /// Open price
    public let o: String
    /// High price
    public let h: String
    /// Low price
    public let l: String
    /// Close price
    public let c: String
    /// Volume
    public let v: String
    /// Number of trades
    public let n: Int
}

/// Candle interval
public enum CandleInterval: String, Sendable, CaseIterable {
    case oneMinute = "1m"
    case threeMinutes = "3m"
    case fiveMinutes = "5m"
    case fifteenMinutes = "15m"
    case thirtyMinutes = "30m"
    case oneHour = "1h"
    case twoHours = "2h"
    case fourHours = "4h"
    case sixHours = "6h"
    case twelveHours = "12h"
    case oneDay = "1d"
    case oneWeek = "1w"
    case oneMonth = "1M"
}

// MARK: - All Mids

/// All mid prices response
public struct AllMids: Codable, Sendable {
    /// Map of coin name to mid price
    public let mids: [String: String]

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        mids = try container.decode([String: String].self)
    }
}

// MARK: - Funding

/// Funding history entry
public struct FundingHistoryEntry: Codable, Sendable {
    /// Coin name
    public let coin: String
    /// Funding rate
    public let fundingRate: String
    /// Premium
    public let premium: String
    /// Timestamp
    public let time: Int64
}

/// User funding entry
public struct UserFundingEntry: Codable, Sendable {
    /// Timestamp
    public let time: Int64
    /// Coin name
    public let coin: String
    /// USD value
    public let usdc: String
    /// Size
    public let szi: String
    /// Funding rate
    public let fundingRate: String
}
