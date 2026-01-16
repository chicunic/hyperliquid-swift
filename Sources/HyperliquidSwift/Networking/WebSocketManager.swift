import Foundation

/// WebSocket connection state
public enum WebSocketState: Sendable {
    case disconnected
    case connecting
    case connected
    case disconnecting
}

/// WebSocket error types
public enum WebSocketError: Error, Sendable {
    case notConnected
    case connectionFailed(String)
    case sendFailed(String)
    case invalidMessage
    case alreadySubscribed(String)
}

/// Callback type for subscription messages
public typealias SubscriptionCallback = @Sendable (WsChannel, Any) -> Void

/// Active subscription info
private struct ActiveSubscription: Sendable {
    let callback: SubscriptionCallback
    let subscriptionId: Int
}

/// WebSocket Manager for real-time data
/// Reference: Python SDK hyperliquid/websocket_manager.py
public actor WebSocketManager {
    // MARK: - Properties

    private let baseURL: String
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var state: WebSocketState = .disconnected
    private var subscriptionIdCounter: Int = 0
    private var activeSubscriptions: [String: [ActiveSubscription]] = [:]
    private var queuedSubscriptions: [(Subscription, SubscriptionCallback)] = []
    private var pingTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?

    /// Ping interval in seconds
    private let pingInterval: TimeInterval = 50

    // MARK: - Initialization

    /// Initialize WebSocket manager with base URL
    /// - Parameter baseURL: HTTP base URL (will be converted to ws://)
    public init(baseURL: String) {
        // Convert http(s) to ws(s)
        var wsURL = baseURL
        if wsURL.hasPrefix("https://") {
            wsURL = "wss://" + wsURL.dropFirst(8)
        } else if wsURL.hasPrefix("http://") {
            wsURL = "ws://" + wsURL.dropFirst(7)
        }
        self.baseURL = wsURL + "/ws"
    }

    /// Initialize with network
    public init(network: HyperliquidNetwork) {
        self.init(baseURL: network.baseURL)
    }

    // MARK: - Connection Management

    /// Current connection state
    public var connectionState: WebSocketState {
        state
    }

    /// Check if connected
    public var isConnected: Bool {
        state == .connected
    }

    /// Start the WebSocket connection
    public func start() async throws {
        guard state == .disconnected else { return }

        state = .connecting

        guard let url = URL(string: baseURL) else {
            state = .disconnected
            throw WebSocketError.connectionFailed("Invalid URL: \(baseURL)")
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300

        urlSession = URLSession(configuration: configuration)
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()

        state = .connected

        // Start receiving messages
        startReceiving()

        // Start ping task
        startPing()

        // Process queued subscriptions
        await processQueuedSubscriptions()
    }

    /// Stop the WebSocket connection
    public func stop() async {
        guard state == .connected || state == .connecting else { return }

        state = .disconnecting

        // Cancel tasks
        pingTask?.cancel()
        pingTask = nil
        receiveTask?.cancel()
        receiveTask = nil

        // Close WebSocket
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil

        urlSession?.invalidateAndCancel()
        urlSession = nil

        // Clear subscriptions
        activeSubscriptions.removeAll()
        queuedSubscriptions.removeAll()

        state = .disconnected
    }

    // MARK: - Subscription Management

    /// Subscribe to a channel
    /// - Parameters:
    ///   - subscription: Subscription type
    ///   - callback: Callback to receive messages
    /// - Returns: Subscription ID for unsubscribing
    @discardableResult
    public func subscribe(
        _ subscription: Subscription,
        callback: @escaping SubscriptionCallback
    ) async throws -> Int {
        subscriptionIdCounter += 1
        let subscriptionId = subscriptionIdCounter

        if state != .connected {
            // Queue subscription for when connected
            queuedSubscriptions.append((subscription, callback))
            return subscriptionId
        }

        try await performSubscribe(subscription, callback: callback, subscriptionId: subscriptionId)
        return subscriptionId
    }

    /// Unsubscribe from a channel
    /// - Parameters:
    ///   - subscription: Subscription to remove
    ///   - subscriptionId: ID returned from subscribe
    /// - Returns: True if unsubscribed successfully
    @discardableResult
    public func unsubscribe(_ subscription: Subscription, subscriptionId: Int) async throws -> Bool {
        guard state == .connected else {
            throw WebSocketError.notConnected
        }

        let identifier = subscription.identifier

        guard var subscriptions = activeSubscriptions[identifier] else {
            return false
        }

        let originalCount = subscriptions.count
        subscriptions.removeAll { $0.subscriptionId == subscriptionId }

        if subscriptions.isEmpty {
            // No more subscribers, send unsubscribe
            let message: [String: Any] = [
                "method": "unsubscribe",
                "subscription": subscription.asDictionary,
            ]
            try await sendJSON(message)
            activeSubscriptions.removeValue(forKey: identifier)
        } else {
            activeSubscriptions[identifier] = subscriptions
        }

        return subscriptions.count != originalCount
    }

    // MARK: - Private Methods

    private func performSubscribe(
        _ subscription: Subscription,
        callback: @escaping SubscriptionCallback,
        subscriptionId: Int
    ) async throws {
        let identifier = subscription.identifier

        // Check for single-subscription channels
        if identifier == "userEvents" || identifier == "orderUpdates" {
            if let existing = activeSubscriptions[identifier], !existing.isEmpty {
                throw WebSocketError.alreadySubscribed("Cannot subscribe to \(identifier) multiple times")
            }
        }

        // Add to active subscriptions
        let activeSub = ActiveSubscription(callback: callback, subscriptionId: subscriptionId)
        if activeSubscriptions[identifier] != nil {
            activeSubscriptions[identifier]?.append(activeSub)
        } else {
            activeSubscriptions[identifier] = [activeSub]

            // Send subscribe message only for first subscriber
            let message: [String: Any] = [
                "method": "subscribe",
                "subscription": subscription.asDictionary,
            ]
            try await sendJSON(message)
        }
    }

    private func processQueuedSubscriptions() async {
        let queued = queuedSubscriptions
        queuedSubscriptions.removeAll()

        for (subscription, callback) in queued {
            subscriptionIdCounter += 1
            do {
                try await performSubscribe(subscription, callback: callback, subscriptionId: subscriptionIdCounter)
            } catch {
                print("Failed to process queued subscription: \(error)")
            }
        }
    }

    private func sendJSON(_ object: [String: Any]) async throws {
        guard let webSocketTask, state == .connected else {
            throw WebSocketError.notConnected
        }

        let data = try JSONSerialization.data(withJSONObject: object)
        guard let string = String(data: data, encoding: .utf8) else {
            throw WebSocketError.sendFailed("Failed to encode message")
        }

        try await webSocketTask.send(.string(string))
    }

    private func startPing() {
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(50 * 1_000_000_000))  // 50 seconds

                guard !Task.isCancelled else { break }

                do {
                    try await self?.sendPing()
                } catch {
                    print("Ping failed: \(error)")
                }
            }
        }
    }

    private func sendPing() async throws {
        let message = ["method": "ping"]
        try await sendJSON(message)
    }

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }

                do {
                    let message = try await receiveMessage()
                    await handleMessage(message)
                } catch {
                    if !Task.isCancelled {
                        print("Receive error: \(error)")
                        // Connection lost, try to reconnect
                        await handleDisconnect()
                    }
                    break
                }
            }
        }
    }

    private func receiveMessage() async throws -> String {
        guard let webSocketTask else {
            throw WebSocketError.notConnected
        }

        let message = try await webSocketTask.receive()

        switch message {
        case .string(let text):
            return text
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else {
                throw WebSocketError.invalidMessage
            }
            return text
        @unknown default:
            throw WebSocketError.invalidMessage
        }
    }

    private func handleMessage(_ message: String) async {
        // Handle connection established message
        if message == "Websocket connection established." {
            return
        }

        // Parse JSON
        guard let data = message.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let channelString = json["channel"] as? String
        else {
            return
        }

        // Handle pong
        if channelString == "pong" {
            return
        }

        // Get identifier from message
        guard let identifier = identifierFromMessage(json, channel: channelString) else {
            print("Unknown message identifier for channel: \(channelString)")
            return
        }

        // Get subscribers
        guard let subscribers = activeSubscriptions[identifier] else {
            print("Received message for unknown subscription: \(identifier)")
            return
        }

        // Parse channel
        let channel = WsChannel(rawValue: channelString) ?? .error

        // Get data
        let messageData = json["data"] ?? json

        // Notify subscribers
        for subscriber in subscribers {
            subscriber.callback(channel, messageData)
        }
    }

    /// Convert WebSocket message to identifier
    /// Reference: Python SDK websocket_manager.py:ws_msg_to_identifier
    private func identifierFromMessage(_ json: [String: Any], channel: String) -> String? {
        // Channels with no additional parameters
        switch channel {
        case "pong": return "pong"
        case "allMids": return "allMids"
        case "user": return "userEvents"
        case "orderUpdates": return "orderUpdates"
        default: break
        }

        // Extract data dictionary for parameterized channels
        guard let data = json["data"] as? [String: Any] else {
            // Special case: trades channel has array data
            if channel == "trades",
                let arrayData = json["data"] as? [[String: Any]],
                let firstTrade = arrayData.first,
                let coin = firstTrade["coin"] as? String
            {
                return "trades:\(coin.lowercased())"
            }
            return nil
        }

        // Coin-based channels
        if let coin = data["coin"] as? String {
            switch channel {
            case "l2Book", "bbo":
                return "\(channel):\(coin.lowercased())"
            case "activeAssetCtx", "activeSpotAssetCtx":
                return "activeAssetCtx:\(coin.lowercased())"
            case "activeAssetData":
                guard let user = data["user"] as? String else { return nil }
                return "activeAssetData:\(coin.lowercased()),\(user.lowercased())"
            default: break
            }
        }

        // User-based channels
        if let user = data["user"] as? String {
            switch channel {
            case "userFills", "userFundings", "userNonFundingLedgerUpdates", "webData2":
                return "\(channel):\(user.lowercased())"
            default: break
            }
        }

        // Candle channel (special format)
        if channel == "candle",
            let symbol = data["s"] as? String,
            let interval = data["i"] as? String
        {
            return "candle:\(symbol.lowercased()),\(interval)"
        }

        return nil
    }

    private func handleDisconnect() async {
        state = .disconnected
        webSocketTask = nil

        // Could implement auto-reconnect here if needed
    }
}

