import Foundation

// MARK: - User State (Perpetuals)

/// User perpetual account state
public struct UserState: Codable, Sendable {
    /// Asset positions
    public let assetPositions: [AssetPosition]
    /// Cross margin summary
    public let crossMarginSummary: MarginSummary
    /// Margin summary (same as cross margin summary)
    public let marginSummary: MarginSummary
    /// Withdrawable balance
    public let withdrawable: String
    /// Cross maintenance margin used
    public let crossMaintenanceMarginUsed: String
}

/// Asset position
public struct AssetPosition: Codable, Sendable {
    /// Position data
    public let position: Position
    /// Position type
    public let type: String
}

/// Position details
public struct Position: Codable, Sendable {
    /// Coin name
    public let coin: String
    /// Entry price (null if no position)
    public let entryPx: String?
    /// Leverage info
    public let leverage: Leverage
    /// Liquidation price (null if no position)
    public let liquidationPx: String?
    /// Margin used
    public let marginUsed: String
    /// Max trade sizes [buy, sell]
    public let maxTradeSzs: [String]
    /// Position value
    public let positionValue: String
    /// Return on equity
    public let returnOnEquity: String
    /// Size (negative for short)
    public let szi: String
    /// Unrealized PnL
    public let unrealizedPnl: String
    /// Cumulative funding
    public let cumFunding: CumulativeFunding?
}

/// Leverage configuration
public struct Leverage: Codable, Sendable {
    /// Leverage type: "cross" or "isolated"
    public let type: String
    /// Leverage value
    public let value: Int
    /// Raw USD for isolated margin (only present for isolated)
    public let rawUsd: String?
}

/// Cumulative funding
public struct CumulativeFunding: Codable, Sendable {
    /// All time funding
    public let allTime: String
    /// Since change funding
    public let sinceChange: String
    /// Since open funding
    public let sinceOpen: String
}

/// Margin summary
public struct MarginSummary: Codable, Sendable {
    /// Account value
    public let accountValue: String
    /// Total margin used
    public let totalMarginUsed: String
    /// Total notional position
    public let totalNtlPos: String
    /// Total raw USD
    public let totalRawUsd: String
}

// MARK: - User State (Spot)

/// User spot account state
public struct SpotUserState: Codable, Sendable {
    /// Token balances
    public let balances: [SpotBalance]
}

/// Spot token balance
public struct SpotBalance: Codable, Sendable {
    /// Token name
    public let coin: String
    /// Entry notional (cost basis)
    public let entryNtl: String?
    /// Available balance
    public let hold: String
    /// Token ID
    public let token: Int
    /// Total balance
    public let total: String
}

// MARK: - Open Orders

/// Open order
public struct OpenOrder: Codable, Sendable {
    /// Coin name
    public let coin: String
    /// Limit price
    public let limitPx: String
    /// Order ID
    public let oid: Int64
    /// Side: "A" (ask/sell) or "B" (bid/buy)
    public let side: String
    /// Size
    public let sz: String
    /// Timestamp
    public let timestamp: Int64
}

/// Frontend open order with additional info
public struct FrontendOpenOrder: Codable, Sendable {
    /// Coin name
    public let coin: String
    /// Whether this is a buy order
    public let isBuy: Bool?
    /// Limit price
    public let limitPx: String
    /// Order ID
    public let oid: Int64
    /// Order type
    public let orderType: String
    /// Original size
    public let origSz: String
    /// Whether this is reduce only
    public let reduceOnly: Bool
    /// Remaining size
    public let sz: String
    /// Timestamp
    public let timestamp: Int64
    /// Trigger condition (for trigger orders)
    public let triggerCondition: String?
    /// Trigger price (for trigger orders)
    public let triggerPx: String?
    /// Client order ID
    public let cloid: String?
}

// MARK: - Fills

/// Fill (trade execution)
public struct Fill: Codable, Sendable {
    /// Coin name
    public let coin: String
    /// Execution price
    public let px: String
    /// Size
    public let sz: String
    /// Side: "A" (ask/sell) or "B" (bid/buy)
    public let side: String
    /// Timestamp
    public let time: Int64
    /// Starting position
    public let startPosition: String
    /// Direction
    public let dir: String
    /// Closed PnL
    public let closedPnl: String
    /// Transaction hash
    public let hash: String
    /// Order ID
    public let oid: Int64
    /// Whether the order crossed the spread
    public let crossed: Bool
    /// Fee amount
    public let fee: String
    /// Trade ID
    public let tid: Int64
    /// Fee token
    public let feeToken: String
    /// Client order ID (optional)
    public let cloid: String?
    /// Liquidation info (optional)
    public let liquidation: LiquidationInfo?
    /// Builder info (optional)
    public let builderFee: String?
}

