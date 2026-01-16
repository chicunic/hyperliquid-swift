import Foundation

// MARK: - Signature

/// Signature components (r, s, v)
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
    public var asDictionary: [String: Sendable] {
        [
            "r": r.hexString,
            "s": s.hexString,
            "v": Int(v),
        ]
    }
}

// MARK: - HyperliquidSigner Protocol

/// Protocol for direct private key signing (SDK computes EIP-712 hash internally)
public protocol HyperliquidSigner: Sendable {
    /// Wallet address (lowercase, 0x prefixed)
    var address: String { get }

    /// Sign a 32-byte keccak256 message hash, returns (r, s, v)
    func sign(messageHash: Data) async throws -> Signature
}

// MARK: - Signature Parsing

extension Signature {
    /// Parse from 0x-prefixed hex string (65 bytes: r + s + v)
    public static func fromHex(_ hexString: String) throws -> Signature {
        let cleanHex = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
        guard let data = Data(hex: cleanHex), data.count == 65 else {
            throw HyperliquidError.signingError("Invalid signature: must be 65 bytes")
        }

        let r = data.prefix(32)
        let s = data.subdata(in: 32..<64)
        let v = data[64]

        return Signature(r: Data(r), s: s, v: v)
    }

    /// Convert to 0x-prefixed hex string (65 bytes: r + s + v)
    public func toHexString() -> String {
        var data = Data()
        data.append(r)
        data.append(s)
        data.append(v)
        return data.hexString
    }
}
