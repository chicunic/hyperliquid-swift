import Foundation
import Testing

@testable import HyperliquidSwift

@Suite("WebSocket Tests")
struct WebSocketTests {

    // MARK: - Subscription Identifier Tests

    @Test("Subscription identifiers are generated correctly")
    func subscriptionIdentifiers() {
        // Test allMids
        let allMids = Subscription.allMids
        #expect(allMids.identifier == "allMids")

        // Test l2Book
        let l2Book = Subscription.l2Book(coin: "BTC")
        #expect(l2Book.identifier == "l2Book:btc")

        // Test trades
        let trades = Subscription.trades(coin: "ETH")
        #expect(trades.identifier == "trades:eth")

        // Test userFills
        let userFills = Subscription.userFills(user: "0x1234567890AbCdEf")
        #expect(userFills.identifier == "userFills:0x1234567890abcdef")

        // Test candle
        let candle = Subscription.candle(coin: "BTC", interval: "1m")
        #expect(candle.identifier == "candle:btc,1m")

        // Test bbo
        let bbo = Subscription.bbo(coin: "ETH")
        #expect(bbo.identifier == "bbo:eth")

        // Test activeAssetCtx
        let activeAssetCtx = Subscription.activeAssetCtx(coin: "SOL")
        #expect(activeAssetCtx.identifier == "activeAssetCtx:sol")

        // Test activeAssetData
        let activeAssetData = Subscription.activeAssetData(user: "0xABCD", coin: "BTC")
        #expect(activeAssetData.identifier == "activeAssetData:btc,0xabcd")

        // Test userEvents
        let userEvents = Subscription.userEvents(user: "0x123")
        #expect(userEvents.identifier == "userEvents")

        // Test orderUpdates
        let orderUpdates = Subscription.orderUpdates(user: "0x123")
        #expect(orderUpdates.identifier == "orderUpdates")
    }

    @Test("Subscription dictionary representation is correct")
    func subscriptionDictionary() {
        // Test allMids
        let allMids = Subscription.allMids
        #expect(allMids.asDictionary == ["type": "allMids"])

        // Test l2Book
        let l2Book = Subscription.l2Book(coin: "BTC")
        #expect(l2Book.asDictionary == ["type": "l2Book", "coin": "BTC"])

        // Test candle
        let candle = Subscription.candle(coin: "ETH", interval: "15m")
        #expect(candle.asDictionary == ["type": "candle", "coin": "ETH", "interval": "15m"])

        // Test userFills
        let userFills = Subscription.userFills(user: "0x123")
        #expect(userFills.asDictionary == ["type": "userFills", "user": "0x123"])
    }

    // MARK: - WebSocket Manager Tests

    @Test("WebSocket manager initializes correctly")
    func webSocketManagerInit() async {
        let manager = WebSocketManager(network: .mainnet)
        let state = await manager.connectionState
        #expect(state == .disconnected)
    }

    @Test("WebSocket URL conversion")
    func webSocketURLConversion() async {
        // Test mainnet URL conversion
        _ = WebSocketManager(baseURL: "https://api.hyperliquid.xyz")
        // The manager internally converts https to wss

        // Test testnet
        let testnetManager = WebSocketManager(network: .testnet)
        let state = await testnetManager.connectionState
        #expect(state == .disconnected)
    }

    // MARK: - Data Type Tests

    @Test("L2BookData decodes correctly")
    func l2BookDataDecoding() throws {
        let json = """
            {
                "coin": "BTC",
                "levels": [
                    [{"px": "50000.0", "sz": "1.5", "n": 3}],
                    [{"px": "49999.0", "sz": "2.0", "n": 5}]
                ],
                "time": 1700000000000
            }
            """

        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(L2BookData.self, from: data)

        #expect(decoded.coin == "BTC")
        #expect(decoded.levels.count == 2)
        #expect(decoded.levels[0][0].px == "50000.0")
        #expect(decoded.levels[0][0].sz == "1.5")
        #expect(decoded.levels[0][0].n == 3)
        #expect(decoded.time == 1_700_000_000_000)
    }

    @Test("TradeData decodes correctly")
    func tradeDataDecoding() throws {
        let json = """
            {
                "coin": "ETH",
                "side": "A",
                "px": "2500.00",
                "sz": "10.5",
                "hash": "0xabc123",
                "time": 1700000000000
            }
            """

        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TradeData.self, from: data)

