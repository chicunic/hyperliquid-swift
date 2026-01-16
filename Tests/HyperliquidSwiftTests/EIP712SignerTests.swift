import BigInt
import Foundation
import OrderedCollections
import P256K
import Testing

@testable import HyperliquidSwift

// MARK: - Mock EIP712Signer for Testing

/// Mock EIP712Signer that simulates external wallet signing behavior
final class MockEIP712Signer: EIP712Signer, @unchecked Sendable {
    private let privateKey: P256K.Recovery.PrivateKey
    let address: String

    init(privateKeyHex: String) throws {
        guard let keyData = Data(hex: privateKeyHex), keyData.count == 32 else {
            throw HyperliquidError.invalidHexString("Invalid private key")
        }
        privateKey = try P256K.Recovery.PrivateKey(dataRepresentation: keyData)

        let uncompressedKey = try P256K.Recovery.PrivateKey(dataRepresentation: keyData, format: .uncompressed)
        let publicKeyData = uncompressedKey.publicKey.dataRepresentation
        let publicKeyBytes = publicKeyData.count == 65 ? publicKeyData.dropFirst() : publicKeyData
        let addressHash = publicKeyBytes.keccak256
        let addressBytes = addressHash.suffix(20)
        address = "0x" + addressBytes.hexStringWithoutPrefix
    }

    func signTypedData(_ typedData: EIP712TypedData) async throws -> String {
        let messageHash = computeEIP712Hash(typedData)
        let digest = MockMessageDigest(data: messageHash)
        let recoverableSignature = try privateKey.signature(for: digest)
        let compact = try recoverableSignature.compactRepresentation
        let signatureData = compact.signature
        let recoveryId = compact.recoveryId

        guard signatureData.count == 64 else {
            throw HyperliquidError.signingError("Invalid signature length")
        }

        var result = Data()
        result.append(signatureData.prefix(32))
        result.append(signatureData.suffix(32))
        result.append(UInt8(recoveryId + 27))
        return result.hexString
    }

    /// Compute EIP-712 hash from typed data
    private func computeEIP712Hash(_ typedData: EIP712TypedData) -> Data {
        let domainSeparator = computeDomainSeparator(typedData.domain)
        let structHash = computeStructHash(
            primaryType: typedData.primaryType,
            message: typedData.message,
            types: typedData.types
        )

        var data = Data([0x19, 0x01])
        data.append(domainSeparator)
        data.append(structHash)

        return data.keccak256
    }

    private func computeDomainSeparator(_ domain: EIP712Domain) -> Data {
        let typeHash = Data("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)".utf8)
            .keccak256

        var encoded = Data()
        encoded.append(typeHash)
        encoded.append(domain.name.data(using: .utf8)!.keccak256)
        encoded.append(domain.version.data(using: .utf8)!.keccak256)
        encoded.append(encodeUInt256(domain.chainId))
        encoded.append(encodeAddress(domain.verifyingContract))

        return encoded.keccak256
    }

    private func computeStructHash(
        primaryType: String,
        message: [String: SendableValue],
        types: [String: [EIP712TypeField]]
    ) -> Data {
        guard let fields = types[primaryType] else {
            return Data(repeating: 0, count: 32)
        }

        let typeString = primaryType + "(" + fields.map { "\($0.type) \($0.name)" }.joined(separator: ",") + ")"
        let typeHash = typeString.data(using: .utf8)!.keccak256

        var encoded = Data()
        encoded.append(typeHash)

        for field in fields {
            if let value = message[field.name] {
                encoded.append(encodeValue(value, type: field.type))
            } else {
                encoded.append(Data(repeating: 0, count: 32))
            }
        }

        return encoded.keccak256
    }