/// Liquidation info
public struct LiquidationInfo: Codable, Sendable {
    /// Liquidated user address
    public let liquidatedUser: String?
    /// Mark price at liquidation
    public let markPx: String?
    /// Method
    public let method: String?
}

// MARK: - User Fees

/// User fee rates
public struct UserFees: Codable, Sendable {
    /// Daily volume
    public let dailyUserVlm: [DailyVolume]
    /// Fee schedule
    public let feeSchedule: FeeSchedule
    /// User add rate (maker)
    public let userAddRate: String
    /// User cross rate (taker for cross)
    public let userCrossRate: String
    /// Active referral discount
    public let activeReferralDiscount: String
}

/// Daily volume entry
public struct DailyVolume: Codable, Sendable {
    /// Date
    public let date: String
    /// User cross volume
    public let userCross: String
    /// User add volume
    public let userAdd: String
    /// Exchange volume
    public let exchange: String
}

/// Fee schedule
public struct FeeSchedule: Codable, Sendable {
    /// Fee tiers by category (vip, mm, etc.)
    public let tiers: FeeTiers?
    /// Cross rate
    public let cross: String?
    /// Add rate (maker)
    public let add: String?
    /// Spot cross rate
    public let spotCross: String?
    /// Spot add rate
    public let spotAdd: String?
    /// Referrer
    public let referrer: String?
}

/// Fee tiers by category
public struct FeeTiers: Codable, Sendable {
    /// VIP tiers
    public let vip: [FeeTier]?
    /// Market maker tiers
    public let mm: [MMFeeTier]?
}

/// VIP fee tier
public struct FeeTier: Codable, Sendable {
    /// Notional cutoff
    public let ntlCutoff: String?
    /// Cross rate
    public let cross: String?
    /// Add rate
    public let add: String?
    /// Spot cross rate
    public let spotCross: String?
    /// Spot add rate
    public let spotAdd: String?
}

/// Market maker fee tier
public struct MMFeeTier: Codable, Sendable {
    /// Maker fraction cutoff
    public let makerFractionCutoff: String?
    /// Add rate
    public let add: String?
}

// MARK: - Order Status

/// Order status response
public struct OrderStatus: Codable, Sendable {
    /// Order details (null if not found)
    public let order: OrderDetails?
    /// Status: "order", "filled", "canceled", etc.
    public let status: String
    /// Status timestamp
    public let statusTimestamp: Int64?
}

/// Order details
public struct OrderDetails: Codable, Sendable {
    /// Coin name
    public let coin: String
    /// Whether this is a buy
    public let isBuy: Bool?
    /// Limit price
    public let limitPx: String
    /// Order ID
    public let oid: Int64
    /// Order type
    public let orderType: String
    /// Original size
    public let origSz: String
    /// Reduce only
    public let reduceOnly: Bool
    /// Remaining size
    public let sz: String
    /// Timestamp
    public let timestamp: Int64
    /// Trigger condition
    public let triggerCondition: String?
    /// Trigger price
    public let triggerPx: String?
    /// Client order ID
    public let cloid: String?
    /// Children orders (for advanced order types)
    public let children: [Self]?
}

// MARK: - Rate Limit

/// User rate limit info
public struct UserRateLimit: Codable, Sendable {
    /// Cumulative volume
    public let cumVlm: String
    /// Number of requests in window
    public let nRequestsUsed: Int
    /// Rate limit window
    public let rateLimitWindow: String?
    /// Rate limit used
    public let rateLimitUsed: String?
}

// MARK: - Referral

/// Referral state
public struct ReferralState: Codable, Sendable {
    /// Referred by
    public let referredBy: ReferredBy?
    /// Cumulative volume
    public let cumVlm: String
    /// Unclaimed rewards
    public let unclaimedRewards: String
    /// Claimed rewards
    public let claimedRewards: String
    /// Builder info
    public let builderState: BuilderState?
    /// Referrer state
    public let referrerState: ReferrerState?
    /// Referral code
    public let code: String?
}

/// Referred by info
public struct ReferredBy: Codable, Sendable {
    /// Referrer address
    public let referrer: String
    /// Referral code
    public let code: String
}

/// Builder state
public struct BuilderState: Codable, Sendable {
    /// Max fee rate
    public let maxFeeRate: String?
}

/// Referrer state
public struct ReferrerState: Codable, Sendable {
    /// Required
    public let required: Bool?
    /// Stage
    public let stage: String?
    /// Data
    public let data: ReferrerData?
}

/// Referrer data
public struct ReferrerData: Codable, Sendable {
    /// Referred count
    public let referredCnt: Int?
    /// Referred volume
    public let referredVlm: String?
    /// Rewards earned
    public let rewardsEarned: String?
}

