# hyperliquid-swift

A native Swift SDK for interacting with the [Hyperliquid](https://hyperliquid.xyz) DEX API.

## Overview

This SDK provides a type-safe Swift interface for the Hyperliquid decentralized exchange, supporting both Info (read-only) and Exchange (trading) APIs. The implementation is aligned with the official [Python SDK](https://github.com/hyperliquid-dex/hyperliquid-python-sdk) to ensure signature compatibility.

## Requirements

- iOS 18.0+ / macOS 15.0+
- Swift 6.0+
- Xcode 16.0+

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/chicunic/hyperliquid-swift.git", from: "0.1.0")
]
```

Or add it via Xcode: File → Add Package Dependencies → Enter the repository URL.

## Features

### Info API (Read-only)

Query market data and account information without authentication:

```swift
import HyperliquidSwift

let client = HyperliquidClient(network: .mainnet)

// Get all mid prices
let mids = try await client.info.getAllMids()

// Get user account state
let state = try await client.info.getUserState(address: "0x...")

// Get order book
let book = try await client.info.getL2Book(coin: "ETH")

// Get candle data
let candles = try await client.info.getCandleSnapshot(
    coin: "ETH",
    interval: "1h",
    startTime: startTimestamp,
    endTime: endTimestamp
)
```

### Exchange API (Trading)

Execute trades with wallet signing:

```swift
import HyperliquidSwift

// Initialize with private key
let signer = try PrivateKeySigner(privateKeyHex: "0x...")
let client = HyperliquidClient(network: .mainnet, signer: signer)

// Place a limit order
let order = OrderRequest(
    coin: "ETH",
    isBuy: true,
    sz: Decimal(string: "0.1")!,
    limitPx: Decimal(string: "3000")!,
    orderType: .limit(LimitOrderType(tif: .gtc)),
    reduceOnly: false
)
let response = try await client.exchange.order(order)

// Cancel an order
try await client.exchange.cancel(coin: "ETH", oid: 123456)

// Transfer USD
try await client.exchange.usdTransfer(
    destination: "0x...",
    amount: Decimal(string: "100")!
)
```

## Supported APIs

### Info API

- `getAllMids` - All trading pair mid prices
- `getUserState` - Perpetual account state
- `getSpotUserState` - Spot account state
- `getOpenOrders` - Open orders
- `getUserFills` / `getUserFillsByTime` - Trade history
- `getMeta` / `getSpotMeta` - Market metadata
- `getMetaAndAssetCtxs` / `getSpotMetaAndAssetCtxs` - Metadata with context
- `getL2Book` - Order book snapshot
- `getCandleSnapshot` - Candlestick data
- `queryOrderByOid` / `queryOrderByCloid` - Order status
- And more...

### Exchange API

- `order` / `bulkOrders` - Place orders
- `cancel` / `bulkCancel` / `cancelByCloid` - Cancel orders
- `modifyOrder` / `bulkModifyOrders` - Modify orders
- `updateLeverage` / `updateIsolatedMargin` - Position management
- `usdTransfer` / `spotTransfer` - Transfers
- `withdrawFromBridge` - Withdrawals
- And more...

## Architecture

The SDK uses:

- **Swift Concurrency** (async/await, actors, Sendable) for thread safety
- **secp256k1.swift (P256K)** for ECDSA signing with recovery
- **CryptoSwift** for keccak256 hashing
- **OrderedCollections** for consistent MessagePack serialization
- **MessagePack** for action hash computation (matching Python SDK exactly)

## Signing

The SDK implements two signing methods matching the Python SDK:

1. **L1 Action Signing** - For order operations, uses phantom agent with EIP-712
2. **User-Signed Action Signing** - For transfers and approvals, uses TypedData EIP-712

All signatures are verified against the Python SDK test vectors to ensure compatibility.

## Networks

```swift
// Mainnet
let client = HyperliquidClient(network: .mainnet, signer: signer)

// Testnet
let client = HyperliquidClient(network: .testnet, signer: signer)
```

## Reference

- [Hyperliquid Documentation](https://hyperliquid.gitbook.io/hyperliquid-docs)
- [Hyperliquid Python SDK](https://github.com/hyperliquid-dex/hyperliquid-python-sdk)
- [Hyperliquid API](https://app.hyperliquid.xyz/api)

## License

MIT License