// MARK: - Convenience Extensions

extension WebSocketManager {
    /// Subscribe to all mid prices
    @discardableResult
    public func subscribeAllMids(
        callback: @escaping @Sendable ([String: String]) -> Void
    ) async throws -> Int {
        try await subscribe(.allMids) { _, data in
            if let dict = data as? [String: Any],
                let mids = dict["mids"] as? [String: String]
            {
                callback(mids)
            }
        }
    }

    /// Subscribe to L2 order book
    @discardableResult
    public func subscribeL2Book(
        coin: String,
        callback: @escaping @Sendable (L2BookData) -> Void
    ) async throws -> Int {
        try await subscribe(.l2Book(coin: coin)) { _, data in
            if let dict = data as? [String: Any],
                let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                let decoded = try? JSONDecoder().decode(L2BookData.self, from: jsonData)
            {
                callback(decoded)
            }
        }
    }

    /// Subscribe to trades
    @discardableResult
    public func subscribeTrades(
        coin: String,
        callback: @escaping @Sendable ([TradeData]) -> Void
    ) async throws -> Int {
        try await subscribe(.trades(coin: coin)) { _, data in
            if let array = data as? [[String: Any]],
                let jsonData = try? JSONSerialization.data(withJSONObject: array),
                let decoded = try? JSONDecoder().decode([TradeData].self, from: jsonData)
            {
                callback(decoded)
            }
        }
    }