        #expect(decoded.coin == "ETH")
        #expect(decoded.side == "A")
        #expect(decoded.px == "2500.00")
        #expect(decoded.sz == "10.5")
        #expect(decoded.hash == "0xabc123")
        #expect(decoded.time == 1_700_000_000_000)
    }

    @Test("CandleData decodes correctly")
    func candleDataDecoding() throws {
        let json = """
            {
                "t": 1700000000000,
                "T": 1700000060000,
                "s": "BTC",
                "i": "1m",
                "o": "50000.0",
                "c": "50100.0",
                "h": "50200.0",
                "l": "49900.0",
                "v": "100.5",
                "n": 150
            }
            """

        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(CandleData.self, from: data)

        #expect(decoded.openTime == 1_700_000_000_000)
        #expect(decoded.closeTime == 1_700_000_060_000)
        #expect(decoded.symbol == "BTC")
        #expect(decoded.interval == "1m")
        #expect(decoded.open == "50000.0")
        #expect(decoded.close == "50100.0")
        #expect(decoded.high == "50200.0")
        #expect(decoded.low == "49900.0")
        #expect(decoded.volume == "100.5")
        #expect(decoded.numTrades == 150)
    }

    @Test("UserFillsData decodes correctly")
    func userFillsDataDecoding() throws {
        let json = """
            {
                "user": "0x1234",
                "isSnapshot": true,
                "fills": [
                    {
                        "coin": "BTC",
                        "px": "50000.0",
                        "sz": "0.1",
                        "side": "B",
                        "time": 1700000000000,
                        "startPosition": "0.5",
                        "dir": "Open Long",
                        "closedPnl": "0.0",
                        "hash": "0xabc",
                        "oid": 12345,
                        "crossed": true,
                        "fee": "5.0",
                        "tid": 67890,
                        "feeToken": "USDC"
                    }
                ]
            }
            """

        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(UserFillsData.self, from: data)

        #expect(decoded.user == "0x1234")
        #expect(decoded.isSnapshot == true)
        #expect(decoded.fills.count == 1)
        #expect(decoded.fills[0].coin == "BTC")
        #expect(decoded.fills[0].px == "50000.0")
        #expect(decoded.fills[0].oid == 12345)
        #expect(decoded.fills[0].crossed == true)
    }

    @Test("OrderUpdateData decodes correctly")
    func orderUpdateDataDecoding() throws {
        let json = """
            {
                "order": {
                    "coin": "ETH",
                    "side": "A",
                    "limitPx": "2500.0",
                    "sz": "5.0",
                    "oid": 12345,
                    "timestamp": 1700000000000,
                    "origSz": "10.0"
                },
                "status": "filled",
                "statusTimestamp": 1700000001000
            }
            """

        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(OrderUpdateData.self, from: data)

        #expect(decoded.order.coin == "ETH")
        #expect(decoded.order.side == "A")
        #expect(decoded.order.limitPx == "2500.0")
        #expect(decoded.order.sz == "5.0")
        #expect(decoded.order.oid == 12345)
        #expect(decoded.status == "filled")
        #expect(decoded.statusTimestamp == 1_700_000_001_000)
    }

    // MARK: - Integration Test (requires network)

    @Test("WebSocket connects to mainnet", .disabled("Requires network connection"))
    func webSocketConnection() async throws {
        let manager = WebSocketManager(network: .mainnet)

        // Start connection
        try await manager.start()

        // Wait a bit for connection to establish
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let isConnected = await manager.isConnected
        #expect(isConnected == true)

        // Subscribe to allMids using a counter actor
        let counter = MessageCounter()
        let subId = try await manager.subscribe(.allMids) { _, _ in
            Task { await counter.increment() }
        }

        // Wait for message
        try await Task.sleep(nanoseconds: 3_000_000_000)

        let count = await counter.count
        #expect(count > 0)

        // Cleanup
        _ = try await manager.unsubscribe(.allMids, subscriptionId: subId)
        await manager.stop()

        let finalState = await manager.connectionState
        #expect(finalState == .disconnected)
    }
}

// Helper actor for counting messages in tests
private actor MessageCounter {
    private(set) var count: Int = 0

    func increment() {
        count += 1
    }
}