    private func encodeValue(_ value: SendableValue, type: String) -> Data {
        switch type {
        case "string":
            if case .string(let s) = value {
                return s.data(using: .utf8)!.keccak256
            }
        case "bytes32":
            if case .data(let d) = value {
                return d.leftPadded(to: 32)
            }
        case "address":
            if case .string(let s) = value {
                return encodeAddress(s)
            }
        case "bool":
            if case .bool(let b) = value {
                var data = Data(repeating: 0, count: 31)
                data.append(b ? 1 : 0)
                return data
            }
        case "uint64":
            switch value {
            case .uint64(let u): return encodeUInt256(u)
            case .int64(let i): return encodeUInt256(UInt64(i))
            case .int(let i): return encodeUInt256(UInt64(i))
            default: break
            }
        case "uint256":
            switch value {
            case .uint64(let u): return encodeUInt256(u)
            case .string(let s): return encodeUInt256FromHex(s)
            default: break
            }
        default:
            break
        }
        return Data(repeating: 0, count: 32)
    }

    private func encodeUInt256(_ value: UInt64) -> Data {
        var data = Data(repeating: 0, count: 24)
        var bigEndian = value.bigEndian
        data.append(Data(bytes: &bigEndian, count: 8))
        return data
    }

    private func encodeUInt256FromHex(_ hex: String) -> Data {
        let cleanHex = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard let data = Data(hex: cleanHex) else {
            return Data(repeating: 0, count: 32)
        }
        return data.leftPadded(to: 32)
    }

    private func encodeAddress(_ address: String) -> Data {
        guard let bytes = address.addressToBytes() else {
            return Data(repeating: 0, count: 32)
        }
        return bytes.leftPadded(to: 32)
    }
}

/// Message digest wrapper for P256K
private struct MockMessageDigest: Digest {
    let data: Data

    static var byteCount: Int { 32 }

    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try data.withUnsafeBytes(body)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(data) }

    static func == (lhs: MockMessageDigest, rhs: MockMessageDigest) -> Bool { lhs.data == rhs.data }

    var description: String { data.hexString }

    func makeIterator() -> Data.Iterator { data.makeIterator() }
}

// MARK: - EIP712Signer Tests

/// Tests verifying EIP712Signer produces identical signatures to HyperliquidSigner
@Suite("EIP712Signer Tests")
struct EIP712SignerTests {
    static let testPrivateKey = "0x0123456789012345678901234567890123456789012345678901234567890123"

    // MARK: - L1 Action Tests

    @Test("EIP712Signer L1 action signature matches HyperliquidSigner")
    func eip712SignerL1ActionMatches() async throws {
        let hyperliquidSigner = try PrivateKeySigner(privateKeyHex: Self.testPrivateKey)
        let eip712Signer = try MockEIP712Signer(privateKeyHex: Self.testPrivateKey)

        let action: OrderedDictionary<String, Sendable> = try [
            "type": "dummy",
            "num": Decimal(1000).toIntForHashing(),
        ]

        let actionHash = try ActionHash.compute(
            action: action,
            vaultAddress: nil,
            nonce: 0,
            expiresAfter: nil
        )

        // HyperliquidSigner
        let messageHash = EIP712.hashTypedDataL1(actionHash: actionHash, isMainnet: true)
        let sig1 = try await hyperliquidSigner.sign(messageHash: messageHash)

        // EIP712Signer
        let typedData = EIP712.buildTypedDataL1(actionHash: actionHash, isMainnet: true)
        let sigHex = try await eip712Signer.signTypedData(typedData)
        let sig2 = try Signature.fromHex(sigHex)

        #expect(sig1.r == sig2.r)
        #expect(sig1.s == sig2.s)
        #expect(sig1.v == sig2.v)

        // Python SDK expected values
        #expect(sig2.r.hexString == "0x053749d5b30552aeb2fca34b530185976545bb22d0b3ce6f62e31be961a59298")
        #expect(sig2.s.hexString == "0x755c40ba9bf05223521753995abb2f73ab3229be8ec921f350cb447e384d8ed8")
        #expect(sig2.v == 27)
    }

