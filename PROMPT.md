# HyperliquidSwift SDK - LLM Reference

This document provides a comprehensive API reference for LLMs to assist users with the HyperliquidSwift SDK.

## Overview

HyperliquidSwift is a native Swift SDK for the [Hyperliquid](https://hyperliquid.xyz) decentralized exchange. It provides:

- **InfoAPI**: Read-only market data and account queries
- **ExchangeAPI**: Trading operations requiring wallet signatures
- **WebSocket**: Real-time market data subscriptions

## Requirements

- iOS 18.0+ / macOS 15.0+
- Swift 6.0+

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/chicunic/hyperliquid-swift.git", from: "0.1.0")
]
```

---

## Quick Start

### Read-Only Access (No Wallet)

```swift
import HyperliquidSwift

let client = HyperliquidClient(network: .mainnet)
let info = try await client.infoAPI()

// Get all mid prices
let mids = try await info.allMids()

// Get user state
let state = try await info.userState(address: "0x...")
```

### Trading Access (With Wallet)

```swift
import HyperliquidSwift

let client = try HyperliquidClient(network: .mainnet, privateKey: "0x...")
let exchange = try await client.exchangeAPI()

// Place a limit order
let response = try await exchange.order(
    coin: "ETH",
    isBuy: true,
    sz: Decimal(string: "0.1")!,
    limitPx: Decimal(string: "3000")!,
    orderType: .limit(LimitOrderType(tif: .gtc)),
    reduceOnly: false
)
```

---

## HyperliquidClient

Main entry point for the SDK.

### Initialization

```swift
// Read-only (no signer)
let client = HyperliquidClient(network: .mainnet)

// With private key
let client = try HyperliquidClient(network: .mainnet, privateKey: "0x...")

// With custom signer (PrivateKeySigner)
let signer = try PrivateKeySigner(privateKeyHex: "0x...")
let client = HyperliquidClient(network: .mainnet, signer: signer)

// With EIP712Signer (for external wallets like Privy, WalletConnect)
let walletSigner = MyWalletSigner()  // implements EIP712Signer
let exchange = try await ExchangeAPI(eip712Signer: walletSigner, network: .mainnet)

