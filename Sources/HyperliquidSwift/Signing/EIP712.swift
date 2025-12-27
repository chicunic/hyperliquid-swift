import Foundation

/// EIP-712 typed data encoding
public enum EIP712 {
    // MARK: - Domain Separator

    /// Compute domain separator hash
    public static func domainSeparatorHash(
        name: String,
        version: String,
        chainId: UInt64,
        verifyingContract: String
    ) -> Data {
        let typeHash = hashType("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")

        var encoded = Data()
        encoded.append(typeHash)
        encoded.append(hashString(name))
        encoded.append(hashString(version))
        encoded.append(encodeUInt256(chainId))
        encoded.append(encodeAddress(verifyingContract))

        return encoded.keccak256
    }

    // MARK: - L1 Action Signing

    /// Build EIP-712 struct hash for L1 actions (Agent type)
    public static func hashL1Action(connectionId: Data, isMainnet: Bool) -> Data {
        let source = isMainnet ? "a" : "b"
        let typeHash = hashType("Agent(string source,bytes32 connectionId)")

        var encoded = Data()
        encoded.append(typeHash)
        encoded.append(hashString(source))
        encoded.append(connectionId.leftPadded(to: 32))

        return encoded.keccak256
    }

    /// Compute full EIP-712 hash for L1 actions
    public static func hashTypedDataL1(actionHash: Data, isMainnet: Bool) -> Data {
        let domainSeparator = domainSeparatorHash(
            name: HyperliquidConstants.L1Domain.name,
            version: HyperliquidConstants.L1Domain.version,
            chainId: HyperliquidConstants.L1Domain.chainId,
            verifyingContract: HyperliquidConstants.L1Domain.verifyingContract
        )

        let structHash = hashL1Action(connectionId: actionHash, isMainnet: isMainnet)

        var message = Data([0x19, 0x01])
        message.append(domainSeparator)
        message.append(structHash)

        return message.keccak256
    }

    // MARK: - User-Signed Action Signing

    /// Compute full EIP-712 hash for user-signed actions
    public static func hashTypedDataUserSigned(
        action: [String: Any],
        signTypes: [TypedVariable],
        primaryType: UserSignedPrimaryType,
        isMainnet: Bool
    ) throws -> Data {
        var fullAction = action
        fullAction["hyperliquidChain"] = isMainnet ? "Mainnet" : "Testnet"
        fullAction["signatureChainId"] = HyperliquidConstants.UserSignedDomain.signatureChainIdHex

        let domainSeparator = domainSeparatorHash(
            name: HyperliquidConstants.UserSignedDomain.name,
            version: HyperliquidConstants.UserSignedDomain.version,
            chainId: HyperliquidConstants.UserSignedDomain.signatureChainId,
            verifyingContract: HyperliquidConstants.UserSignedDomain.verifyingContract
        )

        let structHash = try hashStruct(primaryType: primaryType.rawValue, data: fullAction, types: signTypes)

        var message = Data([0x19, 0x01])
        message.append(domainSeparator)
        message.append(structHash)

        return message.keccak256
    }

    // MARK: - Struct Hash

    /// Hash a struct according to EIP-712
    private static func hashStruct(
        primaryType: String,
        data: [String: Any],
        types: [TypedVariable]
    ) throws -> Data {
        let typeString = buildTypeString(primaryType: primaryType, types: types)
        let typeHash = hashType(typeString)

        var encoded = Data()
        encoded.append(typeHash)

        for field in types {
            let value = data[field.name]
            let encodedValue = try encodeValue(value: value, type: field.type)
            encoded.append(encodedValue)
        }

        return encoded.keccak256
    }

    /// Build EIP-712 type string: "PrimaryType(type1 name1,type2 name2,...)"
    private static func buildTypeString(primaryType: String, types: [TypedVariable]) -> String {
        let fields = types.map { "\($0.type) \($0.name)" }.joined(separator: ",")
        return "\(primaryType)(\(fields))"
    }

    /// Encode value according to its EIP-712 type
    private static func encodeValue(value: Any?, type: String) throws -> Data {
        guard let value else {
            return Data(repeating: 0, count: 32)
        }

        switch type {
        case "string":
            if let string = value as? String {
                return hashString(string)
            }
        case "address":
            if let address = value as? String {
                return encodeAddress(address)
            }
        case "bool":
            if let bool = value as? Bool {
                return encodeBool(bool)
            }
        case "uint64":
            if let uint64 = value as? UInt64 {
                return encodeUInt256(uint64)
            } else if let int64 = value as? Int64 {
                return encodeUInt256(UInt64(int64))
            } else if let int = value as? Int {
                return encodeUInt256(UInt64(int))
            }
        case "uint256":
            if let uint64 = value as? UInt64 {
                return encodeUInt256(uint64)
            } else if let string = value as? String {
                return encodeUInt256FromHex(string)
            }
        case "bytes32":
            if let data = value as? Data {
                return data.leftPadded(to: 32)
            }
        default:
            break
        }

        throw HyperliquidError.invalidParameter("Cannot encode value \(value) as type \(type)")
    }

    // MARK: - Primitive Encoding

    private static func hashType(_ typeString: String) -> Data {
        guard let data = typeString.data(using: .utf8) else { return Data(repeating: 0, count: 32) }
        return data.keccak256
    }

