import BigInt
import Foundation
import OrderedCollections
import Testing

@testable import HyperliquidSwift

/// Tests for signing logic alignment with Python SDK
/// Reference: Python SDK tests/signing_test.py
/// These tests verify exact signature values match Python SDK output
@Suite("Signing Tests")
struct SigningTests {
    // Test wallet - same as Python SDK: 0x0123456789... This derives address: 0x14dc79964da2c08b23698b3d3cc7ca32193d9955
    static let testPrivateKey = "0x0123456789012345678901234567890123456789012345678901234567890123"

    // MARK: - test_phantom_agent_creation_matches_production

    @Test("Phantom agent creation matches production")
    func phantomAgentCreationMatchesProduction() throws {
        let timestamp: Int64 = 1_677_777_606_040

        let orderRequest = OrderRequest(
            coin: "ETH",
            isBuy: true,
            sz: Decimal(string: "0.0147")!,
            limitPx: Decimal(string: "1670.1")!,
            orderType: .limit(LimitOrderType(tif: .ioc)),
            reduceOnly: false,
            cloid: nil
        )

        let orderWire = try orderRequestToOrderWire(orderRequest, asset: 4)
        let orderAction = orderWiresToOrderAction(orderWires: [orderWire])

        let hash = try ActionHash.compute(
            action: orderAction,
            vaultAddress: nil,
            nonce: timestamp,
            expiresAfter: nil
        )

        // Verify the connectionId matches Python SDK output
        let connectionIdHex = "0x" + hash.hexStringWithoutPrefix
        #expect(connectionIdHex == "0x0fcbeda5ae3c4950a548021552a4fea2226858c4453571bf3f24ba017eac2908")
    }

    // MARK: - test_l1_action_signing_matches

    @Test("L1 action signing matches")
    func l1ActionSigningMatches() async throws {
        let signer = try PrivateKeySigner(privateKeyHex: Self.testPrivateKey)

        // Python: action = {"type": "dummy", "num": float_to_int_for_hashing(1000)}. Key order: type, num
        let action: OrderedDictionary<String, Sendable> = try [
            "type": "dummy",
            "num": Decimal(1000).toIntForHashing(),
        ]

        // Test mainnet signature
        let actionHashMainnet = try ActionHash.compute(
            action: action,
            vaultAddress: nil,
            nonce: 0,
            expiresAfter: nil
        )
        let messageHashMainnet = EIP712.hashTypedDataL1(
            actionHash: actionHashMainnet,
            isMainnet: true
        )
        let signatureMainnet = try await signer.sign(messageHash: messageHashMainnet)

        // Python expected values
        #expect(signatureMainnet.r.hexString == "0x053749d5b30552aeb2fca34b530185976545bb22d0b3ce6f62e31be961a59298")
        #expect(signatureMainnet.s.hexString == "0x755c40ba9bf05223521753995abb2f73ab3229be8ec921f350cb447e384d8ed8")
        #expect(signatureMainnet.v == 27)

        // Test testnet signature
        let actionHashTestnet = try ActionHash.compute(
            action: action,
            vaultAddress: nil,
            nonce: 0,
            expiresAfter: nil
        )
        let messageHashTestnet = EIP712.hashTypedDataL1(
            actionHash: actionHashTestnet,
            isMainnet: false
        )
        let signatureTestnet = try await signer.sign(messageHash: messageHashTestnet)

        // Python expected values
        #expect(signatureTestnet.r.hexString == "0x542af61ef1f429707e3c76c5293c80d01f74ef853e34b76efffcb57e574f9510")
        #expect(signatureTestnet.s.hexString == "0x17b8b32f086e8cdede991f1e2c529f5dd5297cbe8128500e00cbaf766204a613")
        #expect(signatureTestnet.v == 28)
    }

    // MARK: - test_l1_action_signing_order_matches