// Convenience constructors
let mainnet = HyperliquidClient.mainnet
let testnet = HyperliquidClient.testnet
let mainnetWithKey = try HyperliquidClient.mainnet(privateKey: "0x...")
```

### Properties & Methods

| Method                                                                  | Description                          |
| ----------------------------------------------------------------------- | ------------------------------------ |
| `infoAPI() async throws -> InfoAPI`                                     | Create InfoAPI with metadata loading |
| `simpleInfoAPI() -> InfoAPI`                                            | Create InfoAPI without metadata      |
| `exchangeAPI(vaultAddress:accountAddress:) async throws -> ExchangeAPI` | Create ExchangeAPI (requires signer) |
| `walletAddress: String?`                                                | Get configured wallet address        |

---

## InfoAPI

Actor for read-only queries. All methods are `async throws`.

### Market Data

| Method                                              | Parameters                 | Returns                 | Description              |
| --------------------------------------------------- | -------------------------- | ----------------------- | ------------------------ |
| `allMids(dex:)`                                     | `dex: String = ""`         | `[String: String]`      | All mid prices           |
| `meta(dex:)`                                        | `dex: String = ""`         | `Meta`                  | Perpetual metadata       |
| `spotMeta()`                                        | -                          | `SpotMeta`              | Spot metadata            |
| `metaAndAssetCtxs()`                                | -                          | `MetaAndAssetCtxs`      | Perp metadata + contexts |
| `spotMetaAndAssetCtxs()`                            | -                          | `SpotMetaAndAssetCtxs`  | Spot metadata + contexts |
| `l2Snapshot(name:)`                                 | `name: String`             | `L2Book`                | Order book snapshot      |
| `candlesSnapshot(name:interval:startTime:endTime:)` | coin, interval, timestamps | `[Candle]`              | OHLCV candles            |
| `fundingHistory(name:startTime:endTime:)`           | coin, timestamps           | `[FundingHistoryEntry]` | Funding rate history     |

### User Account

| Method                                                        | Parameters            | Returns               | Description                 |
| ------------------------------------------------------------- | --------------------- | --------------------- | --------------------------- |
| `userState(address:dex:)`                                     | address, dex          | `UserState`           | Perp account state          |
| `spotUserState(address:)`                                     | address               | `SpotUserState`       | Spot account state          |
| `openOrders(address:dex:)`                                    | address, dex          | `[OpenOrder]`         | Open orders                 |
| `frontendOpenOrders(address:dex:)`                            | address, dex          | `[FrontendOpenOrder]` | Open orders with extra info |
| `userFills(address:)`                                         | address               | `[Fill]`              | Trade history               |
| `userFillsByTime(address:startTime:endTime:aggregateByTime:)` | address, timestamps   | `[Fill]`              | Fills by time range         |
| `userFundingHistory(user:startTime:endTime:)`                 | user, timestamps      | `[UserFunding]`       | User funding history        |
| `userFees(address:)`                                          | address               | `UserFees`            | Fee rates and volume        |
| `queryOrderByOid(user:oid:)`                                  | user, order ID        | `OrderStatus`         | Query order by ID           |
| `queryOrderByCloid(user:cloid:)`                              | user, client order ID | `OrderStatus`         | Query order by CLOID        |
| `historicalOrders(user:)`                                     | user                  | `[HistoricalOrder]`   | Order history               |
| `userNonFundingLedgerUpdates(user:startTime:endTime:)`        | user, timestamps      | `[LedgerUpdate]`      | Ledger updates              |
| `userTwapSliceFills(user:)`                                   | user                  | `[TwapSliceFill]`     | TWAP fills                  |
| `userVaultEquities(user:)`                                    | user                  | `[VaultEquity]`       | Vault positions             |
| `userRole(user:)`                                             | user                  | `UserRole`            | Account type info           |
| `userRateLimit(user:)`                                        | user                  | `UserRateLimit`       | Rate limit status           |

### Staking

| Method                             | Parameters | Returns                   | Description        |
| ---------------------------------- | ---------- | ------------------------- | ------------------ |
| `userStakingSummary(address:)`     | address    | `StakingSummary`          | Staking summary    |
| `delegatorSummary(address:)`       | address    | `StakingSummary`          | Alias for above    |
| `userStakingDelegations(address:)` | address    | `[StakingDelegation]`     | Delegation list    |
| `userStakingRewards(address:)`     | address    | `[StakingReward]`         | Reward history     |
| `delegatorHistory(user:)`          | user       | `[DelegatorHistoryEntry]` | Delegation history |

### Other

| Method                      | Parameters | Returns         | Description                   |
| --------------------------- | ---------- | --------------- | ----------------------------- |
| `queryReferralState(user:)` | user       | `ReferralState` | Referral info                 |
| `querySubAccounts(user:)`   | user       | `[SubAccount]`  | Sub accounts                  |
| `extraAgents(user:)`        | user       | `[ExtraAgent]`  | Approved agents               |
| `nameToAsset(name:)`        | name       | `Int?`          | Convert coin name to asset ID |

### WebSocket Subscriptions

```swift
// Subscribe to order book updates
let subId = try await info.subscribe(.l2Book(coin: "ETH")) { message in
    if case let .l2Book(data) = message {
        print("Book update: \(data)")
    }
}

// Unsubscribe
try await info.unsubscribe(.l2Book(coin: "ETH"), subscriptionId: subId)

