import Foundation

// MARK: - Subscription Types

/// WebSocket subscription types
/// Reference: Python SDK hyperliquid/utils/types.py
public enum Subscription: Sendable, Encodable {
    /// Subscribe to all mid prices
    case allMids
    /// Subscribe to best bid/offer for a coin
    case bbo(coin: String)
    /// Subscribe to L2 order book for a coin
    case l2Book(coin: String)
    /// Subscribe to trades for a coin
    case trades(coin: String)
    /// Subscribe to user events (fills, etc.)
    case userEvents(user: String)
    /// Subscribe to user fills
    case userFills(user: String)
    /// Subscribe to candle data
    case candle(coin: String, interval: String)
    /// Subscribe to order updates
    case orderUpdates(user: String)
    /// Subscribe to user funding payments
    case userFundings(user: String)
    /// Subscribe to non-funding ledger updates
    case userNonFundingLedgerUpdates(user: String)
    /// Subscribe to web data
    case webData2(user: String)
    /// Subscribe to active asset context
    case activeAssetCtx(coin: String)
    /// Subscribe to active asset data for a user
    case activeAssetData(user: String, coin: String)

    /// Convert to dictionary for JSON serialization
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(asDictionary)
    }

    /// Convert to dictionary representation
    public var asDictionary: [String: String] {
        switch self {
        case .allMids:
            ["type": "allMids"]
        case .bbo(let coin):
            ["type": "bbo", "coin": coin]
        case .l2Book(let coin):
            ["type": "l2Book", "coin": coin]
        case .trades(let coin):
            ["type": "trades", "coin": coin]
        case .userEvents(let user):
            ["type": "userEvents", "user": user]
        case .userFills(let user):
            ["type": "userFills", "user": user]
        case .candle(let coin, let interval):
            ["type": "candle", "coin": coin, "interval": interval]
        case .orderUpdates(let user):
            ["type": "orderUpdates", "user": user]
        case .userFundings(let user):
            ["type": "userFundings", "user": user]
        case .userNonFundingLedgerUpdates(let user):
            ["type": "userNonFundingLedgerUpdates", "user": user]
        case .webData2(let user):
            ["type": "webData2", "user": user]
        case .activeAssetCtx(let coin):
            ["type": "activeAssetCtx", "coin": coin]
        case .activeAssetData(let user, let coin):
            ["type": "activeAssetData", "user": user, "coin": coin]
        }
    }

    /// Generate unique identifier for subscription
    /// Reference: Python SDK websocket_manager.py:subscription_to_identifier
    public var identifier: String {
        switch self {
        case .allMids:
            "allMids"
        case .bbo(let coin):
            "bbo:\(coin.lowercased())"
        case .l2Book(let coin):
            "l2Book:\(coin.lowercased())"
        case .trades(let coin):
            "trades:\(coin.lowercased())"
        case .userEvents:
            "userEvents"
        case .userFills(let user):
            "userFills:\(user.lowercased())"
        case .candle(let coin, let interval):
            "candle:\(coin.lowercased()),\(interval)"
        case .orderUpdates:
            "orderUpdates"
        case .userFundings(let user):
            "userFundings:\(user.lowercased())"
        case .userNonFundingLedgerUpdates(let user):
            "userNonFundingLedgerUpdates:\(user.lowercased())"
        case .webData2(let user):
            "webData2:\(user.lowercased())"
        case .activeAssetCtx(let coin):
            "activeAssetCtx:\(coin.lowercased())"
        case .activeAssetData(let user, let coin):
            "activeAssetData:\(coin.lowercased()),\(user.lowercased())"
        }
    }
}

// MARK: - WebSocket Message Types

/// WebSocket channel types
public enum WsChannel: String, Codable, Sendable {
    case pong
    case allMids
    case l2Book
    case bbo
    case trades
    case user
    case userFills
    case candle
    case orderUpdates
    case userFundings
    case userNonFundingLedgerUpdates
    case webData2
    case activeAssetCtx
    case activeSpotAssetCtx
    case activeAssetData
    case subscriptionResponse
    case error
}