    @Test("L1 action signing order matches")
    func l1ActionSigningOrderMatches() async throws {
        let signer = try PrivateKeySigner(privateKeyHex: Self.testPrivateKey)

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
        let timestamp: Int64 = 0

        // Test mainnet signature
        let actionHashMainnet = try ActionHash.compute(
            action: orderAction,
            vaultAddress: nil,
            nonce: timestamp,
            expiresAfter: nil
        )
        let messageHashMainnet = EIP712.hashTypedDataL1(
            actionHash: actionHashMainnet,
            isMainnet: true
        )
        let signatureMainnet = try await signer.sign(messageHash: messageHashMainnet)

        // Python expected values
        #expect(signatureMainnet.r.hexString == "0xd65369825a9df5d80099e513cce430311d7d26ddf477f5b3a33d2806b100d78e")
        #expect(signatureMainnet.s.hexString == "0x2b54116ff64054968aa237c20ca9ff68000f977c93289157748a3162b6ea940e")
        #expect(signatureMainnet.v == 28)

        // Test testnet signature
        let actionHashTestnet = try ActionHash.compute(
            action: orderAction,
            vaultAddress: nil,
            nonce: timestamp,
            expiresAfter: nil
        )
        let messageHashTestnet = EIP712.hashTypedDataL1(
            actionHash: actionHashTestnet,
            isMainnet: false
        )
        let signatureTestnet = try await signer.sign(messageHash: messageHashTestnet)

        // Python expected values
        #expect(signatureTestnet.r.hexString == "0x82b2ba28e76b3d761093aaded1b1cdad4960b3af30212b343fb2e6cdfa4e3d54")
        #expect(signatureTestnet.s.hexString == "0x6b53878fc99d26047f4d7e8c90eb98955a109f44209163f52d8dc4278cbbd9f5")
        #expect(signatureTestnet.v == 27)
    }

    // MARK: - test_l1_action_signing_order_with_cloid_matches

    @Test("L1 action signing order with cloid matches")
    func l1ActionSigningOrderWithCloidMatches() async throws {
        let signer = try PrivateKeySigner(privateKeyHex: Self.testPrivateKey)

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
        let timestamp: Int64 = 0

        // Test mainnet signature
        let actionHashMainnet = try ActionHash.compute(
            action: orderAction,
            vaultAddress: nil,
            nonce: timestamp,
            expiresAfter: nil
        )
        let messageHashMainnet = EIP712.hashTypedDataL1(
            actionHash: actionHashMainnet,
            isMainnet: true
        )
        let signatureMainnet = try await signer.sign(messageHash: messageHashMainnet)

        // Python expected values (note: Python shows 0x41ae... without leading zero, we need 0x041ae...)
        #expect(signatureMainnet.r.hexString == "0x041ae18e8239a56cacbc5dad94d45d0b747e5da11ad564077fcac71277a946e3")
        #expect(signatureMainnet.s.hexString == "0x3c61f667e747404fe7eea8f90ab0e76cc12ce60270438b2058324681a00116da")
        #expect(signatureMainnet.v == 27)

        // Test testnet signature
        let actionHashTestnet = try ActionHash.compute(
            action: orderAction,
            vaultAddress: nil,
            nonce: timestamp,
            expiresAfter: nil
        )
        let messageHashTestnet = EIP712.hashTypedDataL1(
            actionHash: actionHashTestnet,
            isMainnet: false
        )
        let signatureTestnet = try await signer.sign(messageHash: messageHashTestnet)

        // Python expected values
        #expect(signatureTestnet.r.hexString == "0xeba0664bed2676fc4e5a743bf89e5c7501aa6d870bdb9446e122c9466c5cd16d")
        #expect(signatureTestnet.s.hexString == "0x7f3e74825c9114bc59086f1eebea2928c190fdfbfde144827cb02b85bbe90988")
        #expect(signatureTestnet.v == 28)
    }

    // MARK: - test_l1_action_signing_matches_with_vault

