import Foundation

/// Signature components
public struct Signature: Sendable {
    public let r: Data
    public let s: Data
    public let v: UInt8

    public init(r: Data, s: Data, v: UInt8) {
        self.r = r
        self.s = s
        self.v = v
    }

    /// Convert to dictionary format for API
    public var asDictionary: [String: Any] {
        [
            "r": r.hexString,
            "s": s.hexString,
            "v": Int(v),
        ]
    }
}

/// Signer protocol for Hyperliquid signing operations
/// Reference: Python SDK signing.py
public protocol HyperliquidSigner: Sendable {
    /// The wallet address (lowercase, with 0x prefix)
    var address: String { get }

    /// Sign a message hash
    /// - Parameter messageHash: 32-byte keccak256 hash
    /// - Returns: Signature components (r, s, v)
    func sign(messageHash: Data) async throws -> Signature
}
