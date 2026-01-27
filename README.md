# hyperliquid-swift

![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Platform](https://img.shields.io/badge/platform-iOS%2018.0%2B%20%7C%20macOS%2015.0%2B-lightgrey.svg)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A native, type-safe Swift SDK for interacting with the [Hyperliquid](https://hyperliquid.xyz) DEX API.

## Overview

This SDK provides a comprehensive Swift interface for the Hyperliquid decentralized exchange, supporting both **Info (read-only)** and **Exchange (trading)** APIs. The implementation is rigorously tested and aligned with the official [Python SDK](https://github.com/hyperliquid-dex/hyperliquid-python-sdk) to ensure signature compatibility and reliability.

## Requirements

- **Swift:** 6.0+
- **Platforms:**
  - macOS 15.0+
  - iOS 18.0+
- **Tools:** Xcode 16.0+

## Installation

### Swift Package Manager

Add the package to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/chicunic/hyperliquid-swift.git", from: "0.2.0")
]
```

Or add it via Xcode:

1. **File** → **Add Package Dependencies...**
2. Enter URL: `https://github.com/chicunic/hyperliquid-swift.git`
3. Select the version rule (e.g., Up to Next Major).

## Quick Start

### Info API (Public Data)

Query market data and account information without authentication keys.

```swift
import HyperliquidSwift

// 1. Initialize Client
let client = HyperliquidClient(network: .mainnet)

// 2. Query Market Data
let mids = try await client.info.getAllMids()
print("BTC Price: \(mids["BTC"] ?? "N/A")")

// 3. Get Account State
let userAddress = "0x..."
let state = try await client.info.getUserState(address: userAddress)
print("Account Value: \(state.marginSummary.accountValue)")

// 4. Get Historical Candles
let candles = try await client.info.getCandleSnapshot(
    coin: "ETH",
    interval: "1h",
    startTime: startTimestamp,
    endTime: endTimestamp
)
```

### Exchange API (Trading)

Execute trades and manage funds securely.

```swift
import HyperliquidSwift

// 1. Initialize with Private Key
// Note: Never hardcode private keys in production apps.
let privateKey = "0x..."
let signer = try PrivateKeySigner(privateKeyHex: privateKey)
let client = HyperliquidClient(network: .mainnet, signer: signer)

// 2. Place a Limit Order
let orderRequest = OrderRequest(
    coin: "ETH",
    isBuy: true,
    sz: Decimal(string: "0.1")!,
    limitPx: Decimal(string: "3000")!,
    orderType: .limit(LimitOrderType(tif: .gtc)),
    reduceOnly: false
)

let result = try await client.exchange.order(orderRequest)
print("Order placed: \(result)")

// 3. Cancel an Order
try await client.exchange.cancel(coin: "ETH", oid: 123456)
```

## Features

### 📊 Info API

- **Market Data:** `getAllMids`, `getL2Book`, `getCandleSnapshot`
- **Account Info:** `getUserState`, `getSpotUserState`, `getUserFills`
- **Metadata:** `getMeta`, `getSpotMeta`, `getMetaAndAssetCtxs`
- **Orders:** `getOpenOrders`, `queryOrderByOid`

### ⚡ Exchange API

- **Trading:** Place, Modify, and Cancel orders (Single & Bulk)
- **Account Management:** `updateLeverage`, `updateIsolatedMargin`
- **Transfers:** USD & Spot transfers, Withdrawals from Bridge
- **Advanced:** EIP-712 Signing support for external wallets

## Architecture & Security

- **Type Safety:** leveraging Swift's strong type system to prevent common API errors.
- **Concurrency:** Built entirely with Swift `async`/`await` and `Actors`.
- **Cryptography:**
  - **secp256k1.swift:** High-performance ECDSA signing.
  - **EIP-712:** Full typed data hashing implementation matching the Python SDK.
- **Serialization:** Custom MessagePack handling ensures binary-compatible payloads with the Hyperliquid backend.

### Signing Support

The SDK supports two modes for signing transactions:

1. **PrivateKeySigner:** For automated bots or backend services where you hold the key.
2. **EIP712Signer (Protocol):** For integrating with user wallets (MetaMask, WalletConnect, Privy, etc.). You implement `signTypedData` and the SDK handles the payload construction.

## Development

This project uses a `Makefile` to simplify common development tasks.

```bash
# Build the project
make build

# Run unit tests
make test

# Check code style (SwiftLint + swift-format)
make check

# Fix code style issues
make fix

# Update dependencies
make resolve
```

## License

MIT
