import Foundation

// MARK: - TypedVariable (EIP-712 type definition)

/// Represents a typed variable in EIP-712 structured data
public struct TypedVariable: Sendable, Equatable {
    public let name: String
    public let type: String

    public init(name: String, type: String) {
        self.name = name
        self.type = type
    }
}

// MARK: - User-Signed Action Sign Types (Python SDK signing.py:80-145)

public let usdSendSignTypes: [TypedVariable] = [
    TypedVariable(name: "hyperliquidChain", type: "string"),
    TypedVariable(name: "destination", type: "string"),
    TypedVariable(name: "amount", type: "string"),
    TypedVariable(name: "time", type: "uint64"),
]

public let spotTransferSignTypes: [TypedVariable] = [
    TypedVariable(name: "hyperliquidChain", type: "string"),
    TypedVariable(name: "destination", type: "string"),
    TypedVariable(name: "token", type: "string"),
    TypedVariable(name: "amount", type: "string"),
    TypedVariable(name: "time", type: "uint64"),
]

public let withdrawSignTypes: [TypedVariable] = [
    TypedVariable(name: "hyperliquidChain", type: "string"),
    TypedVariable(name: "destination", type: "string"),
    TypedVariable(name: "amount", type: "string"),
    TypedVariable(name: "time", type: "uint64"),
]

public let usdClassTransferSignTypes: [TypedVariable] = [
    TypedVariable(name: "hyperliquidChain", type: "string"),
    TypedVariable(name: "amount", type: "string"),
    TypedVariable(name: "toPerp", type: "bool"),
    TypedVariable(name: "nonce", type: "uint64"),
]

public let sendAssetSignTypes: [TypedVariable] = [
    TypedVariable(name: "hyperliquidChain", type: "string"),
    TypedVariable(name: "destination", type: "string"),
    TypedVariable(name: "sourceDex", type: "string"),
    TypedVariable(name: "destinationDex", type: "string"),
    TypedVariable(name: "token", type: "string"),
    TypedVariable(name: "amount", type: "string"),
    TypedVariable(name: "fromSubAccount", type: "string"),
    TypedVariable(name: "nonce", type: "uint64"),
]

public let tokenDelegateSignTypes: [TypedVariable] = [
    TypedVariable(name: "hyperliquidChain", type: "string"),
    TypedVariable(name: "validator", type: "address"),
    TypedVariable(name: "wei", type: "uint64"),
    TypedVariable(name: "isUndelegate", type: "bool"),
    TypedVariable(name: "nonce", type: "uint64"),
]

public let approveAgentSignTypes: [TypedVariable] = [
    TypedVariable(name: "hyperliquidChain", type: "string"),
    TypedVariable(name: "agentAddress", type: "address"),
    TypedVariable(name: "agentName", type: "string"),
    TypedVariable(name: "nonce", type: "uint64"),
]

public let approveBuilderFeeSignTypes: [TypedVariable] = [
    TypedVariable(name: "hyperliquidChain", type: "string"),
    TypedVariable(name: "maxFeeRate", type: "string"),
    TypedVariable(name: "builder", type: "address"),
    TypedVariable(name: "nonce", type: "uint64"),
]

public let userDexAbstractionSignTypes: [TypedVariable] = [
    TypedVariable(name: "hyperliquidChain", type: "string"),
    TypedVariable(name: "user", type: "address"),
    TypedVariable(name: "enabled", type: "bool"),
    TypedVariable(name: "nonce", type: "uint64"),
]

public let convertToMultiSigUserSignTypes: [TypedVariable] = [
    TypedVariable(name: "hyperliquidChain", type: "string"),
    TypedVariable(name: "signers", type: "string"),
    TypedVariable(name: "nonce", type: "uint64"),
]

public let multiSigEnvelopeSignTypes: [TypedVariable] = [
    TypedVariable(name: "hyperliquidChain", type: "string"),
    TypedVariable(name: "multiSigActionHash", type: "bytes32"),
    TypedVariable(name: "nonce", type: "uint64"),
]

// MARK: - User-Signed Primary Types

public enum UserSignedPrimaryType: String, Sendable {
    case usdSend = "HyperliquidTransaction:UsdSend"
    case spotSend = "HyperliquidTransaction:SpotSend"
    case withdraw = "HyperliquidTransaction:Withdraw"
    case usdClassTransfer = "HyperliquidTransaction:UsdClassTransfer"
    case sendAsset = "HyperliquidTransaction:SendAsset"
    case tokenDelegate = "HyperliquidTransaction:TokenDelegate"
    case approveAgent = "HyperliquidTransaction:ApproveAgent"
    case approveBuilderFee = "HyperliquidTransaction:ApproveBuilderFee"
    case userDexAbstraction = "HyperliquidTransaction:UserDexAbstraction"
    case convertToMultiSigUser = "HyperliquidTransaction:ConvertToMultiSigUser"
    case multiSigEnvelope = "HyperliquidTransaction:SendMultiSig"
}