    /// Subscribe to user fills
    @discardableResult
    public func subscribeUserFills(
        user: String,
        callback: @escaping @Sendable (UserFillsData) -> Void
    ) async throws -> Int {
        try await subscribe(.userFills(user: user)) { _, data in
            if let dict = data as? [String: Any],
                let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                let decoded = try? JSONDecoder().decode(UserFillsData.self, from: jsonData)
            {
                callback(decoded)
            }
        }
    }

    /// Subscribe to order updates
    @discardableResult
    public func subscribeOrderUpdates(
        user: String,
        callback: @escaping @Sendable ([OrderUpdateData]) -> Void
    ) async throws -> Int {
        try await subscribe(.orderUpdates(user: user)) { _, data in
            if let array = data as? [[String: Any]],
                let jsonData = try? JSONSerialization.data(withJSONObject: array),
                let decoded = try? JSONDecoder().decode([OrderUpdateData].self, from: jsonData)
            {
                callback(decoded)
            }
        }
    }

    /// Subscribe to candles
    @discardableResult
    public func subscribeCandles(
        coin: String,
        interval: String,
        callback: @escaping @Sendable (CandleData) -> Void
    ) async throws -> Int {
        try await subscribe(.candle(coin: coin, interval: interval)) { _, data in
            if let dict = data as? [String: Any],
                let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                let decoded = try? JSONDecoder().decode(CandleData.self, from: jsonData)
            {
                callback(decoded)
            }
        }
    }
}
