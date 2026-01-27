import Foundation
import P256K

/// Signer implementation using a private key via secp256k1
public final class PrivateKeySigner: HyperliquidSigner, @unchecked Sendable {
    private let privateKey: P256K.Recovery.PrivateKey
    public let address: String

    /// Initialize with a hex private key string
    /// - Parameter privateKeyHex: 32-byte private key as hex string (with or without 0x prefix)
    public convenience init(privateKeyHex: String) throws {
        guard let keyData = Data(hex: privateKeyHex), keyData.count == 32 else {
            throw HyperliquidError.invalidHexString("Invalid private key: must be 32 bytes")
        }
        try self.init(privateKeyData: keyData)
    }

    /// Initialize with raw private key data
    /// - Parameter privateKeyData: 32-byte private key
    public init(privateKeyData: Data) throws {
        guard privateKeyData.count == 32 else {
            throw HyperliquidError.invalidParameter("Private key must be 32 bytes")
        }

        privateKey = try P256K.Recovery.PrivateKey(dataRepresentation: privateKeyData)
        address = try Self.deriveAddress(from: privateKeyData)
    }

    /// Derive Ethereum address from private key data
    private static func deriveAddress(from keyData: Data) throws -> String {
        let uncompressedKey = try P256K.Recovery.PrivateKey(dataRepresentation: keyData, format: .uncompressed)
        let publicKeyData = uncompressedKey.publicKey.dataRepresentation
        // Public key is 65 bytes (0x04 prefix + 64 bytes), we need keccak256 of the 64 bytes
        let publicKeyBytes = publicKeyData.count == 65 ? publicKeyData.dropFirst() : publicKeyData
        let addressHash = publicKeyBytes.keccak256
        return "0x" + addressHash.suffix(20).hexStringWithoutPrefix
    }

    /// Sign a message hash using secp256k1 with recovery
    /// - Parameter messageHash: 32-byte hash to sign
    /// - Returns: Signature with r, s, v components
    public func sign(messageHash: Data) async throws -> Signature {
        guard messageHash.count == 32 else {
            throw HyperliquidError.signingError("Message hash must be 32 bytes")
        }

        // Create a digest wrapper for the message hash
        let digest = MessageDigest(data: messageHash)

        // Sign with recoverable signature
        let recoverableSignature = try privateKey.signature(for: digest)

        // Get compact representation (r || s) and recovery ID
        let compact = try recoverableSignature.compactRepresentation
        let signatureData = compact.signature
        let recoveryId = compact.recoveryId

        guard signatureData.count == 64 else {
            throw HyperliquidError.signingError("Invalid signature length")
        }

        let r = signatureData.prefix(32)
        let s = signatureData.suffix(32)

        // v = recoveryId + 27
        let v = UInt8(recoveryId + 27)

        return Signature(r: Data(r), s: Data(s), v: v)
    }
}

// MARK: - Message Digest Wrapper

/// A wrapper to pass pre-computed hash to P256K signing
struct MessageDigest: Digest {
    let data: Data

    init(data: Data) {
        self.data = data
    }

    static var byteCount: Int { 32 }

    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try data.withUnsafeBytes(body)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(data)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.data == rhs.data
    }

    var description: String {
        data.hexString
    }

    func makeIterator() -> Data.Iterator {
        data.makeIterator()
    }
}
