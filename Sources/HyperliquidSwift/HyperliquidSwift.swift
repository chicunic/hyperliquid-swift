// HyperliquidSwift - Swift SDK for Hyperliquid DEX
//
// This SDK provides native Swift access to the Hyperliquid DEX API,
// aligned with the official Python SDK implementation.
//
// Key Features:
// - Full Info API support for market and account queries
// - Exchange API for trading operations
// - EIP-712 compliant signing
// - Swift 6 concurrency with async/await
//
// Quick Start:
// ```swift
// // Read-only access
// let client = HyperliquidClient.mainnet
// let infoAPI = try await client.infoAPI()
// let mids = try await infoAPI.getAllMids()
//
// // Trading access
// let client = try HyperliquidClient.mainnet(privateKey: "0x...")
// let exchangeAPI = try await client.exchangeAPI()
// let response = try await exchangeAPI.order(
//     coin: "BTC",
//     isBuy: true,
//     sz: 0.01,
//     limitPx: 50000,
//     orderType: .limit(LimitOrderType(tif: .gtc))
// )
// ```

// Re-export all public types
@_exported import Foundation

// Client
public typealias Client = HyperliquidClient

// API
public typealias Info = InfoAPI
public typealias Exchange = ExchangeAPI