/// Base WebSocket message
public struct WsMessage: Codable, Sendable {
    public let channel: String
    public let data: WsMessageData?

    public init(channel: String, data: WsMessageData?) {
        self.channel = channel
        self.data = data
    }
}

/// WebSocket message data - using enum to handle different types
public enum WsMessageData: Codable, Sendable {
    case allMids(AllMidsData)
    case l2Book(L2BookData)
    case bbo(BboData)
    case trades([TradeData])
    case userEvents(UserEventsData)
    case userFills(UserFillsData)
    case candle(CandleData)
    case orderUpdates([OrderUpdateData])
    case userFundings(UserFundingsData)
    case userNonFundingLedgerUpdates(UserNonFundingLedgerUpdatesData)
    case activeAssetCtx(ActiveAssetCtxData)
    case activeSpotAssetCtx(ActiveSpotAssetCtxData)
    case activeAssetData(ActiveAssetDataMessage)
    case raw(AnyCodable)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Try to decode as raw JSON first
        self = try .raw(container.decode(AnyCodable.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .allMids(let data):
            try container.encode(data)
        case .l2Book(let data):
            try container.encode(data)
        case .bbo(let data):
            try container.encode(data)
        case .trades(let data):
            try container.encode(data)
        case .userEvents(let data):
            try container.encode(data)
        case .userFills(let data):
            try container.encode(data)
        case .candle(let data):
            try container.encode(data)
        case .orderUpdates(let data):
            try container.encode(data)
        case .userFundings(let data):
            try container.encode(data)
        case .userNonFundingLedgerUpdates(let data):
            try container.encode(data)
        case .activeAssetCtx(let data):
            try container.encode(data)
        case .activeSpotAssetCtx(let data):
            try container.encode(data)
        case .activeAssetData(let data):
            try container.encode(data)
        case .raw(let data):
            try container.encode(data)
        }
    }
}

/// Helper for encoding/decoding arbitrary JSON
/// Using @unchecked Sendable because the underlying values are immutable after initialization
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([Self].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: Self].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode AnyCodable")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { Self($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { Self($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Cannot encode AnyCodable")
            )
        }
    }
}

// MARK: - Specific Data Types

/// All mids data
public struct AllMidsData: Codable, Sendable {
    public let mids: [String: String]

    public init(mids: [String: String]) {
        self.mids = mids
    }
}

/// L2 book data
public struct L2BookData: Codable, Sendable {
    public let coin: String
    public let levels: [[WsL2Level]]
    public let time: Int64

    public init(coin: String, levels: [[WsL2Level]], time: Int64) {
        self.coin = coin
        self.levels = levels
        self.time = time
    }
}

/// WebSocket L2 level (same structure as L2Level but for WS)
public struct WsL2Level: Codable, Sendable {
    public let px: String
    public let sz: String
    public let n: Int

    public init(px: String, sz: String, n: Int) {
        self.px = px
        self.sz = sz
        self.n = n
    }
}

/// BBO (Best Bid/Offer) data
public struct BboData: Codable, Sendable {
    public let coin: String
    public let time: Int64
    public let bbo: [WsL2Level?]

    public init(coin: String, time: Int64, bbo: [WsL2Level?]) {
        self.coin = coin
        self.time = time
        self.bbo = bbo
    }
}

/// Trade data
public struct TradeData: Codable, Sendable {
    public let coin: String
    public let side: String
    public let px: String
    public let sz: String
    public let hash: String
    public let time: Int64
    public let tid: Int64?

    public init(coin: String, side: String, px: String, sz: String, hash: String, time: Int64, tid: Int64? = nil) {
        self.coin = coin
        self.side = side
        self.px = px
        self.sz = sz
        self.hash = hash
        self.time = time
        self.tid = tid
    }
}

