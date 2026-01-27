import Foundation

/// Info API for querying Hyperliquid data. Reference: Python SDK hyperliquid/info.py
public actor InfoAPI {
    private let httpClient: HTTPClient
    private let network: HyperliquidNetwork

    // Caches for asset/coin mapping
    private var coinToAsset: [String: Int] = [:]
    private var nameToCoin: [String: String] = [:]
    private var assetToSzDecimals: [Int: Int] = [:]

    // WebSocket manager
    private var wsManager: WebSocketManager?

    /// Initialize Info API with network
    public init(
        network: HyperliquidNetwork = .mainnet,
        meta: Meta? = nil,
        spotMeta: SpotMeta? = nil
    ) {
        self.network = network
        httpClient = HTTPClient(baseURL: network.baseURL)
    }

    /// Async initializer that loads metadata
    public init(
        network: HyperliquidNetwork = .mainnet,
        skipWs: Bool = true,
        meta: Meta? = nil,
        spotMeta: SpotMeta? = nil
    ) async throws {
        self.network = network
        httpClient = HTTPClient(baseURL: network.baseURL)

        if !skipWs {
            let manager = WebSocketManager(network: network)
            try await manager.start()
            wsManager = manager
        }

        // Load spot meta
        let loadedSpotMeta: SpotMeta
        if let spotMeta {
            loadedSpotMeta = spotMeta
        } else {
            loadedSpotMeta = try await self.spotMeta()
        }

        // Set up spot asset mappings (spot assets start at 10000)
        for spotInfo in loadedSpotMeta.universe {
            let asset = spotInfo.index + 10000
            coinToAsset[spotInfo.name] = asset
            nameToCoin[spotInfo.name] = spotInfo.name

            let baseToken = loadedSpotMeta.tokens[spotInfo.tokens[0]]
            let quoteToken = loadedSpotMeta.tokens[spotInfo.tokens[1]]
            assetToSzDecimals[asset] = baseToken.szDecimals

            let pairName = "\(baseToken.name)/\(quoteToken.name)"
            if nameToCoin[pairName] == nil {
                nameToCoin[pairName] = spotInfo.name
            }
        }

        // Load perp meta
        let loadedMeta: Meta
        if let meta {
            loadedMeta = meta
        } else {
            loadedMeta = try await self.meta()
        }
        setPerpMeta(loadedMeta, offset: 0)
    }

    private func setPerpMeta(_ meta: Meta, offset: Int) {
        for (index, assetInfo) in meta.universe.enumerated() {
            let asset = index + offset
            coinToAsset[assetInfo.name] = asset
            nameToCoin[assetInfo.name] = assetInfo.name
            assetToSzDecimals[asset] = assetInfo.szDecimals
        }
    }

    // MARK: - Asset/Coin Mapping

    public func nameToAsset(_ name: String) -> Int? {
        guard let coin = nameToCoin[name] else { return nil }
        return coinToAsset[coin]
    }

    public func getCoin(for name: String) -> String? {
        nameToCoin[name]
    }

    // MARK: - Helper

    private func makePayload(type: String, additional: [String: Sendable] = [:]) -> [String: Sendable] {
        var payload = additional
        payload["type"] = type
        return payload
    }

    // MARK: - Market Data APIs

    public func allMids(dex: String = "") async throws -> [String: String] {
        try await httpClient.postInfo(makePayload(type: "allMids", additional: ["dex": dex]))
    }

    public func meta(dex: String = "") async throws -> Meta {
        try await httpClient.postInfo(makePayload(type: "meta", additional: ["dex": dex]))
    }

    public func spotMeta() async throws -> SpotMeta {
        try await httpClient.postInfo(makePayload(type: "spotMeta"))
    }

    public func metaAndAssetCtxs(dex: String = "") async throws -> MetaAndAssetCtxs {
        let data = try await httpClient.postInfoRaw(makePayload(type: "metaAndAssetCtxs", additional: ["dex": dex]))
        return try decodeTuple(data, type1: Meta.self, type2: [PerpAssetCtx].self) {
            MetaAndAssetCtxs(meta: $0, assetCtxs: $1)
        }
    }

    public func spotMetaAndAssetCtxs() async throws -> SpotMetaAndAssetCtxs {
        let data = try await httpClient.postInfoRaw(makePayload(type: "spotMetaAndAssetCtxs"))
        return try decodeTuple(data, type1: SpotMeta.self, type2: [SpotAssetCtx].self) {
            SpotMetaAndAssetCtxs(meta: $0, assetCtxs: $1)
        }
    }

    private func decodeTuple<T1: Decodable, T2: Decodable, R>(
        _ data: Data, type1: T1.Type, type2: T2.Type, combine: (T1, T2) -> R
    ) throws -> R {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [Any],
            array.count >= 2,
            let dict1 = array[0] as? [String: Any]
        else {
            throw HyperliquidError.decodingError(underlying: NSError(domain: "InfoAPI", code: -1))
        }

        let dict2 = array[1]

        let data1 = try JSONSerialization.data(withJSONObject: dict1)
        let val1 = try JSONDecoder().decode(T1.self, from: data1)

        let data2 = try JSONSerialization.data(withJSONObject: dict2)
        let val2 = try JSONDecoder().decode(T2.self, from: data2)

        return combine(val1, val2)
    }

    public func l2Snapshot(name: String) async throws -> L2Book {
        try await httpClient.postInfo(makePayload(type: "l2Book", additional: ["coin": mapCoin(name)]))
    }

    public func candlesSnapshot(name: String, interval: String, startTime: Int64, endTime: Int64) async throws
        -> [Candle]
    {
        let req: [String: Sendable] = [
            "coin": mapCoin(name),
            "interval": interval,
            "startTime": startTime,
            "endTime": endTime,
        ]
        return try await httpClient.postInfo(makePayload(type: "candleSnapshot", additional: ["req": req]))
    }

    public func fundingHistory(name: String, startTime: Int64, endTime: Int64? = nil) async throws
        -> [FundingHistoryEntry]
    {
        var additional: [String: Sendable] = ["coin": mapCoin(name), "startTime": startTime]
        if let endTime { additional["endTime"] = endTime }
        return try await httpClient.postInfo(makePayload(type: "fundingHistory", additional: additional))
    }

    /// Retrieve all perp DEXs
    /// - Returns: Array of PerpDex objects. The first element is nil representing the main crypto DEX.
    public func perpDexs() async throws -> [PerpDex?] {
        try await httpClient.postInfo(makePayload(type: "perpDexs"))
    }

    // MARK: - User Account APIs

    public func userState(address: String, dex: String = "") async throws -> UserState {
        try await httpClient.postInfo(
            makePayload(type: "clearinghouseState", additional: ["user": address.normalizedAddress, "dex": dex]))
    }

    public func spotUserState(address: String) async throws -> SpotUserState {
        try await httpClient.postInfo(
            makePayload(type: "spotClearinghouseState", additional: ["user": address.normalizedAddress]))
    }

    public func openOrders(address: String, dex: String = "") async throws -> [OpenOrder] {
        try await httpClient.postInfo(
            makePayload(type: "openOrders", additional: ["user": address.normalizedAddress, "dex": dex]))
    }

    public func frontendOpenOrders(address: String, dex: String = "") async throws -> [FrontendOpenOrder] {
        try await httpClient.postInfo(
            makePayload(type: "frontendOpenOrders", additional: ["user": address.normalizedAddress, "dex": dex]))
    }

    public func userFills(address: String) async throws -> [Fill] {
        try await httpClient.postInfo(makePayload(type: "userFills", additional: ["user": address.normalizedAddress]))
    }

    public func userFillsByTime(address: String, startTime: Int64, endTime: Int64? = nil, aggregateByTime: Bool = false)
        async throws -> [Fill]
    {
        var additional: [String: Sendable] = [
            "user": address.normalizedAddress, "startTime": startTime, "aggregateByTime": aggregateByTime,
        ]
        if let endTime { additional["endTime"] = endTime }
        return try await httpClient.postInfo(makePayload(type: "userFillsByTime", additional: additional))
    }

    public func userFundingHistory(user: String, startTime: Int64, endTime: Int64? = nil) async throws -> [UserFunding]
    {
        var additional: [String: Sendable] = ["user": user.normalizedAddress, "startTime": startTime]
        if let endTime { additional["endTime"] = endTime }
        return try await httpClient.postInfo(makePayload(type: "userFunding", additional: additional))
    }

    public func userFees(address: String) async throws -> UserFees {
        try await httpClient.postInfo(makePayload(type: "userFees", additional: ["user": address.normalizedAddress]))
    }

    public func userStakingSummary(address: String) async throws -> StakingSummary {
        try await httpClient.postInfo(
            makePayload(type: "delegatorSummary", additional: ["user": address.normalizedAddress]))
    }

    public func delegatorSummary(address: String) async throws -> StakingSummary {
        try await userStakingSummary(address: address)
    }

    public func userStakingDelegations(address: String) async throws -> [StakingDelegation] {
        try await httpClient.postInfo(makePayload(type: "delegations", additional: ["user": address.normalizedAddress]))
    }

    public func userStakingRewards(address: String) async throws -> [StakingReward] {
        try await httpClient.postInfo(
            makePayload(type: "delegatorRewards", additional: ["user": address.normalizedAddress]))
    }

    public func delegatorHistory(user: String) async throws -> [DelegatorHistoryEntry] {
        try await httpClient.postInfo(
            makePayload(type: "delegatorHistory", additional: ["user": user.normalizedAddress]))
    }

    public func queryOrderByOid(user: String, oid: Int64) async throws -> OrderStatus {
        try await httpClient.postInfo(
            makePayload(type: "orderStatus", additional: ["user": user.normalizedAddress, "oid": oid]))
    }

    public func orderStatus(address: String, oid: Int64) async throws -> OrderStatus {
        try await queryOrderByOid(user: address, oid: oid)
    }

    public func queryOrderByCloid(user: String, cloid: Cloid) async throws -> OrderStatus {
        try await httpClient.postInfo(
            makePayload(type: "orderStatus", additional: ["user": user.normalizedAddress, "oid": cloid.toRaw()]))
    }

    public func queryReferralState(user: String) async throws -> ReferralState {
        try await httpClient.postInfo(makePayload(type: "referral", additional: ["user": user.normalizedAddress]))
    }

    public func referralState(address: String) async throws -> ReferralState {
        try await queryReferralState(user: address)
    }

    public func querySubAccounts(user: String) async throws -> [SubAccount] {
        let data = try await httpClient.postInfoRaw(
            makePayload(type: "subAccounts", additional: ["user": user.normalizedAddress]))
        if let str = String(data: data, encoding: .utf8), str.trimmingCharacters(in: .whitespacesAndNewlines) == "null"
        {
            return []
        }
        return try JSONDecoder().decode([SubAccount].self, from: data)
    }

    public func subAccounts(address: String) async throws -> [SubAccount] {
        try await querySubAccounts(user: address)
    }

    /// Query multi-sig signers for a user
    /// - Parameter multiSigUser: The multi-sig user address
    /// - Returns: Multi-sig signers configuration, or nil if user is not a multi-sig
    public func queryUserToMultiSigSigners(multiSigUser: String) async throws -> MultiSigSignersResponse? {
        try await httpClient.postInfo(
            makePayload(type: "userToMultiSigSigners", additional: ["user": multiSigUser.normalizedAddress]))
    }

    /// Query perp deploy auction status
    /// - Returns: Current gas auction status for perp deployment
    public func queryPerpDeployAuctionStatus() async throws -> PerpDeployAuctionStatus {
        try await httpClient.postInfo(makePayload(type: "perpDeployAuctionStatus"))
    }

    /// Query user DEX abstraction state
    /// - Parameter user: The user address
    /// - Returns: DEX abstraction state, or nil if not configured
    public func queryUserDexAbstractionState(user: String) async throws -> UserDexAbstractionState? {
        try await httpClient.postInfo(
            makePayload(type: "userDexAbstraction", additional: ["user": user.normalizedAddress]))
    }

    public func historicalOrders(user: String) async throws -> [HistoricalOrder] {
        try await httpClient.postInfo(
            makePayload(type: "historicalOrders", additional: ["user": user.normalizedAddress]))
    }

    public func userNonFundingLedgerUpdates(user: String, startTime: Int64, endTime: Int64? = nil) async throws
        -> [LedgerUpdate]
    {
        var additional: [String: Sendable] = ["user": user.normalizedAddress, "startTime": startTime]
        if let endTime { additional["endTime"] = endTime }
        return try await httpClient.postInfo(makePayload(type: "userNonFundingLedgerUpdates", additional: additional))
    }

    /// Query user portfolio history with account value and PnL over different time periods
    /// - Parameter user: The user address
    /// - Returns: Portfolio history data for day, week, month, and allTime periods
    public func portfolio(user: String) async throws -> UserPortfolioHistory {
        try await httpClient.postInfo(
            makePayload(type: "portfolio", additional: ["user": user.normalizedAddress]))
    }

    public func userTwapSliceFills(user: String) async throws -> [TwapSliceFill] {
        try await httpClient.postInfo(
            makePayload(type: "userTwapSliceFills", additional: ["user": user.normalizedAddress]))
    }

    public func userVaultEquities(user: String) async throws -> [VaultEquity] {
        try await httpClient.postInfo(
            makePayload(type: "userVaultEquities", additional: ["user": user.normalizedAddress]))
    }

    public func userRole(user: String) async throws -> UserRole {
        try await httpClient.postInfo(makePayload(type: "userRole", additional: ["user": user.normalizedAddress]))
    }

    public func userRateLimit(user: String) async throws -> UserRateLimit {
        try await httpClient.postInfo(makePayload(type: "userRateLimit", additional: ["user": user.normalizedAddress]))
    }

    /// Query spot deploy auction status
    /// - Parameter user: The user address
    /// - Returns: Spot deploy state including gas auction information
    public func querySpotDeployAuctionStatus(user: String) async throws -> SpotDeployState {
        try await httpClient.postInfo(
            makePayload(type: "spotDeployState", additional: ["user": user.normalizedAddress]))
    }

    public func extraAgents(user: String) async throws -> [ExtraAgent] {
        try await httpClient.postInfo(makePayload(type: "extraAgents", additional: ["user": user.normalizedAddress]))
    }

    // MARK: - WebSocket Methods

    @discardableResult
    public func subscribe(_ subscription: Subscription, callback: @escaping SubscriptionCallback) async throws -> Int {
        let remappedSubscription = remapCoinSubscription(subscription)
        let manager: WebSocketManager
        if let existing = wsManager {
            manager = existing
        } else {
            manager = WebSocketManager(network: network)
            try await manager.start()
            wsManager = manager
        }
        return try await manager.subscribe(remappedSubscription, callback: callback)
    }

    @discardableResult
    public func unsubscribe(_ subscription: Subscription, subscriptionId: Int) async throws -> Bool {
        guard let wsManager else { throw WebSocketError.notConnected }
        return try await wsManager.unsubscribe(remapCoinSubscription(subscription), subscriptionId: subscriptionId)
    }

    public func disconnectWebSocket() async {
        await wsManager?.stop()
        wsManager = nil
    }

    public var isWebSocketConnected: Bool {
        get async { await wsManager?.isConnected ?? false }
    }

    private func remapCoinSubscription(_ subscription: Subscription) -> Subscription {
        switch subscription {
        case .l2Book(let coin): return .l2Book(coin: mapCoin(coin))
        case .trades(let coin): return .trades(coin: mapCoin(coin))
        case .candle(let coin, let interval): return .candle(coin: mapCoin(coin), interval: interval)
        case .bbo(let coin): return .bbo(coin: mapCoin(coin))
        case .activeAssetCtx(let coin): return .activeAssetCtx(coin: mapCoin(coin))
        default: return subscription
        }
    }

    private func mapCoin(_ coin: String) -> String {
        nameToCoin[coin] ?? coin
    }
}
