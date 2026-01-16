import Foundation

/// EIP-712 typed data encoding
public enum EIP712 {
    // MARK: - Domain Separator

    public static func domainSeparatorHash(name: String, version: String, chainId: UInt64, verifyingContract: String)
        -> Data
    {
        let typeHash = hashType("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
        var encoded = Data()
        encoded.append(typeHash)
        encoded.append(hashString(name))
        encoded.append(hashString(version))
        encoded.append(encodeUInt256(chainId))
        encoded.append(encodeAddress(verifyingContract))
        return encoded.keccak256
    }

    // MARK: - Domain Separators (cached)

    private static let l1DomainSeparator = domainSeparatorHash(
        name: HyperliquidConstants.L1Domain.name,
        version: HyperliquidConstants.L1Domain.version,
        chainId: HyperliquidConstants.L1Domain.chainId,
        verifyingContract: HyperliquidConstants.L1Domain.verifyingContract
    )

    private static let userSignedDomainSeparator = domainSeparatorHash(
        name: HyperliquidConstants.UserSignedDomain.name,
        version: HyperliquidConstants.UserSignedDomain.version,
        chainId: HyperliquidConstants.UserSignedDomain.signatureChainId,
        verifyingContract: HyperliquidConstants.UserSignedDomain.verifyingContract
    )

    // MARK: - L1 Action Signing

    public static func hashTypedDataL1(actionHash: Data, isMainnet: Bool) -> Data {
        let source = isMainnet ? "a" : "b"
        let typeHash = hashType("Agent(string source,bytes32 connectionId)")
        var structEncoded = Data()
        structEncoded.append(typeHash)
        structEncoded.append(hashString(source))
        structEncoded.append(actionHash.leftPadded(to: 32))

        return encodePacked(l1DomainSeparator, structEncoded.keccak256).keccak256
    }

    // MARK: - User-Signed Action Signing

    public static func hashTypedDataUserSigned(
        action: [String: Sendable],
        signTypes: [TypedVariable],
        primaryType: UserSignedPrimaryType,
        isMainnet: Bool
    ) throws -> Data {
        var fullAction = action
        fullAction["hyperliquidChain"] = isMainnet ? "Mainnet" : "Testnet"
        fullAction["signatureChainId"] = HyperliquidConstants.UserSignedDomain.signatureChainIdHex

        let structHash = try hashStruct(primaryType: primaryType.rawValue, data: fullAction, types: signTypes)
        return encodePacked(userSignedDomainSeparator, structHash).keccak256
    }

    // MARK: - Struct Hash

    private static func hashStruct(primaryType: String, data: [String: Sendable], types: [TypedVariable]) throws -> Data
    {
        let typeString = "\(primaryType)(\(types.map { "\($0.type) \($0.name)" }.joined(separator: ",")))"
        var encoded = Data()
        encoded.append(hashType(typeString))

        for field in types {
            encoded.append(try encodeValue(value: data[field.name], type: field.type))
        }
        return encoded.keccak256
    }

    private static func encodeValue(value: Sendable?, type: String) throws -> Data {
        guard let value else { return Data(repeating: 0, count: 32) }

        switch type {
        case "string":
            return hashString((value as? String) ?? "")
        case "address":
            return encodeAddress((value as? String) ?? "")
        case "bool":
            return encodeBool((value as? Bool) ?? false)
        case "uint64":
            if let v = value as? UInt64 { return encodeUInt256(v) }
            if let v = value as? Int64 { return encodeUInt256(UInt64(v)) }
            if let v = value as? Int { return encodeUInt256(UInt64(v)) }
        case "uint256":
            if let v = value as? UInt64 { return encodeUInt256(v) }
            if let v = value as? String { return encodeUInt256FromHex(v) }
        case "bytes32":
            if let v = value as? Data { return v.leftPadded(to: 32) }
        default: break
        }
        throw HyperliquidError.invalidParameter("Cannot encode value \(value) as type \(type)")
    }

    // MARK: - Primitive Encoding

    private static func encodePacked(_ part1: Data, _ part2: Data) -> Data {
        var data = Data([0x19, 0x01])
        data.append(part1)
        data.append(part2)
        return data
    }

    /// Keccak-256 hash of type string for EIP-712 encoding
    private static func hashType(_ typeString: String) -> Data {
        typeString.data(using: .utf8)?.keccak256 ?? Data(repeating: 0, count: 32)
    }

    /// Keccak-256 hash of string value
    private static func hashString(_ string: String) -> Data {
        string.data(using: .utf8)?.keccak256 ?? Data(repeating: 0, count: 32)
    }

    /// Encode UInt64 as 32-byte big-endian value (EIP-712 uint256)
    private static func encodeUInt256(_ value: UInt64) -> Data {
        var big = value.bigEndian
        return Data(bytes: &big, count: 8).leftPadded(to: 32)
    }

    /// Decode hex string and encode as 32-byte value
    private static func encodeUInt256FromHex(_ hex: String) -> Data {
        let clean = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        return Data(hex: clean)?.leftPadded(to: 32) ?? Data(repeating: 0, count: 32)
    }

    /// Encode Ethereum address as 32-byte value (left-padded)
    private static func encodeAddress(_ address: String) -> Data {
        address.addressToBytes()?.leftPadded(to: 32) ?? Data(repeating: 0, count: 32)
    }

    /// Encode boolean as 32-byte value (0x00...00 or 0x00...01)
    private static func encodeBool(_ value: Bool) -> Data {
        var data = Data(repeating: 0, count: 31)
        data.append(value ? 1 : 0)
        return data
    }

    // MARK: - EIP712TypedData Builders

    private static let eip712DomainTypeFields: [EIP712TypeField] = [
        EIP712TypeField(name: "name", type: "string"),
        EIP712TypeField(name: "version", type: "string"),
        EIP712TypeField(name: "chainId", type: "uint256"),
        EIP712TypeField(name: "verifyingContract", type: "address"),
    ]

    public static func buildTypedDataL1(actionHash: Data, isMainnet: Bool) -> EIP712TypedData {
        let source = isMainnet ? "a" : "b"
        let message: [String: SendableValue] = [
            "source": .string(source),
            "connectionId": .data(actionHash.leftPadded(to: 32)),
        ]

        return EIP712TypedData(
            domain: makeDomain(
                name: HyperliquidConstants.L1Domain.name, version: HyperliquidConstants.L1Domain.version,
                chainId: HyperliquidConstants.L1Domain.chainId,
                verifyingContract: HyperliquidConstants.L1Domain.verifyingContract),
            primaryType: "Agent",
            types: [
                "EIP712Domain": eip712DomainTypeFields,
                "Agent": [
                    EIP712TypeField(name: "source", type: "string"),
                    EIP712TypeField(name: "connectionId", type: "bytes32"),
                ],
            ],
            message: message
        )
    }

    public static func buildTypedDataUserSigned(
        action: [String: Sendable],
        signTypes: [TypedVariable],
        primaryType: UserSignedPrimaryType,
        isMainnet: Bool
    ) -> EIP712TypedData {
        var message: [String: SendableValue] = [:]
        message["hyperliquidChain"] = .string(isMainnet ? "Mainnet" : "Testnet")
        message["signatureChainId"] = .string(HyperliquidConstants.UserSignedDomain.signatureChainIdHex)

        for field in signTypes where field.name != "hyperliquidChain" {
            if let value = action[field.name] {
                message[field.name] = convertToSendableValue(value, type: field.type)
            }
        }

        return EIP712TypedData(
            domain: makeDomain(
                name: HyperliquidConstants.UserSignedDomain.name,
                version: HyperliquidConstants.UserSignedDomain.version,
                chainId: HyperliquidConstants.UserSignedDomain.signatureChainId,
                verifyingContract: HyperliquidConstants.UserSignedDomain.verifyingContract),
            primaryType: primaryType.rawValue,
            types: [
                "EIP712Domain": eip712DomainTypeFields,
                primaryType.rawValue: signTypes.map { EIP712TypeField(name: $0.name, type: $0.type) },
            ],
            message: message
        )
    }

    private static func makeDomain(name: String, version: String, chainId: UInt64, verifyingContract: String)
        -> EIP712Domain
    {
        EIP712Domain(name: name, version: version, chainId: chainId, verifyingContract: verifyingContract)
    }

    private static func convertToSendableValue(_ value: Sendable, type: String) -> SendableValue {
        // Precise matching first
        switch type {
        case "string", "address": if let s = value as? String { return .string(s) }
        case "bool": if let b = value as? Bool { return .bool(b) }
        case "uint64":
            if let u = value as? UInt64 { return .uint64(u) }
            if let i = value as? Int64 { return .int64(i) }
            if let i = value as? Int { return .int(i) }
        case "uint256":
            if let u = value as? UInt64 { return .uint64(u) }
            if let s = value as? String { return .string(s) }
        case "bytes32":
            if let d = value as? Data { return .data(d) }
        default: break
        }

        // Fallback matching
        if let s = value as? String { return .string(s) }
        if let i = value as? Int { return .int(i) }
        if let i = value as? Int64 { return .int64(i) }
        if let u = value as? UInt64 { return .uint64(u) }
        if let b = value as? Bool { return .bool(b) }
        if let d = value as? Data { return .data(d) }
        return .string(String(describing: value))
    }
}