    @Test("L1 action signing matches with vault")
    func l1ActionSigningMatchesWithVault() async throws {
        let signer = try PrivateKeySigner(privateKeyHex: Self.testPrivateKey)
        let vaultAddress = "0x1719884eb866cb12b2287399b15f7db5e7d775ea"

        // Python: action = {"type": "dummy", "num": float_to_int_for_hashing(1000)}
        let action: OrderedDictionary<String, Sendable> = try [
            "type": "dummy",
            "num": Decimal(1000).toIntForHashing(),
        ]

        // Test mainnet signature
        let actionHashMainnet = try ActionHash.compute(
            action: action,
            vaultAddress: vaultAddress,
            nonce: 0,
            expiresAfter: nil
        )
        let messageHashMainnet = EIP712.hashTypedDataL1(
            actionHash: actionHashMainnet,
            isMainnet: true
        )
        let signatureMainnet = try await signer.sign(messageHash: messageHashMainnet)

        // Python expected values (note: Python shows 0x3c548... without leading zero, we need 0x003c548...)
        #expect(signatureMainnet.r.hexString == "0x003c548db75e479f8012acf3000ca3a6b05606bc2ec0c29c50c515066a326239")
        #expect(signatureMainnet.s.hexString == "0x4d402be7396ce74fbba3795769cda45aec00dc3125a984f2a9f23177b190da2c")
        #expect(signatureMainnet.v == 28)

        // Test testnet signature
        let actionHashTestnet = try ActionHash.compute(
            action: action,
            vaultAddress: vaultAddress,
            nonce: 0,
            expiresAfter: nil
        )
        let messageHashTestnet = EIP712.hashTypedDataL1(
            actionHash: actionHashTestnet,
            isMainnet: false
        )
        let signatureTestnet = try await signer.sign(messageHash: messageHashTestnet)

        // Python expected values
        #expect(signatureTestnet.r.hexString == "0xe281d2fb5c6e25ca01601f878e4d69c965bb598b88fac58e475dd1f5e56c362b")
        #expect(signatureTestnet.s.hexString == "0x7ddad27e9a238d045c035bc606349d075d5c5cd00a6cd1da23ab5c39d4ef0f60")
        #expect(signatureTestnet.v == 27)
    }

    // MARK: - test_l1_action_signing_tpsl_order_matches

    @Test("L1 action signing TPSL order matches")
    func l1ActionSigningTpslOrderMatches() async throws {
        let signer = try PrivateKeySigner(privateKeyHex: Self.testPrivateKey)

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
        let timestamp: Int64 = 0

        // Test mainnet signature
        let actionHashMainnet = try ActionHash.compute(
            action: orderAction,
            vaultAddress: nil,
            nonce: timestamp,
            expiresAfter: nil
        )
        let messageHashMainnet = EIP712.hashTypedDataL1(
            actionHash: actionHashMainnet,
            isMainnet: true
        )
        let signatureMainnet = try await signer.sign(messageHash: messageHashMainnet)

        // Python expected values
        #expect(signatureMainnet.r.hexString == "0x98343f2b5ae8e26bb2587daad3863bc70d8792b09af1841b6fdd530a2065a3f9")
        #expect(signatureMainnet.s.hexString == "0x6b5bb6bb0633b710aa22b721dd9dee6d083646a5f8e581a20b545be6c1feb405")
        #expect(signatureMainnet.v == 27)

        // Test testnet signature
        let actionHashTestnet = try ActionHash.compute(
            action: orderAction,
            vaultAddress: nil,
            nonce: timestamp,
            expiresAfter: nil
        )
        let messageHashTestnet = EIP712.hashTypedDataL1(
            actionHash: actionHashTestnet,
            isMainnet: false
        )
        let signatureTestnet = try await signer.sign(messageHash: messageHashTestnet)

        // Python expected values
        #expect(signatureTestnet.r.hexString == "0x971c554d917c44e0e1b6cc45d8f9404f32172a9d3b3566262347d0302896a2e4")
        #expect(signatureTestnet.s.hexString == "0x206257b104788f80450f8e786c329daa589aa0b32ba96948201ae556d5637eac")
        #expect(signatureTestnet.v == 28)
    }

