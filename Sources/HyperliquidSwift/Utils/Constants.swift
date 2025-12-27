import Foundation

/// API endpoints and constants
public enum HyperliquidConstants {
    /// Mainnet API URL
    public static let mainnetAPIURL = "https://api.hyperliquid.xyz"
    /// Testnet API URL
    public static let testnetAPIURL = "https://api.hyperliquid-testnet.xyz"
    /// Local API URL for testing
    public static let localAPIURL = "http://localhost:3001"

    /// EIP-712 Domain configuration for L1 actions
    public enum L1Domain {
        public static let name = "Exchange"
        public static let version = "1"
        public static let chainId: UInt64 = 1337
        public static let verifyingContract = "0x0000000000000000000000000000000000000000"
    }

    /// EIP-712 Domain configuration for user-signed actions
    public enum UserSignedDomain {
        public static let name = "HyperliquidSignTransaction"
        public static let version = "1"
        /// Chain ID as hex string: 0x66eee = 421614
        public static let signatureChainIdHex = "0x66eee"
        public static let signatureChainId: UInt64 = 0x66EEE
        public static let verifyingContract = "0x0000000000000000000000000000000000000000"
    }
}

/// Network type
public enum HyperliquidNetwork: String, Sendable {
    case mainnet = "Mainnet"
    case testnet = "Testnet"

    public var baseURL: String {
        switch self {
        case .mainnet:
            HyperliquidConstants.mainnetAPIURL
        case .testnet:
            HyperliquidConstants.testnetAPIURL
        }
    }

    /// Source indicator for phantom agent (a = mainnet, b = testnet)
    public var sourceIndicator: String {
        switch self {
        case .mainnet:
            "a"
        case .testnet:
            "b"
        }
    }
}
