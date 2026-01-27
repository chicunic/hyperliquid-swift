import Foundation

// MARK: - EIP712Signer Protocol

/// Protocol for external wallets (Privy, WalletConnect, MetaMask) to sign EIP-712 typed data
public protocol EIP712Signer: Sendable {
    /// Wallet address (lowercase, 0x prefixed)
    var address: String { get }

    /// Sign EIP-712 typed data, returns 0x-prefixed 65-byte hex signature (r + s + v)
    func signTypedData(_ typedData: EIP712TypedData) async throws -> String
}

// MARK: - EIP-712 Typed Data Structures

/// EIP-712 domain separator (name, version, chainId, verifyingContract)
public struct EIP712Domain: Sendable, Equatable {
    public let name: String
    public let version: String
    public let chainId: UInt64
    public let verifyingContract: String

    public init(name: String, version: String, chainId: UInt64, verifyingContract: String) {
        self.name = name
        self.version = version
        self.chainId = chainId
        self.verifyingContract = verifyingContract
    }
}

/// EIP-712 type field definition
public struct EIP712TypeField: Sendable, Equatable {
    public let name: String
    public let type: String

    public init(name: String, type: String) {
        self.name = name
        self.type = type
    }
}

/// EIP-712 typed data structure for wallet signing (domain, types, primaryType, message)
public struct EIP712TypedData: Sendable {
    public let domain: EIP712Domain
    public let primaryType: String
    public let types: [String: [EIP712TypeField]]
    public let message: [String: SendableValue]

    public init(
        domain: EIP712Domain,
        primaryType: String,
        types: [String: [EIP712TypeField]],
        message: [String: SendableValue]
    ) {
        self.domain = domain
        self.primaryType = primaryType
        self.types = types
        self.message = message
    }

    /// Convert to dictionary for JSON serialization (pass to wallet SDKs)
    public func toDictionary() -> [String: Any] {
        [
            "domain": [
                "name": domain.name,
                "version": domain.version,
                "chainId": domain.chainId,
                "verifyingContract": domain.verifyingContract,
            ],
            "primaryType": primaryType,
            "types": types.mapValues { fields in
                fields.map { ["name": $0.name, "type": $0.type] }
            },
            "message": message.mapValues { $0.rawValue },
        ]
    }
}

/// Sendable wrapper for EIP-712 message values (String, Int, Int64, UInt64, Bool, Data)
public enum SendableValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case int64(Int64)
    case uint64(UInt64)
    case bool(Bool)
    case data(Data)

    /// Get underlying raw value
    public var rawValue: Any {
        switch self {
        case .string(let v): v
        case .int(let v): v
        case .int64(let v): v
        case .uint64(let v): v
        case .bool(let v): v
        case .data(let v): v
        }
    }

    public static func from(_ value: String) -> Self { .string(value) }
    public static func from(_ value: Int) -> Self { .int(value) }
    public static func from(_ value: Int64) -> Self { .int64(value) }
    public static func from(_ value: UInt64) -> Self { .uint64(value) }
    public static func from(_ value: Bool) -> Self { .bool(value) }
    public static func from(_ value: Data) -> Self { .data(value) }
}