    // MARK: - test_float_to_int_for_hashing

    @Test("Float to int for hashing")
    func floatToIntForHashing() throws {
        // Test with BigInt to match Python SDK exactly (handles large numbers). Python: assert float_to_int_for_hashing(123123123123) == 12312312312300000000
        #expect(try Decimal(string: "123123123123")!.toIntForHashing() == BigInt("12312312312300000000"))
        // Python: assert float_to_int_for_hashing(0.00001231) == 1231
        #expect(try Decimal(string: "0.00001231")!.toIntForHashing() == BigInt(1231))
        // Python: assert float_to_int_for_hashing(1.033) == 103300000
        #expect(try Decimal(string: "1.033")!.toIntForHashing() == BigInt(103_300_000))

        // Test that too many decimal places throws. Python: with pytest.raises(ValueError): float_to_int_for_hashing(0.000012312312)
        let tooManyDecimals = Decimal(string: "0.000012312312")!
        #expect(throws: HyperliquidError.self) {
            _ = try tooManyDecimals.toIntForHashing()
        }
    }

    // MARK: - test_sign_usd_transfer_action

    @Test("Sign USD transfer action")
    func signUsdTransferAction() async throws {
        let signer = try PrivateKeySigner(privateKeyHex: Self.testPrivateKey)

        let action: [String: Sendable] = [
            "destination": "0x5e9ee1089755c3435139848e47e6635505d5a13a",
            "amount": "1",
            "time": 1_687_816_341_423,
        ]

        // Note: signTypes matches Python's USD_SEND_SIGN_TYPES - does NOT include signatureChainId. EIP712.hashTypedDataUserSigned adds signatureChainId automatically
        let signTypes: [TypedVariable] = [
            TypedVariable(name: "hyperliquidChain", type: "string"),
            TypedVariable(name: "destination", type: "string"),
            TypedVariable(name: "amount", type: "string"),
            TypedVariable(name: "time", type: "uint64"),
        ]

        let messageHash = try EIP712.hashTypedDataUserSigned(
            action: action,
            signTypes: signTypes,
            primaryType: .usdSend,
            isMainnet: false
        )

        // Debug: Print hash to compare with Python. Python hash: 0xe81f1691f350bb9a59d2b40b3d16c9526a8f93407dd72bcb9ea95e291a5de6da
        print("Swift message hash: \(messageHash.hexString)")

        let signature = try await signer.sign(messageHash: messageHash)

        // Python expected values
        #expect(signature.r.hexString == "0x637b37dd731507cdd24f46532ca8ba6eec616952c56218baeff04144e4a77073")
        #expect(signature.s.hexString == "0x11a6a24900e6e314136d2592e2f8d502cd89b7c15b198e1bee043c9589f9fad7")
        #expect(signature.v == 27)
    }

    // MARK: - test_sign_withdraw_from_bridge_action

    @Test("Sign withdraw from bridge action")
    func signWithdrawFromBridgeAction() async throws {
        let signer = try PrivateKeySigner(privateKeyHex: Self.testPrivateKey)

        let action: [String: Sendable] = [
            "destination": "0x5e9ee1089755c3435139848e47e6635505d5a13a",
            "amount": "1",
            "time": 1_687_816_341_423,
        ]

        // Note: signTypes matches Python's WITHDRAW_SIGN_TYPES - does NOT include signatureChainId
        let signTypes: [TypedVariable] = [
            TypedVariable(name: "hyperliquidChain", type: "string"),
            TypedVariable(name: "destination", type: "string"),
            TypedVariable(name: "amount", type: "string"),
            TypedVariable(name: "time", type: "uint64"),
        ]

        let messageHash = try EIP712.hashTypedDataUserSigned(
            action: action,
            signTypes: signTypes,
            primaryType: .withdraw,
            isMainnet: false
        )
        let signature = try await signer.sign(messageHash: messageHash)

        // Python expected values
        #expect(signature.r.hexString == "0x8363524c799e90ce9bc41022f7c39b4e9bdba786e5f9c72b20e43e1462c37cf9")
        #expect(signature.s.hexString == "0x58b1411a775938b83e29182e8ef74975f9054c8e97ebf5ec2dc8d51bfc893881")
        #expect(signature.v == 28)
    }

    // MARK: - test_create_sub_account_action

    @Test("Create sub account action")
    func createSubAccountAction() async throws {
        let signer = try PrivateKeySigner(privateKeyHex: Self.testPrivateKey)

        // Python: action = {"type": "createSubAccount", "name": "example"}
        let action: OrderedDictionary<String, Sendable> = [
            "type": "createSubAccount",
            "name": "example",
        ]

        // Test mainnet signature
        let actionHashMainnet = try ActionHash.compute(
            action: action,
            vaultAddress: nil,
            nonce: 0,
            expiresAfter: nil
        )
        let messageHashMainnet = EIP712.hashTypedDataL1(
            actionHash: actionHashMainnet,
            isMainnet: true
        )
        let signatureMainnet = try await signer.sign(messageHash: messageHashMainnet)

        // Python expected values (note: Python shows 0xb71f7d... without leading zero, we need 0x0b71f7d...)
        #expect(signatureMainnet.r.hexString == "0x51096fe3239421d16b671e192f574ae24ae14329099b6db28e479b86cdd6caa7")
        #expect(signatureMainnet.s.hexString == "0x0b71f7d293af92d3772572afb8b102d167a7cef7473388286bc01f52a5c5b423")
        #expect(signatureMainnet.v == 27)

        // Test testnet signature
        let actionHashTestnet = try ActionHash.compute(
            action: action,
            vaultAddress: nil,
            nonce: 0,
            expiresAfter: nil
        )
        let messageHashTestnet = EIP712.hashTypedDataL1(
            actionHash: actionHashTestnet,
            isMainnet: false
        )
        let signatureTestnet = try await signer.sign(messageHash: messageHashTestnet)

        // Python expected values
        #expect(signatureTestnet.r.hexString == "0xa699e3ed5c2b89628c746d3298b5dc1cca604694c2c855da8bb8250ec8014a5b")
        #expect(signatureTestnet.s.hexString == "0x53f1b8153a301c72ecc655b1c315d64e1dcea3ee58921fd7507e35818fcc1584")
        #expect(signatureTestnet.v == 28)
    }

    // MARK: - test_sub_account_transfer_action

    @Test("Sub account transfer action")
    func subAccountTransferAction() async throws {
        let signer = try PrivateKeySigner(privateKeyHex: Self.testPrivateKey)

        // Python: action = {"type": "subAccountTransfer", "subAccountUser": "...", "isDeposit": True, "usd": 10}
        let action: OrderedDictionary<String, Sendable> = [
            "type": "subAccountTransfer",
            "subAccountUser": "0x1d9470d4b963f552e6f671a81619d395877bf409",
            "isDeposit": true,
            "usd": 10,
        ]

        // Test mainnet signature
        let actionHashMainnet = try ActionHash.compute(
            action: action,
            vaultAddress: nil,
            nonce: 0,
            expiresAfter: nil
        )
        let messageHashMainnet = EIP712.hashTypedDataL1(
            actionHash: actionHashMainnet,
            isMainnet: true
        )
        let signatureMainnet = try await signer.sign(messageHash: messageHashMainnet)

        // Python expected values
        #expect(signatureMainnet.r.hexString == "0x43592d7c6c7d816ece2e206f174be61249d651944932b13343f4d13f306ae602")
        #expect(signatureMainnet.s.hexString == "0x71a926cb5c9a7c01c3359ec4c4c34c16ff8107d610994d4de0e6430e5cc0f4c9")
        #expect(signatureMainnet.v == 28)

        // Test testnet signature
        let actionHashTestnet = try ActionHash.compute(
            action: action,
            vaultAddress: nil,
            nonce: 0,
            expiresAfter: nil
        )
        let messageHashTestnet = EIP712.hashTypedDataL1(
            actionHash: actionHashTestnet,
            isMainnet: false
        )
        let signatureTestnet = try await signer.sign(messageHash: messageHashTestnet)

        // Python expected values (note: Python shows 0xefb08... without leading zero, we need 0x0efb08...)
        #expect(signatureTestnet.r.hexString == "0xe26574013395ad55ee2f4e0575310f003c5bb3351b5425482e2969fa51543927")
        #expect(signatureTestnet.s.hexString == "0x0efb08999196366871f919fd0e138b3a7f30ee33e678df7cfaf203e25f0a4278")
        #expect(signatureTestnet.v == 28)
    }

    // MARK: - test_schedule_cancel_action

    @Test("Schedule cancel action")
    func scheduleCancelAction() async throws {
        let signer = try PrivateKeySigner(privateKeyHex: Self.testPrivateKey)

        // Test without time
        // Python: action = {"type": "scheduleCancel"}
        let actionNoTime: OrderedDictionary<String, Sendable> = [
            "type": "scheduleCancel"
        ]

        // Test mainnet signature (no time)
        let actionHashNoTimeMainnet = try ActionHash.compute(
            action: actionNoTime,
            vaultAddress: nil,
            nonce: 0,
            expiresAfter: nil
        )
        let messageHashNoTimeMainnet = EIP712.hashTypedDataL1(
            actionHash: actionHashNoTimeMainnet,
            isMainnet: true
        )
        let signatureNoTimeMainnet = try await signer.sign(messageHash: messageHashNoTimeMainnet)

        // Python expected values
        #expect(
            signatureNoTimeMainnet.r
                .hexString == "0x6cdfb286702f5917e76cd9b3b8bf678fcc49aec194c02a73e6d4f16891195df9")
        #expect(
            signatureNoTimeMainnet.s
                .hexString == "0x6557ac307fa05d25b8d61f21fb8a938e703b3d9bf575f6717ba21ec61261b2a0")
        #expect(signatureNoTimeMainnet.v == 27)

        // Test testnet signature (no time)
        let actionHashNoTimeTestnet = try ActionHash.compute(
            action: actionNoTime,
            vaultAddress: nil,
            nonce: 0,
            expiresAfter: nil
        )
        let messageHashNoTimeTestnet = EIP712.hashTypedDataL1(
            actionHash: actionHashNoTimeTestnet,
            isMainnet: false
        )
        let signatureNoTimeTestnet = try await signer.sign(messageHash: messageHashNoTimeTestnet)

        // Python expected values
        #expect(
            signatureNoTimeTestnet.r
                .hexString == "0xc75bb195c3f6a4e06b7d395acc20bbb224f6d23ccff7c6a26d327304e6efaeed")
        #expect(
            signatureNoTimeTestnet.s
                .hexString == "0x342f8ede109a29f2c0723bd5efb9e9100e3bbb493f8fb5164ee3d385908233df")
        #expect(signatureNoTimeTestnet.v == 28)

        // Test with time
        // Python: action = {"type": "scheduleCancel", "time": 123456789}
        let actionWithTime: OrderedDictionary<String, Sendable> = [
            "type": "scheduleCancel",
            "time": 123_456_789,
        ]

        // Test mainnet signature (with time)
        let actionHashWithTimeMainnet = try ActionHash.compute(
            action: actionWithTime,
            vaultAddress: nil,
            nonce: 0,
            expiresAfter: nil
        )
        let messageHashWithTimeMainnet = EIP712.hashTypedDataL1(
            actionHash: actionHashWithTimeMainnet,
            isMainnet: true
        )
        let signatureWithTimeMainnet = try await signer.sign(messageHash: messageHashWithTimeMainnet)

        // Python expected values
        #expect(
            signatureWithTimeMainnet.r
                .hexString == "0x609cb20c737945d070716dcc696ba030e9976fcf5edad87afa7d877493109d55")
        #expect(
            signatureWithTimeMainnet.s
                .hexString == "0x16c685d63b5c7a04512d73f183b3d7a00da5406ff1f8aad33f8ae2163bab758b")
        #expect(signatureWithTimeMainnet.v == 28)

        // Test testnet signature (with time)
        let actionHashWithTimeTestnet = try ActionHash.compute(
            action: actionWithTime,
            vaultAddress: nil,
            nonce: 0,
            expiresAfter: nil
        )
        let messageHashWithTimeTestnet = EIP712.hashTypedDataL1(
            actionHash: actionHashWithTimeTestnet,
            isMainnet: false
        )
        let signatureWithTimeTestnet = try await signer.sign(messageHash: messageHashWithTimeTestnet)

        // Python expected values
        #expect(
            signatureWithTimeTestnet.r
                .hexString == "0x4e4f2dbd4107c69783e251b7e1057d9f2b9d11cee213441ccfa2be63516dc5bc")
        #expect(
            signatureWithTimeTestnet.s
                .hexString == "0x706c656b23428c8ba356d68db207e11139ede1670481a9e01ae2dfcdb0e1a678")
        #expect(signatureWithTimeTestnet.v == 27)
    }

    // MARK: - Utility Tests

    @Test("Private key signer derives correct address")
    func privateKeySignerAddress() throws {
        let signer = try PrivateKeySigner(privateKeyHex: Self.testPrivateKey)
        // Expected address from Python SDK: 0x0123456789... derives to 0x14791697260E4c9A71f18484C9f997B308e59325
        #expect(signer.address.lowercased() == "0x14791697260e4c9a71f18484c9f997b308e59325")
    }

    @Test("Cloid creation and validation")
    func cloidCreation() throws {
        // Test from hex string
        guard let cloid = Cloid(rawValue: "0x00000000000000000000000000000001") else {
            throw HyperliquidError.invalidHexString("Invalid cloid")
        }
        // toRaw() returns with 0x prefix (matches Python SDK wire format)
        #expect(cloid.toRaw() == "0x00000000000000000000000000000001")
        // hexString property also returns with 0x prefix
        #expect(cloid.hexString == "0x00000000000000000000000000000001")

        // Test random generation
        let randomCloid = Cloid.random()
        #expect(randomCloid.hexString.hasPrefix("0x"))
        #expect(randomCloid.hexString.count == 34)  // 0x + 32 hex chars
    }

    @Test("Address normalization")
    func addressNormalization() {
        let upper = "0xABCDEF1234567890ABCDEF1234567890ABCDEF12"
        let lower = "0xabcdef1234567890abcdef1234567890abcdef12"

        #expect(upper.normalizedAddress == lower)
        #expect(lower.normalizedAddress == lower)
    }

    @Test("Float to wire conversion")
    func floatToWire() throws {
        #expect(try Decimal(string: "100")!.toWireString() == "100")
        #expect(try Decimal(string: "100.5")!.toWireString() == "100.5")
        #expect(try Decimal(string: "100.50")!.toWireString() == "100.5")
        #expect(try Decimal(string: "100.12345678")!.toWireString() == "100.12345678")  // Exactly 8 decimals
        #expect(try Decimal(string: "-0")!.toWireString() == "0")
        // Values with too many decimals throw precision loss error
        #expect(throws: HyperliquidError.self) {
            try Decimal(string: "100.123456789")!.toWireString()
        }
    }

    @Test("Data hex string conversion")
    func dataHexString() {
        let data = Data([0x01, 0x02, 0x03, 0xAB, 0xCD, 0xEF])
        #expect(data.hexString == "0x010203abcdef")
        #expect(data.hexStringWithoutPrefix == "010203abcdef")
    }
}
