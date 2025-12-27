import Foundation
@testable import HyperliquidSwift
import Testing

/// Tests for Exchange API
/// Note: Most tests require a funded testnet account
@Suite("Exchange API Tests")
struct ExchangeAPITests {
    // Test wallet from Python SDK tests
    static let testPrivateKey = "0x0123456789012345678901234567890123456789012345678901234567890123"

    @Test("Create Exchange API instance")
    func createExchangeAPI() async throws {
        let signer = try PrivateKeySigner(privateKeyHex: Self.testPrivateKey)
        let exchange = try await ExchangeAPI(signer: signer, network: .testnet)
        // Should not throw
    }

    @Test("Client initialization with private key")
    func clientWithPrivateKey() async throws {
        let client = try HyperliquidClient.testnet(privateKey: Self.testPrivateKey)

        #expect(client.walletAddress != nil)
        #expect(client.walletAddress?.hasPrefix("0x") == true)
    }

    @Test("Client Info API access")
    func clientInfoAPI() async throws {
        let client = HyperliquidClient.mainnet
        let infoAPI = try await client.infoAPI()

        let mids = try await infoAPI.allMids()
        #expect(!mids.isEmpty)
    }

    @Test("Order request to wire format")
    func orderRequestToWire() throws {
        let order = OrderRequest(
            coin: "BTC",
            isBuy: true,
            sz: Decimal(string: "0.001")!,
            limitPx: Decimal(string: "50000")!,
            orderType: .limit(LimitOrderType(tif: .gtc)),
            reduceOnly: false
        )

        let wire = try orderRequestToOrderWire(order, asset: 0)

        #expect(wire.a == 0)
        #expect(wire.b == true)
        #expect(wire.p == "50000")
        #expect(wire.s == "0.001")
        #expect(wire.r == false)

        // Verify order type wire format
        let typeDict = wire.t.asDictionary
        #expect(typeDict["limit"] != nil)
    }

    @Test("Modify request construction")
    func modifyRequestConstruction() throws {
        let order = OrderRequest(
            coin: "ETH",
            isBuy: false,
            sz: Decimal(string: "0.5")!,
            limitPx: Decimal(string: "3000")!,
            orderType: .limit(LimitOrderType(tif: .alo)),
            reduceOnly: true
        )

        let modify = ModifyRequest(
            oidOrCloid: .oid(12345),
            order: order
        )

        #expect(modify.order.coin == "ETH")
        #expect(modify.order.isBuy == false)

        if case let .oid(oid) = modify.oidOrCloid {
            #expect(oid == 12345)
        } else {
            Issue.record("Expected oid type")
        }
    }

    @Test("Cancel request construction")
    func cancelRequestConstruction() {
        let cancel = CancelRequest(coin: "BTC", oid: 67890)
        #expect(cancel.coin == "BTC")
        #expect(cancel.oid == 67890)

        let cloid = Cloid.random()
        let cancelByCloid = CancelByCloidRequest(coin: "ETH", cloid: cloid)
        #expect(cancelByCloid.coin == "ETH")
    }

    @Test("Builder info construction")
    func builderInfoConstruction() {
        let builder = BuilderInfo(
            address: "0x1234567890123456789012345678901234567890",
            fee: 10
        )

        let dict = builder.asDictionary
        #expect(dict["b"] as? String == "0x1234567890123456789012345678901234567890")
        #expect(dict["f"] as? Int == 10)
    }

    @Test("Order grouping options")
    func orderGroupingOptions() {
        #expect(OrderGrouping.na.rawValue == "na")
        #expect(OrderGrouping.normalTpsl.rawValue == "normalTpsl")
        #expect(OrderGrouping.positionTpsl.rawValue == "positionTpsl")
    }

}