// Disconnect
await info.disconnectWebSocket()
```

**Subscription Types:**

- `.allMids` - All mid prices
- `.l2Book(coin:)` - Order book
- `.trades(coin:)` - Trades
- `.candle(coin:interval:)` - Candles
- `.orderUpdates(user:)` - Order updates
- `.userFills(user:)` - User fills
- `.userFundings(user:)` - User funding
- `.userNonFundingLedgerUpdates(user:)` - Ledger updates

---

## ExchangeAPI

Actor for trading operations. Requires signer. All methods are `async throws` and return `Data` (raw JSON response).

### Order Operations

| Method                                                               | Parameters                          | Description              |
| -------------------------------------------------------------------- | ----------------------------------- | ------------------------ |
| `order(coin:isBuy:sz:limitPx:orderType:reduceOnly:cloid:builder:)`   | order params                        | Place single order       |
| `bulkOrders(orders:builder:grouping:)`                               | `[OrderRequest]`, builder, grouping | Place multiple orders    |
| `modifyOrder(oid:coin:isBuy:sz:limitPx:orderType:reduceOnly:cloid:)` | order ID + new params               | Modify order             |
| `bulkModifyOrders(modifies:)`                                        | `[ModifyRequest]`                   | Modify multiple orders   |
| `cancel(coin:oid:)`                                                  | coin, order ID                      | Cancel order             |
| `bulkCancel(cancels:)`                                               | `[CancelRequest]`                   | Cancel multiple orders   |
| `cancelByCloid(coin:cloid:)`                                         | coin, client order ID               | Cancel by CLOID          |
| `bulkCancelByCloid(cancels:)`                                        | `[CancelByCloidRequest]`            | Cancel multiple by CLOID |
| `scheduleCancel(time:)`                                              | timestamp or nil                    | Schedule cancel all      |

### Market Orders (Convenience)

| Method                                                 | Parameters                            | Description           |
| ------------------------------------------------------ | ------------------------------------- | --------------------- |
| `marketOpen(coin:isBuy:sz:px:slippage:cloid:builder:)` | coin, direction, size, optional price | Open market position  |
| `marketClose(coin:sz:px:slippage:cloid:builder:)`      | coin, optional size, optional price   | Close market position |

### Account Operations

| Method                                   | Parameters                     | Description            |
| ---------------------------------------- | ------------------------------ | ---------------------- |
| `updateLeverage(leverage:coin:isCross:)` | leverage, coin, cross/isolated | Update leverage        |
| `updateIsolatedMargin(amount:coin:)`     | amount, coin                   | Adjust isolated margin |
| `setReferrer(code:)`                     | referral code                  | Set referrer           |
| `createSubAccount(name:)`                | name                           | Create sub-account     |

### Transfer Operations

| Method                                                           | Parameters                            | Description                |
| ---------------------------------------------------------------- | ------------------------------------- | -------------------------- |
| `usdTransfer(amount:destination:)`                               | amount, address                       | Transfer USDC              |
| `spotTransfer(amount:destination:token:)`                        | amount, address, token                | Transfer spot token        |
| `usdClassTransfer(amount:toPerp:)`                               | amount, direction                     | Transfer between perp/spot |
| `subAccountTransfer(subAccountUser:isDeposit:usd:)`              | sub-account, direction, amount        | Sub-account USD transfer   |
| `subAccountSpotTransfer(subAccountUser:isDeposit:token:amount:)` | sub-account, direction, token, amount | Sub-account spot transfer  |
| `vaultUsdTransfer(vaultAddress:isDeposit:usd:)`                  | vault, direction, amount              | Vault USD transfer         |
| `withdrawFromBridge(amount:destination:)`                        | amount, address                       | Bridge withdrawal          |
| `sendAsset(destination:sourceDex:destinationDex:token:amount:)`  | addresses, token, amount              | Cross-DEX transfer         |

### Staking & Agent Operations

| Method                                       | Parameters                   | Description           |
| -------------------------------------------- | ---------------------------- | --------------------- |
| `tokenDelegate(validator:wei:isUndelegate:)` | validator, amount, direction | Delegate/undelegate   |
| `approveAgent(agentAddress:agentName:)`      | agent address, optional name | Approve trading agent |
| `approveBuilderFee(builder:maxFeeRate:)`     | builder address, max fee     | Approve builder fee   |

---

## Core Types

### Order Types

```swift
// Limit order
let orderType: OrderType = .limit(LimitOrderType(tif: .gtc))

// Trigger order (TP/SL)
let orderType: OrderType = .trigger(TriggerOrderType(
    triggerPx: Decimal(string: "3500")!,
    isMarket: true,
    tpsl: .takeProfit
))
```

### Time in Force

```swift
enum TimeInForce: String {
    case gtc = "Gtc"  // Good 'til cancelled
    case ioc = "Ioc"  // Immediate or cancel
    case alo = "Alo"  // Add liquidity only (maker)
}
```

### Client Order ID (Cloid)

```swift
// Create from hex string
let cloid = Cloid(rawValue: "0x00000000000000000000000000000001")