/// User events data
public struct UserEventsData: Codable, Sendable {
    public let fills: [WsFill]?
    public let liquidation: WsLiquidation?
    public let nonUserCancel: [WsNonUserCancel]?

    public init(fills: [WsFill]? = nil, liquidation: WsLiquidation? = nil, nonUserCancel: [WsNonUserCancel]? = nil) {
        self.fills = fills
        self.liquidation = liquidation
        self.nonUserCancel = nonUserCancel
    }
}

/// WebSocket fill data
public struct WsFill: Codable, Sendable {
    public let coin: String
    public let px: String
    public let sz: String
    public let side: String
    public let time: Int64
    public let startPosition: String
    public let dir: String
    public let closedPnl: String
    public let hash: String
    public let oid: Int64
    public let crossed: Bool
    public let fee: String
    public let tid: Int64
    public let feeToken: String?
    public let cloid: String?

    public init(
        coin: String,
        px: String,
        sz: String,
        side: String,
        time: Int64,
        startPosition: String,
        dir: String,
        closedPnl: String,
        hash: String,
        oid: Int64,
        crossed: Bool,
        fee: String,
        tid: Int64,
        feeToken: String? = nil,
        cloid: String? = nil
    ) {
        self.coin = coin
        self.px = px
        self.sz = sz
        self.side = side
        self.time = time
        self.startPosition = startPosition
        self.dir = dir
        self.closedPnl = closedPnl
        self.hash = hash
        self.oid = oid
        self.crossed = crossed
        self.fee = fee
        self.tid = tid
        self.feeToken = feeToken
        self.cloid = cloid
    }
}

/// WebSocket liquidation data
public struct WsLiquidation: Codable, Sendable {
    public let lid: Int64
    public let liquidator: String
    public let liquidatedUser: String
    public let liquidatedNtlPos: String
    public let liquidatedAccountValue: String

    enum CodingKeys: String, CodingKey {
        case lid, liquidator
        case liquidatedUser = "liquidated_user"
        case liquidatedNtlPos = "liquidated_ntl_pos"
        case liquidatedAccountValue = "liquidated_account_value"
    }

    public init(
        lid: Int64,
        liquidator: String,
        liquidatedUser: String,
        liquidatedNtlPos: String,
        liquidatedAccountValue: String
    ) {
        self.lid = lid
        self.liquidator = liquidator
        self.liquidatedUser = liquidatedUser
        self.liquidatedNtlPos = liquidatedNtlPos
        self.liquidatedAccountValue = liquidatedAccountValue
    }
}

/// WebSocket non-user cancel data
public struct WsNonUserCancel: Codable, Sendable {
    public let coin: String
    public let oid: Int64

    public init(coin: String, oid: Int64) {
        self.coin = coin
        self.oid = oid
    }
}

/// User fills data
public struct UserFillsData: Codable, Sendable {
    public let user: String
    public let isSnapshot: Bool
    public let fills: [WsFill]

    public init(user: String, isSnapshot: Bool, fills: [WsFill]) {
        self.user = user
        self.isSnapshot = isSnapshot
        self.fills = fills
    }
}

/// Candle data
public struct CandleData: Codable, Sendable {
    public let openTime: Int64
    public let closeTime: Int64
    public let symbol: String
    public let interval: String
    public let open: String
    public let close: String
    public let high: String
    public let low: String
    public let volume: String
    public let numTrades: Int

    enum CodingKeys: String, CodingKey {
        case openTime = "t"
        case closeTime = "T"
        case symbol = "s"
        case interval = "i"
        case open = "o"
        case close = "c"
        case high = "h"
        case low = "l"
        case volume = "v"
        case numTrades = "n"
    }

    public init(
        openTime: Int64,
        closeTime: Int64,
        symbol: String,
        interval: String,
        open: String,
        close: String,
        high: String,
        low: String,
        volume: String,
        numTrades: Int
    ) {
        self.openTime = openTime
        self.closeTime = closeTime
        self.symbol = symbol
        self.interval = interval
        self.open = open
        self.close = close
        self.high = high
        self.low = low
        self.volume = volume
        self.numTrades = numTrades
    }
}