    @Test("EIP712Signer L1 order signature matches HyperliquidSigner")
    func eip712SignerL1OrderMatches() async throws {
        let hyperliquidSigner = try PrivateKeySigner(privateKeyHex: Self.testPrivateKey)
        let eip712Signer = try MockEIP712Signer(privateKeyHex: Self.testPrivateKey)

        let orderRequest = OrderRequest(
            coin: "ETH",
            isBuy: true,
            sz: Decimal(100),
            limitPx: Decimal(100),
            orderType: .limit(LimitOrderType(tif: .gtc)),
            reduceOnly: false,
            cloid: nil
        )

        let orderWire = try orderRequestToOrderWire(orderRequest, asset: 1)
        let orderAction = orderWiresToOrderAction(orderWires: [orderWire])

        let actionHash = try ActionHash.compute(
            action: orderAction,
            vaultAddress: nil,
            nonce: 0,
            expiresAfter: nil
        )

        // HyperliquidSigner
        let messageHash = EIP712.hashTypedDataL1(actionHash: actionHash, isMainnet: true)
        let sig1 = try await hyperliquidSigner.sign(messageHash: messageHash)

        // EIP712Signer
        let typedData = EIP712.buildTypedDataL1(actionHash: actionHash, isMainnet: true)
        let sigHex = try await eip712Signer.signTypedData(typedData)
        let sig2 = try Signature.fromHex(sigHex)

        #expect(sig1.r == sig2.r)
        #expect(sig1.s == sig2.s)
        #expect(sig1.v == sig2.v)

        // Python SDK expected values
        #expect(sig2.r.hexString == "0xd65369825a9df5d80099e513cce430311d7d26ddf477f5b3a33d2806b100d78e")
        #expect(sig2.s.hexString == "0x2b54116ff64054968aa237c20ca9ff68000f977c93289157748a3162b6ea940e")
        #expect(sig2.v == 28)
    }

    @Test("EIP712Signer L1 action with vault matches HyperliquidSigner")
    func eip712SignerL1ActionWithVaultMatches() async throws {
        let hyperliquidSigner = try PrivateKeySigner(privateKeyHex: Self.testPrivateKey)
        let eip712Signer = try MockEIP712Signer(privateKeyHex: Self.testPrivateKey)
        let vaultAddress = "0x1719884eb866cb12b2287399b15f7db5e7d775ea"

        let action: OrderedDictionary<String, Sendable> = try [
            "type": "dummy",
            "num": Decimal(1000).toIntForHashing(),
        ]

        let actionHash = try ActionHash.compute(
            action: action,
            vaultAddress: vaultAddress,
            nonce: 0,
            expiresAfter: nil
        )

        // HyperliquidSigner
        let messageHash = EIP712.hashTypedDataL1(actionHash: actionHash, isMainnet: true)
        let sig1 = try await hyperliquidSigner.sign(messageHash: messageHash)

        // EIP712Signer
        let typedData = EIP712.buildTypedDataL1(actionHash: actionHash, isMainnet: true)
        let sigHex = try await eip712Signer.signTypedData(typedData)
        let sig2 = try Signature.fromHex(sigHex)

        #expect(sig1.r == sig2.r)
        #expect(sig1.s == sig2.s)
        #expect(sig1.v == sig2.v)

        // Python SDK expected values
        #expect(sig2.r.hexString == "0x003c548db75e479f8012acf3000ca3a6b05606bc2ec0c29c50c515066a326239")
        #expect(sig2.s.hexString == "0x4d402be7396ce74fbba3795769cda45aec00dc3125a984f2a9f23177b190da2c")
        #expect(sig2.v == 28)
    }