// Generate random
let cloid = Cloid.random()

// Get hex string
cloid.hexString  // "0x..."
cloid.toRaw()    // "0x..."
```

### Order Requests

```swift
// Order request
let order = OrderRequest(
    coin: "ETH",
    isBuy: true,
    sz: Decimal(string: "0.1")!,
    limitPx: Decimal(string: "3000")!,
    orderType: .limit(LimitOrderType(tif: .gtc)),
    reduceOnly: false,
    cloid: Cloid.random()
)

// Cancel request
let cancel = CancelRequest(coin: "ETH", oid: 123456)

// Cancel by CLOID
let cancelByCloid = CancelByCloidRequest(coin: "ETH", cloid: cloid)

// Modify request
let modify = ModifyRequest(
    oidOrCloid: .oid(123456),
    order: order
)
```

### Builder Info (Fee Sharing)

```swift
let builder = BuilderInfo(
    address: "0x...",
    fee: 10  // 1 basis point (10 = 0.1%)
)
```

### Order Grouping

```swift
enum OrderGrouping: String {
    case na            // No grouping
    case normalTpsl    // TP/SL grouping
    case positionTpsl  // Position TP/SL grouping
}
```

---

## Response Types

### UserState (Perpetual Account)

```swift
struct UserState {
    let assetPositions: [AssetPosition]
    let crossMarginSummary: MarginSummary
    let marginSummary: MarginSummary
    let withdrawable: String
    let crossMaintenanceMarginUsed: String
}

struct Position {
    let coin: String
    let entryPx: String?
    let leverage: Leverage
    let liquidationPx: String?
    let marginUsed: String
    let positionValue: String
    let returnOnEquity: String
    let szi: String  // Negative for short
    let unrealizedPnl: String
}
```

### SpotUserState

```swift
struct SpotUserState {
    let balances: [SpotBalance]
}

struct SpotBalance {
    let coin: String
    let hold: String
    let total: String
    let token: Int
}
```

### L2Book (Order Book)

```swift
struct L2Book {
    let coin: String
    let levels: [[L2Level]]  // [bids, asks]
    let time: Int64
}

struct L2Level {
    let px: String
    let sz: String
    let n: Int  // Number of orders
}
```

### Fill (Trade)

```swift
struct Fill {
    let coin: String
    let px: String
    let sz: String
    let side: String  // "A" (sell) or "B" (buy)
    let time: Int64
    let closedPnl: String
    let fee: String
    let oid: Int64
    let tid: Int64
}
```

### OrderStatus

```swift
struct OrderStatus {
    let order: OrderDetails?
    let status: String  // "order", "filled", "canceled"
    let statusTimestamp: Int64?
}
```

---

## Error Handling

```swift
enum HyperliquidError: Error {
    case invalidAddress(String)
    case invalidHexString(String)
    case precisionLoss(value: Decimal)
    case networkError(underlying: Error)
    case apiError(status: String?, response: String?)
    case decodingError(underlying: Error)
    case signingError(String)
    case invalidParameter(String)
    case missingRequiredField(String)
}
```

---

## Networks

```swift
enum HyperliquidNetwork {
    case mainnet  // https://api.hyperliquid.xyz
    case testnet  // https://api.hyperliquid-testnet.xyz
}
```

---

## Common Patterns

### Place and Track Order

```swift
let client = try HyperliquidClient(network: .mainnet, privateKey: "0x...")
let exchange = try await client.exchangeAPI()
let info = try await client.infoAPI()

// Place order
let response = try await exchange.order(
    coin: "ETH",
    isBuy: true,
    sz: Decimal(string: "0.1")!,
    limitPx: Decimal(string: "3000")!,
    orderType: .limit(LimitOrderType(tif: .gtc)),
    reduceOnly: false
)

// Parse response to get order ID
let json = try JSONSerialization.jsonObject(with: response) as? [String: Any]
// ... extract oid from response

// Query order status
let status = try await info.queryOrderByOid(user: client.walletAddress!, oid: oid)
```

### Monitor Position

```swift
let info = try await client.infoAPI()
let state = try await info.userState(address: "0x...")

