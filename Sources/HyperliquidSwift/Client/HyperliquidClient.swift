import Foundation

/// Main client for Hyperliquid SDK
/// Provides unified access to Info and Exchange APIs
public final class HyperliquidClient: Sendable {
    /// Network configuration
    public let network: HyperliquidNetwork

    /// Optional signer for Exchange API operations
    private let signer: HyperliquidSigner?

    /// Initialize client for read-only Info API access
    /// - Parameter network: Network to connect to
    public init(network: HyperliquidNetwork = .mainnet) {
        self.network = network
        signer = nil
    }

    /// Initialize client with signing capability for Exchange API access
    /// - Parameters:
    ///   - network: Network to connect to
    ///   - signer: Signer for transaction signing
    public init(network: HyperliquidNetwork = .mainnet, signer: HyperliquidSigner) {
        self.network = network
        self.signer = signer
    }

    /// Initialize client with a private key
    /// - Parameters:
    ///   - network: Network to connect to
    ///   - privateKey: Hex-encoded private key (with or without 0x prefix)
    public init(network: HyperliquidNetwork = .mainnet, privateKey: String) throws {
        self.network = network
        signer = try PrivateKeySigner(privateKeyHex: privateKey)
    }

    /// Create an Info API instance
    /// - Returns: Info API actor for querying market and account data
    public func infoAPI() async throws -> InfoAPI {
        try await InfoAPI(network: network)
    }

    /// Create a simple Info API instance (without metadata loading)
    /// - Returns: Info API actor for simple queries
    public func simpleInfoAPI() -> InfoAPI {
        InfoAPI(network: network)
    }

    /// Create an Exchange API instance
    /// - Parameters:
    ///   - vaultAddress: Optional vault address
    ///   - accountAddress: Optional account address
    /// - Returns: Exchange API actor for trading operations
    public func exchangeAPI(
        vaultAddress: String? = nil,
        accountAddress: String? = nil
    ) async throws -> ExchangeAPI {
        guard let signer else {
            throw HyperliquidError.signingError("Signer required for Exchange API")
        }
        return try await ExchangeAPI(
            signer: signer,
            network: network,
            vaultAddress: vaultAddress,
            accountAddress: accountAddress
        )
    }

    /// Get the wallet address if a signer is configured
    public var walletAddress: String? {
        signer?.address
    }
}

// MARK: - Convenience Extensions

extension HyperliquidClient {
    /// Create a mainnet client
    public static var mainnet: HyperliquidClient {
        HyperliquidClient(network: .mainnet)
    }

    /// Create a testnet client
    public static var testnet: HyperliquidClient {
        HyperliquidClient(network: .testnet)
    }

    /// Create a mainnet client with private key
    public static func mainnet(privateKey: String) throws -> HyperliquidClient {
        try HyperliquidClient(network: .mainnet, privateKey: privateKey)
    }

    /// Create a testnet client with private key
    public static func testnet(privateKey: String) throws -> HyperliquidClient {
        try HyperliquidClient(network: .testnet, privateKey: privateKey)
    }
}