    @Test("EIP712Signer L1 order with cloid matches HyperliquidSigner")
    func eip712SignerL1OrderWithCloidMatches() async throws {
        let hyperliquidSigner = try PrivateKeySigner(privateKeyHex: Self.testPrivateKey)
        let eip712Signer = try MockEIP712Signer(privateKeyHex: Self.testPrivateKey)

        guard let cloid = Cloid(rawValue: "0x00000000000000000000000000000001") else {
            throw HyperliquidError.invalidHexString("Invalid cloid")
        }

        let orderRequest = OrderRequest(
            coin: "ETH",
            isBuy: true,
            sz: Decimal(100),
            limitPx: Decimal(100),
            orderType: .limit(LimitOrderType(tif: .gtc)),
            reduceOnly: false,
            cloid: cloid
        )

        let orderWire = try orderRequestToOrderWire(orderRequest, asset: 1)
        let orderAction = orderWiresToOrderAction(orderWires: [orderWire])

        let actionHash = try ActionHash.compute(
            action: orderAction,
            vaultAddress: nil,
            nonce: 0,
            expiresAfter: nil
        )

        // HyperliquidSigner
        let messageHash = EIP712.hashTypedDataL1(actionHash: actionHash, isMainnet: true)
        let sig1 = try await hyperliquidSigner.sign(messageHash: messageHash)

        // EIP712Signer
        let typedData = EIP712.buildTypedDataL1(actionHash: actionHash, isMainnet: true)
        let sigHex = try await eip712Signer.signTypedData(typedData)
        let sig2 = try Signature.fromHex(sigHex)

        #expect(sig1.r == sig2.r)
        #expect(sig1.s == sig2.s)
        #expect(sig1.v == sig2.v)

        // Python SDK expected values
        #expect(sig2.r.hexString == "0x041ae18e8239a56cacbc5dad94d45d0b747e5da11ad564077fcac71277a946e3")
        #expect(sig2.s.hexString == "0x3c61f667e747404fe7eea8f90ab0e76cc12ce60270438b2058324681a00116da")
        #expect(sig2.v == 27)
    }

    @Test("EIP712Signer L1 TPSL order matches HyperliquidSigner")
    func eip712SignerL1TpslOrderMatches() async throws {
        let hyperliquidSigner = try PrivateKeySigner(privateKeyHex: Self.testPrivateKey)
        let eip712Signer = try MockEIP712Signer(privateKeyHex: Self.testPrivateKey)

        let orderRequest = OrderRequest(
            coin: "ETH",
            isBuy: true,
            sz: Decimal(100),
            limitPx: Decimal(100),
            orderType: .trigger(TriggerOrderType(triggerPx: Decimal(103), isMarket: true, tpsl: .stopLoss)),
            reduceOnly: false,
            cloid: nil
        )

        let orderWire = try orderRequestToOrderWire(orderRequest, asset: 1)
        let orderAction = orderWiresToOrderAction(orderWires: [orderWire])

        let actionHash = try ActionHash.compute(
            action: orderAction,
            vaultAddress: nil,
            nonce: 0,
            expiresAfter: nil
        )

        // HyperliquidSigner
        let messageHash = EIP712.hashTypedDataL1(actionHash: actionHash, isMainnet: true)
        let sig1 = try await hyperliquidSigner.sign(messageHash: messageHash)

        // EIP712Signer
        let typedData = EIP712.buildTypedDataL1(actionHash: actionHash, isMainnet: true)
        let sigHex = try await eip712Signer.signTypedData(typedData)
        let sig2 = try Signature.fromHex(sigHex)

        #expect(sig1.r == sig2.r)
        #expect(sig1.s == sig2.s)
        #expect(sig1.v == sig2.v)

        // Python SDK expected values
        #expect(sig2.r.hexString == "0x98343f2b5ae8e26bb2587daad3863bc70d8792b09af1841b6fdd530a2065a3f9")
        #expect(sig2.s.hexString == "0x6b5bb6bb0633b710aa22b721dd9dee6d083646a5f8e581a20b545be6c1feb405")
        #expect(sig2.v == 27)
    }