for assetPosition in state.assetPositions {
    let pos = assetPosition.position
    print("\(pos.coin): size=\(pos.szi), pnl=\(pos.unrealizedPnl)")
}
```

### Real-time Order Book

```swift
let info = try await client.infoAPI()

try await info.subscribe(.l2Book(coin: "ETH")) { message in
    if case let .l2Book(book) = message {
        let bids = book.levels[0]
        let asks = book.levels[1]
        print("Best bid: \(bids.first?.px ?? "none")")
        print("Best ask: \(asks.first?.px ?? "none")")
    }
}
```

---

## Signing

The SDK supports two signer protocols for different use cases.

### Signing File Structure

| File                     | Contents                                                                                       |
| ------------------------ | ---------------------------------------------------------------------------------------------- |
| `Signer.swift`           | `Signature` struct, `HyperliquidSigner` protocol                                               |
| `EIP712Signer.swift`     | `EIP712Signer` protocol, `EIP712TypedData`, `EIP712Domain`, `EIP712TypeField`, `SendableValue` |
| `EIP712.swift`           | EIP-712 hash computation, `buildTypedDataL1()`, `buildTypedDataUserSigned()`                   |
| `PrivateKeySigner.swift` | `PrivateKeySigner` implementation using secp256k1                                              |

### HyperliquidSigner (Direct Signing)

For direct message hash signing where the SDK computes the EIP-712 hash internally. Used by `PrivateKeySigner`:

```swift
public protocol HyperliquidSigner: Sendable {
    var address: String { get }
    func sign(messageHash: Data) async throws -> Signature
}

// Usage
let signer = try PrivateKeySigner(privateKeyHex: "0x...")
let exchange = try await ExchangeAPI(signer: signer, network: .mainnet)
```

### EIP712Signer (External Wallets)

For external wallets (Privy, WalletConnect, MetaMask, etc.) that need the full EIP-712 typed data to display signing content to users:

```swift
public protocol EIP712Signer: Sendable {
    var address: String { get }
    func signTypedData(_ typedData: EIP712TypedData) async throws -> String
}

// Implementation example
class MyWalletSigner: EIP712Signer {
    let address: String = "0x..."

    func signTypedData(_ typedData: EIP712TypedData) async throws -> String {
        // Convert to dictionary for wallet SDK
        let dict = typedData.toDictionary()
        // Returns: { domain, primaryType, types, message }

        // Call your wallet SDK
        return try await walletSDK.signTypedData(dict)
        // Return 0x-prefixed 65-byte signature (r + s + v)
    }
}

// Usage
let walletSigner = MyWalletSigner()
let exchange = try await ExchangeAPI(eip712Signer: walletSigner, network: .mainnet)
```

### EIP712TypedData Structure

```swift
struct EIP712TypedData {
    let domain: EIP712Domain        // name, version, chainId, verifyingContract
    let primaryType: String         // e.g., "Agent" or "HyperliquidTransaction:UsdSend"
    let types: [String: [EIP712TypeField]]  // Type definitions
    let message: [String: SendableValue]    // Message data

    func toDictionary() -> [String: Any]  // Convert for JSON serialization
}

struct EIP712Domain {
    let name: String
    let version: String
    let chainId: UInt64
    let verifyingContract: String
}

struct EIP712TypeField {
    let name: String
    let type: String
}

enum SendableValue {
    case string(String)
    case int(Int)
    case int64(Int64)
    case uint64(UInt64)
    case bool(Bool)
    case data(Data)

    var rawValue: Any
}
```

### Signature Utilities

```swift
// Parse signature from hex string
let signature = try Signature.fromHex("0x...")

// Convert signature to hex string
let hexString = signature.toHexString()
```

---

## Dependencies

- **secp256k1.swift (P256K)** - ECDSA signing with recovery
- **CryptoSwift** - Keccak256 hashing
- **BigInt** - Arbitrary precision integers
- **OrderedCollections** - Ordered dictionaries for MessagePack

---

## Reference

- [Hyperliquid Documentation](https://hyperliquid.gitbook.io/hyperliquid-docs)
- [Hyperliquid Python SDK](https://github.com/hyperliquid-dex/hyperliquid-python-sdk)
- [Hyperliquid API](https://app.hyperliquid.xyz/api)