// MARK: - Staking

/// Staking summary
public struct StakingSummary: Codable, Sendable {
    /// Delegated amount
    public let delegated: String
    /// Undelegated amount
    public let undelegated: String
    /// Total pending withdrawal
    public let totalPendingWithdrawal: String
    /// Number of pending withdrawals
    public let nPendingWithdrawals: Int
}

/// Staking delegation
public struct StakingDelegation: Codable, Sendable {
    /// Validator address
    public let validator: String
    /// Amount delegated
    public let amount: String
    /// Locked until timestamp
    public let lockedUntilTimestamp: Int64?
}

/// Staking reward entry
public struct StakingReward: Codable, Sendable {
    /// Timestamp
    public let time: Int64
    /// Source
    public let source: String
    /// Total amount
    public let totalAmount: String
}

// MARK: - Sub Accounts

/// Sub account info
public struct SubAccount: Codable, Sendable {
    /// Sub account address
    public let subAccountUser: String
    /// Sub account name
    public let name: String
    /// Clearing house state
    public let clearinghouseState: UserState?
    /// Spot clearing house state
    public let spotState: SpotUserState?
}

// MARK: - Portfolio

/// Portfolio response
public struct Portfolio: Codable, Sendable {
    /// Portfolio
    public let portfolio: PortfolioData
}

/// Portfolio data
public struct PortfolioData: Codable, Sendable {
    /// Account value
    public let accountValue: String
    /// Total notional position
    public let totalNtlPos: String
    /// Unrealized PnL
    public let unrealizedPnl: String
    /// Realized PnL
    public let realizedPnl: String
    /// Funding
    public let funding: String
}

// MARK: - Historical Order

/// Historical order entry
public struct HistoricalOrder: Codable, Sendable {
    /// Order details
    public let order: OrderDetails?
    /// Order status
    public let status: String
    /// Status timestamp
    public let statusTimestamp: Int64
}

// MARK: - Ledger Updates

/// Ledger update entry
public struct LedgerUpdate: Codable, Sendable {
    /// Delta information
    public let delta: LedgerDelta?
    /// Transaction hash
    public let hash: String
    /// Timestamp
    public let time: Int64
}

/// Ledger delta
public struct LedgerDelta: Codable, Sendable {
    /// Type of update
    public let type: String?
    /// Amount
    public let amount: String?
    /// Coin
    public let coin: String?
    /// Fee
    public let fee: String?
    /// Additional data as JSON
    public let extra: [String: String]?
}

// MARK: - User Funding

/// User funding entry
public struct UserFunding: Codable, Sendable {
    /// Funding delta
    public let delta: FundingDelta?
    /// Transaction hash
    public let hash: String
    /// Timestamp
    public let time: Int64
}

/// Funding delta
public struct FundingDelta: Codable, Sendable {
    /// Coin name
    public let coin: String?
    /// Funding rate
    public let fundingRate: String?
    /// Size
    public let szi: String?
    /// Type (should be "funding")
    public let type: String
    /// USDC amount
    public let usdc: String?
}

// MARK: - TWAP Slice Fill

/// TWAP slice fill
public struct TwapSliceFill: Codable, Sendable {
    /// Coin name
    public let coin: String?
    /// Price
    public let px: String?
    /// Size
    public let sz: String?
    /// Side
    public let side: String?
    /// Timestamp
    public let time: Int64?
    /// Fee
    public let fee: String?
    /// Trade ID
    public let tid: Int64?
}

// MARK: - Vault Equity

/// Vault equity
public struct VaultEquity: Codable, Sendable {
    /// Vault address
    public let vaultAddress: String?
    /// Vault (alternative field name)
    public let vault: String?
    /// Equity amount
    public let equity: String?
}

// MARK: - User Role

/// User role information
public struct UserRole: Codable, Sendable {
    /// Role type
    public let role: String?
    /// Account type
    public let type: String?
    /// Account address
    public let account: String?
}

// MARK: - Delegator History

/// Delegator history entry
public struct DelegatorHistoryEntry: Codable, Sendable {
    /// Delta information
    public let delta: DelegatorDelta?
    /// Transaction hash
    public let hash: String
    /// Timestamp
    public let time: Int64
}

/// Delegator delta
public struct DelegatorDelta: Codable, Sendable {
    /// Type of event
    public let type: String?
    /// Amount
    public let amount: String?
    /// Validator
    public let validator: String?
}

// MARK: - Extra Agent

/// Extra agent information
public struct ExtraAgent: Codable, Sendable {
    /// Agent name
    public let name: String?
    /// Agent address
    public let address: String?
    /// Valid until timestamp
    public let validUntil: Int64?
}