    @Test("EIP712Signer L1 create sub account matches HyperliquidSigner")
    func eip712SignerL1CreateSubAccountMatches() async throws {
        let hyperliquidSigner = try PrivateKeySigner(privateKeyHex: Self.testPrivateKey)
        let eip712Signer = try MockEIP712Signer(privateKeyHex: Self.testPrivateKey)

        let action: OrderedDictionary<String, Sendable> = [
            "type": "createSubAccount",
            "name": "example",
        ]

        let actionHash = try ActionHash.compute(
            action: action,
            vaultAddress: nil,
            nonce: 0,
            expiresAfter: nil
        )

        // HyperliquidSigner
        let messageHash = EIP712.hashTypedDataL1(actionHash: actionHash, isMainnet: true)
        let sig1 = try await hyperliquidSigner.sign(messageHash: messageHash)

        // EIP712Signer
        let typedData = EIP712.buildTypedDataL1(actionHash: actionHash, isMainnet: true)
        let sigHex = try await eip712Signer.signTypedData(typedData)
        let sig2 = try Signature.fromHex(sigHex)

        #expect(sig1.r == sig2.r)
        #expect(sig1.s == sig2.s)
        #expect(sig1.v == sig2.v)

        // Python SDK expected values
        #expect(sig2.r.hexString == "0x51096fe3239421d16b671e192f574ae24ae14329099b6db28e479b86cdd6caa7")
        #expect(sig2.s.hexString == "0x0b71f7d293af92d3772572afb8b102d167a7cef7473388286bc01f52a5c5b423")
        #expect(sig2.v == 27)
    }

    @Test("EIP712Signer L1 sub account transfer matches HyperliquidSigner")
    func eip712SignerL1SubAccountTransferMatches() async throws {
        let hyperliquidSigner = try PrivateKeySigner(privateKeyHex: Self.testPrivateKey)
        let eip712Signer = try MockEIP712Signer(privateKeyHex: Self.testPrivateKey)

        let action: OrderedDictionary<String, Sendable> = [
            "type": "subAccountTransfer",
            "subAccountUser": "0x1d9470d4b963f552e6f671a81619d395877bf409",
            "isDeposit": true,
            "usd": 10,
        ]

        let actionHash = try ActionHash.compute(
            action: action,
            vaultAddress: nil,
            nonce: 0,
            expiresAfter: nil
        )

        // HyperliquidSigner
        let messageHash = EIP712.hashTypedDataL1(actionHash: actionHash, isMainnet: true)
        let sig1 = try await hyperliquidSigner.sign(messageHash: messageHash)

        // EIP712Signer
        let typedData = EIP712.buildTypedDataL1(actionHash: actionHash, isMainnet: true)
        let sigHex = try await eip712Signer.signTypedData(typedData)
        let sig2 = try Signature.fromHex(sigHex)

        #expect(sig1.r == sig2.r)
        #expect(sig1.s == sig2.s)
        #expect(sig1.v == sig2.v)

        // Python SDK expected values
        #expect(sig2.r.hexString == "0x43592d7c6c7d816ece2e206f174be61249d651944932b13343f4d13f306ae602")
        #expect(sig2.s.hexString == "0x71a926cb5c9a7c01c3359ec4c4c34c16ff8107d610994d4de0e6430e5cc0f4c9")
        #expect(sig2.v == 28)
    }

