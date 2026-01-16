import Foundation

/// Common error types for Hyperliquid SDK
public enum HyperliquidError: Error, Sendable {
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

/// Represents a client order ID (CLOID)
public struct Cloid: Sendable, Hashable, Codable {
    private let rawValue: String

    /// Initialize with a raw CLOID string (must be valid hex without 0x prefix, 32 chars)
    public init?(rawValue: String) {
        // Validate: must be 16 bytes (32 hex chars)
        let cleaned = rawValue.hasPrefix("0x") ? String(rawValue.dropFirst(2)) : rawValue
        guard cleaned.count == 32,
            cleaned.allSatisfy(\.isHexDigit)
        else {
            return nil
        }
        self.rawValue = cleaned
    }

    /// Create a new random CLOID
    public static func random() -> Cloid {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return Cloid(rawValue: hex)!
    }

    /// Hex string with 0x prefix (matches Python SDK format for wire)
    public func toRaw() -> String {
        "0x" + rawValue
    }

    /// Hex string with 0x prefix
    public var hexString: String {
        "0x" + rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let cleaned = value.hasPrefix("0x") ? String(value.dropFirst(2)) : value
        rawValue = cleaned
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode("0x" + rawValue)
    }
}

/// Time in force options for limit orders
public enum TimeInForce: String, Sendable, Codable {
    /// Good 'til cancelled
    case gtc = "Gtc"
    /// Immediate or cancel
    case ioc = "Ioc"
    /// Add liquidity only (maker only)
    case alo = "Alo"
}

/// Take profit / Stop loss indicator
public enum TpSl: String, Sendable, Codable {
    case takeProfit = "tp"
    case stopLoss = "sl"
}

/// Order side
public enum OrderSide: Sendable {
    case buy
    case sell

    public var isBuy: Bool {
        self == .buy
    }
}

/// Asset type
public enum AssetType: String, Sendable, Codable {
    case perp
    case spot
}

/// Generate current timestamp in milliseconds
public func currentTimestampMs() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
}