    private static func hashString(_ string: String) -> Data {
        guard let data = string.data(using: .utf8) else { return Data(repeating: 0, count: 32) }
        return data.keccak256
    }

    private static func encodeUInt256(_ value: UInt64) -> Data {
        var data = Data(repeating: 0, count: 24)
        var bigEndian = value.bigEndian
        data.append(Data(bytes: &bigEndian, count: 8))
        return data
    }

    private static func encodeUInt256FromHex(_ hex: String) -> Data {
        let cleanHex = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard let data = Data(hex: cleanHex) else {
            return Data(repeating: 0, count: 32)
        }
        return data.leftPadded(to: 32)
    }

    private static func encodeAddress(_ address: String) -> Data {
        guard let bytes = address.addressToBytes() else { return Data(repeating: 0, count: 32) }
        return bytes.leftPadded(to: 32)
    }

    private static func encodeBool(_ value: Bool) -> Data {
        var data = Data(repeating: 0, count: 31)
        data.append(value ? 1 : 0)
        return data
    }

    // MARK: - Phantom Agent

    /// Construct a phantom agent for L1 signing
    public static func constructPhantomAgent(source: String, connectionId: Data) -> [String: Any] {
        ["source": source, "connectionId": connectionId]
    }

    // MARK: - EIP712TypedData Builders

    /// EIP712Domain type fields
    private static let eip712DomainTypeFields: [EIP712TypeField] = [
        EIP712TypeField(name: "name", type: "string"),
        EIP712TypeField(name: "version", type: "string"),
        EIP712TypeField(name: "chainId", type: "uint256"),
        EIP712TypeField(name: "verifyingContract", type: "address"),
    ]

    /// Build EIP712TypedData for L1 actions (Agent type)
    public static func buildTypedDataL1(actionHash: Data, isMainnet: Bool) -> EIP712TypedData {
        let source = isMainnet ? "a" : "b"

        let domain = EIP712Domain(
            name: HyperliquidConstants.L1Domain.name,
            version: HyperliquidConstants.L1Domain.version,
            chainId: HyperliquidConstants.L1Domain.chainId,
            verifyingContract: HyperliquidConstants.L1Domain.verifyingContract
        )

        let agentTypeFields: [EIP712TypeField] = [
            EIP712TypeField(name: "source", type: "string"),
            EIP712TypeField(name: "connectionId", type: "bytes32"),
        ]

        let types: [String: [EIP712TypeField]] = [
            "EIP712Domain": eip712DomainTypeFields,
            "Agent": agentTypeFields,
        ]

        let message: [String: SendableValue] = [
            "source": .string(source),
            "connectionId": .data(actionHash.leftPadded(to: 32)),
        ]

        return EIP712TypedData(
            domain: domain,
            primaryType: "Agent",
            types: types,
            message: message
        )
    }

    /// Build EIP712TypedData for user-signed actions
    public static func buildTypedDataUserSigned(
        action: [String: Any],
        signTypes: [TypedVariable],
        primaryType: UserSignedPrimaryType,
        isMainnet: Bool
    ) -> EIP712TypedData {
        let domain = EIP712Domain(
            name: HyperliquidConstants.UserSignedDomain.name,
            version: HyperliquidConstants.UserSignedDomain.version,
            chainId: HyperliquidConstants.UserSignedDomain.signatureChainId,
            verifyingContract: HyperliquidConstants.UserSignedDomain.verifyingContract
        )

        // signatureChainId is added to message but NOT to type definition
        let typeFields: [EIP712TypeField] = signTypes.map {
            EIP712TypeField(name: $0.name, type: $0.type)
        }

        let types: [String: [EIP712TypeField]] = [
            "EIP712Domain": eip712DomainTypeFields,
            primaryType.rawValue: typeFields,
        ]

        var message: [String: SendableValue] = [:]
        message["hyperliquidChain"] = .string(isMainnet ? "Mainnet" : "Testnet")

        for field in signTypes {
            if field.name == "hyperliquidChain" { continue }
            if let value = action[field.name] {
                message[field.name] = convertToSendableValue(value, type: field.type)
            }
        }

        message["signatureChainId"] = .string(HyperliquidConstants.UserSignedDomain.signatureChainIdHex)

        return EIP712TypedData(
            domain: domain,
            primaryType: primaryType.rawValue,
            types: types,
            message: message
        )
    }

    /// Convert value to SendableValue based on EIP-712 type
    private static func convertToSendableValue(_ value: Any, type: String) -> SendableValue {
        switch type {
        case "string": if let s = value as? String { return .string(s) }
        case "address": if let s = value as? String { return .string(s) }
        case "bool": if let b = value as? Bool { return .bool(b) }
        case "uint64":
            if let u = value as? UInt64 { return .uint64(u) }
            if let i = value as? Int64 { return .int64(i) }
            if let i = value as? Int { return .int(i) }
        case "uint256":
            if let u = value as? UInt64 { return .uint64(u) }
            if let s = value as? String { return .string(s) }
        case "bytes32": if let d = value as? Data { return .data(d) }
        default: break
        }
        if let s = value as? String { return .string(s) }
        if let i = value as? Int { return .int(i) }
        if let i = value as? Int64 { return .int64(i) }
        if let u = value as? UInt64 { return .uint64(u) }
        if let b = value as? Bool { return .bool(b) }
        if let d = value as? Data { return .data(d) }
        return .string(String(describing: value))
    }
}