    @Test("EIP712Signer L1 schedule cancel matches HyperliquidSigner")
    func eip712SignerL1ScheduleCancelMatches() async throws {
        let hyperliquidSigner = try PrivateKeySigner(privateKeyHex: Self.testPrivateKey)
        let eip712Signer = try MockEIP712Signer(privateKeyHex: Self.testPrivateKey)

        // Test without time
        let actionNoTime: OrderedDictionary<String, Sendable> = [
            "type": "scheduleCancel"
        ]

        let actionHashNoTime = try ActionHash.compute(
            action: actionNoTime,
            vaultAddress: nil,
            nonce: 0,
            expiresAfter: nil
        )

        // HyperliquidSigner
        let messageHashNoTime = EIP712.hashTypedDataL1(actionHash: actionHashNoTime, isMainnet: true)
        let sig1NoTime = try await hyperliquidSigner.sign(messageHash: messageHashNoTime)

        // EIP712Signer
        let typedDataNoTime = EIP712.buildTypedDataL1(actionHash: actionHashNoTime, isMainnet: true)
        let sigHexNoTime = try await eip712Signer.signTypedData(typedDataNoTime)
        let sig2NoTime = try Signature.fromHex(sigHexNoTime)

        #expect(sig1NoTime.r == sig2NoTime.r)
        #expect(sig1NoTime.s == sig2NoTime.s)
        #expect(sig1NoTime.v == sig2NoTime.v)

        // Python SDK expected values (no time)
        #expect(sig2NoTime.r.hexString == "0x6cdfb286702f5917e76cd9b3b8bf678fcc49aec194c02a73e6d4f16891195df9")
        #expect(sig2NoTime.s.hexString == "0x6557ac307fa05d25b8d61f21fb8a938e703b3d9bf575f6717ba21ec61261b2a0")
        #expect(sig2NoTime.v == 27)

        // Test with time
        let actionWithTime: OrderedDictionary<String, Sendable> = [
            "type": "scheduleCancel",
            "time": 123_456_789,
        ]

        let actionHashWithTime = try ActionHash.compute(
            action: actionWithTime,
            vaultAddress: nil,
            nonce: 0,
            expiresAfter: nil
        )

        // HyperliquidSigner
        let messageHashWithTime = EIP712.hashTypedDataL1(actionHash: actionHashWithTime, isMainnet: true)
        let sig1WithTime = try await hyperliquidSigner.sign(messageHash: messageHashWithTime)

        // EIP712Signer
        let typedDataWithTime = EIP712.buildTypedDataL1(actionHash: actionHashWithTime, isMainnet: true)
        let sigHexWithTime = try await eip712Signer.signTypedData(typedDataWithTime)
        let sig2WithTime = try Signature.fromHex(sigHexWithTime)

        #expect(sig1WithTime.r == sig2WithTime.r)
        #expect(sig1WithTime.s == sig2WithTime.s)
        #expect(sig1WithTime.v == sig2WithTime.v)

        // Python SDK expected values (with time)
        #expect(sig2WithTime.r.hexString == "0x609cb20c737945d070716dcc696ba030e9976fcf5edad87afa7d877493109d55")
        #expect(sig2WithTime.s.hexString == "0x16c685d63b5c7a04512d73f183b3d7a00da5406ff1f8aad33f8ae2163bab758b")
        #expect(sig2WithTime.v == 28)
    }

    // MARK: - User-Signed Action Tests

    @Test("EIP712Signer user-signed USD transfer matches HyperliquidSigner")
    func eip712SignerUserSignedUsdTransferMatches() async throws {
        let hyperliquidSigner = try PrivateKeySigner(privateKeyHex: Self.testPrivateKey)
        let eip712Signer = try MockEIP712Signer(privateKeyHex: Self.testPrivateKey)

        let action: [String: Sendable] = [
            "destination": "0x5e9ee1089755c3435139848e47e6635505d5a13a",
            "amount": "1",
            "time": 1_687_816_341_423,
        ]

        let signTypes: [TypedVariable] = [
            TypedVariable(name: "hyperliquidChain", type: "string"),
            TypedVariable(name: "destination", type: "string"),
            TypedVariable(name: "amount", type: "string"),
            TypedVariable(name: "time", type: "uint64"),
        ]

        // HyperliquidSigner
        let messageHash = try EIP712.hashTypedDataUserSigned(
            action: action,
            signTypes: signTypes,
            primaryType: .usdSend,
            isMainnet: false
        )
        let sig1 = try await hyperliquidSigner.sign(messageHash: messageHash)

        // EIP712Signer
        let typedData = EIP712.buildTypedDataUserSigned(
            action: action,
            signTypes: signTypes,
            primaryType: .usdSend,
            isMainnet: false
        )
        let sigHex = try await eip712Signer.signTypedData(typedData)
        let sig2 = try Signature.fromHex(sigHex)

        #expect(sig1.r == sig2.r)
        #expect(sig1.s == sig2.s)
        #expect(sig1.v == sig2.v)

        // Python SDK expected values
        #expect(sig2.r.hexString == "0x637b37dd731507cdd24f46532ca8ba6eec616952c56218baeff04144e4a77073")
        #expect(sig2.s.hexString == "0x11a6a24900e6e314136d2592e2f8d502cd89b7c15b198e1bee043c9589f9fad7")
        #expect(sig2.v == 27)
    }