/// Order update data
public struct OrderUpdateData: Codable, Sendable {
    public let order: WsOrder
    public let status: String
    public let statusTimestamp: Int64

    public init(order: WsOrder, status: String, statusTimestamp: Int64) {
        self.order = order
        self.status = status
        self.statusTimestamp = statusTimestamp
    }
}

/// WebSocket order data
public struct WsOrder: Codable, Sendable {
    public let coin: String
    public let side: String
    public let limitPx: String
    public let sz: String
    public let oid: Int64
    public let timestamp: Int64
    public let origSz: String
    public let cloid: String?

    public init(
        coin: String,
        side: String,
        limitPx: String,
        sz: String,
        oid: Int64,
        timestamp: Int64,
        origSz: String,
        cloid: String? = nil
    ) {
        self.coin = coin
        self.side = side
        self.limitPx = limitPx
        self.sz = sz
        self.oid = oid
        self.timestamp = timestamp
        self.origSz = origSz
        self.cloid = cloid
    }
}

/// User fundings data
public struct UserFundingsData: Codable, Sendable {
    public let user: String
    public let isSnapshot: Bool
    public let fundings: [WsFunding]

    public init(user: String, isSnapshot: Bool, fundings: [WsFunding]) {
        self.user = user
        self.isSnapshot = isSnapshot
        self.fundings = fundings
    }
}

/// WebSocket funding data
public struct WsFunding: Codable, Sendable {
    public let time: Int64
    public let coin: String
    public let usdc: String
    public let szi: String
    public let fundingRate: String

    public init(time: Int64, coin: String, usdc: String, szi: String, fundingRate: String) {
        self.time = time
        self.coin = coin
        self.usdc = usdc
        self.szi = szi
        self.fundingRate = fundingRate
    }
}

/// User non-funding ledger updates data
public struct UserNonFundingLedgerUpdatesData: Codable, Sendable {
    public let user: String
    public let isSnapshot: Bool
    public let nonFundingLedgerUpdates: [AnyCodable]

    public init(user: String, isSnapshot: Bool, nonFundingLedgerUpdates: [AnyCodable]) {
        self.user = user
        self.isSnapshot = isSnapshot
        self.nonFundingLedgerUpdates = nonFundingLedgerUpdates
    }
}

/// Active asset context data
public struct ActiveAssetCtxData: Codable, Sendable {
    public let coin: String
    public let ctx: PerpAssetCtx

    public init(coin: String, ctx: PerpAssetCtx) {
        self.coin = coin
        self.ctx = ctx
    }
}

/// Active spot asset context data
public struct ActiveSpotAssetCtxData: Codable, Sendable {
    public let coin: String
    public let ctx: SpotAssetCtx

    public init(coin: String, ctx: SpotAssetCtx) {
        self.coin = coin
        self.ctx = ctx
    }
}

/// Active asset data message
public struct ActiveAssetDataMessage: Codable, Sendable {
    public let user: String
    public let coin: String
    public let leverage: LeverageInfo
    public let maxTradeSzs: [String]
    public let availableToTrade: [String]
    public let markPx: String

    public init(
        user: String,
        coin: String,
        leverage: LeverageInfo,
        maxTradeSzs: [String],
        availableToTrade: [String],
        markPx: String
    ) {
        self.user = user
        self.coin = coin
        self.leverage = leverage
        self.maxTradeSzs = maxTradeSzs
        self.availableToTrade = availableToTrade
        self.markPx = markPx
    }
}

/// Leverage info for WebSocket
public struct LeverageInfo: Codable, Sendable {
    public let type: String
    public let value: Int
    public let rawUsd: String?

    public init(type: String, value: Int, rawUsd: String? = nil) {
        self.type = type
        self.value = value
        self.rawUsd = rawUsd
    }
}