    @Test("EIP712Signer user-signed withdraw matches HyperliquidSigner")
    func eip712SignerUserSignedWithdrawMatches() async throws {
        let hyperliquidSigner = try PrivateKeySigner(privateKeyHex: Self.testPrivateKey)
        let eip712Signer = try MockEIP712Signer(privateKeyHex: Self.testPrivateKey)

        let action: [String: Sendable] = [
            "destination": "0x5e9ee1089755c3435139848e47e6635505d5a13a",
            "amount": "1",
            "time": 1_687_816_341_423,
        ]

        let signTypes: [TypedVariable] = [
            TypedVariable(name: "hyperliquidChain", type: "string"),
            TypedVariable(name: "destination", type: "string"),
            TypedVariable(name: "amount", type: "string"),
            TypedVariable(name: "time", type: "uint64"),
        ]

        // HyperliquidSigner
        let messageHash = try EIP712.hashTypedDataUserSigned(
            action: action,
            signTypes: signTypes,
            primaryType: .withdraw,
            isMainnet: false
        )
        let sig1 = try await hyperliquidSigner.sign(messageHash: messageHash)

        // EIP712Signer
        let typedData = EIP712.buildTypedDataUserSigned(
            action: action,
            signTypes: signTypes,
            primaryType: .withdraw,
            isMainnet: false
        )
        let sigHex = try await eip712Signer.signTypedData(typedData)
        let sig2 = try Signature.fromHex(sigHex)

        #expect(sig1.r == sig2.r)
        #expect(sig1.s == sig2.s)
        #expect(sig1.v == sig2.v)

        // Python SDK expected values
        #expect(sig2.r.hexString == "0x8363524c799e90ce9bc41022f7c39b4e9bdba786e5f9c72b20e43e1462c37cf9")
        #expect(sig2.s.hexString == "0x58b1411a775938b83e29182e8ef74975f9054c8e97ebf5ec2dc8d51bfc893881")
        #expect(sig2.v == 28)
    }

    // MARK: - Utility Tests

    @Test("Signature hex string round-trip")
    func signatureHexRoundTrip() throws {
        let original = Signature(
            r: Data(repeating: 0xAB, count: 32),
            s: Data(repeating: 0xCD, count: 32),
            v: 27
        )

        let hexString = original.toHexString()
        let restored = try Signature.fromHex(hexString)

        #expect(original.r == restored.r)
        #expect(original.s == restored.s)
        #expect(original.v == restored.v)
    }

    @Test("EIP712TypedData toDictionary format")
    func typedDataToDictionary() throws {
        let action: OrderedDictionary<String, Sendable> = try [
            "type": "dummy",
            "num": Decimal(1000).toIntForHashing(),
        ]

        let actionHash = try ActionHash.compute(
            action: action,
            vaultAddress: nil,
            nonce: 0,
            expiresAfter: nil
        )

        let typedData = EIP712.buildTypedDataL1(actionHash: actionHash, isMainnet: true)
        let dict = typedData.toDictionary()

        // Verify structure matches what wallet SDKs expect
        #expect(dict["primaryType"] as? String == "Agent")

        let domain = dict["domain"] as? [String: Sendable]
        #expect(domain?["name"] as? String == "Exchange")
        #expect(domain?["version"] as? String == "1")
        #expect(domain?["chainId"] as? UInt64 == 1337)

        let types = dict["types"] as? [String: Sendable]
        #expect(types?["EIP712Domain"] != nil)
        #expect(types?["Agent"] != nil)

        let message = dict["message"] as? [String: Sendable]
        #expect(message?["source"] as? String == "a")
        #expect(message?["connectionId"] != nil)
    }
}
