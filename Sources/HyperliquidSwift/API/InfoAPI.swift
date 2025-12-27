import Foundation

/// Info API for querying Hyperliquid data
/// Reference: Python SDK hyperliquid/info.py
/// All method names and parameters strictly align with the Python SDK
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
    /// - Parameters:
    ///   - network: Network to connect to (mainnet or testnet)
    ///   - meta: Optional pre-loaded perpetual metadata
    ///   - spotMeta: Optional pre-loaded spot metadata
    public init(
        network: HyperliquidNetwork = .mainnet,
        meta: Meta? = nil,
        spotMeta: SpotMeta? = nil
    ) {
        self.network = network
        httpClient = HTTPClient(baseURL: network.baseURL)
    }

    /// Async initializer that loads metadata
    /// Reference: Python info.py:__init__
    public init(
        network: HyperliquidNetwork = .mainnet,
        skipWs: Bool = true,
        meta: Meta? = nil,
        spotMeta: SpotMeta? = nil
    ) async throws {
        self.network = network
        httpClient = HTTPClient(baseURL: network.baseURL)

        // Initialize WebSocket if not skipped
        if !skipWs {
            wsManager = WebSocketManager(network: network)
            try await wsManager?.start()
        }

        // Load spot meta if not provided
        let loadedSpotMeta: SpotMeta = if let spotMeta {
            spotMeta
        } else {
            try await self.spotMeta()
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
        let loadedMeta: Meta = if let meta {
            meta
        } else {
            try await self.meta()
        }
        setPerpMeta(loadedMeta, offset: 0)
    }

    /// Set perpetual metadata
    /// Reference: Python info.py:set_perp_meta
    private func setPerpMeta(_ meta: Meta, offset: Int) {
        for (index, assetInfo) in meta.universe.enumerated() {
            let asset = index + offset
            coinToAsset[assetInfo.name] = asset
            nameToCoin[assetInfo.name] = assetInfo.name
            assetToSzDecimals[asset] = assetInfo.szDecimals
        }
    }

    // MARK: - Asset/Coin Mapping

    /// Convert name to asset ID
    /// Reference: Python info.py:name_to_asset
    public func nameToAsset(_ name: String) -> Int? {
        guard let coin = nameToCoin[name], let asset = coinToAsset[coin] else {
            return nil
        }
        return asset
    }

    /// Get coin name for a given name
    public func getCoin(for name: String) -> String? {
        nameToCoin[name]
    }

    // MARK: - Market Data APIs

    /// Retrieve all mids for all actively traded coins
    /// Reference: Python info.py:all_mids
    public func allMids(dex: String = "") async throws -> [String: String] {
        let payload = HTTPClient.infoPayload(type: "allMids", additional: ["dex": dex])
        return try await httpClient.postInfo(payload)
    }

    /// Retrieve exchange perp metadata
    /// Reference: Python info.py:meta
    public func meta(dex: String = "") async throws -> Meta {
        let payload = HTTPClient.infoPayload(type: "meta", additional: ["dex": dex])
        return try await httpClient.postInfo(payload)
    }

    /// Retrieve exchange spot metadata
    /// Reference: Python info.py:spot_meta
    public func spotMeta() async throws -> SpotMeta {
        let payload = HTTPClient.infoPayload(type: "spotMeta")
        return try await httpClient.postInfo(payload)
    }

    /// Retrieve exchange MetaAndAssetCtxs
    /// Reference: Python info.py:meta_and_asset_ctxs
    public func metaAndAssetCtxs() async throws -> MetaAndAssetCtxs {
        let payload = HTTPClient.infoPayload(type: "metaAndAssetCtxs")
        let data = try await httpClient.postInfoRaw(payload)

        guard let array = try JSONSerialization.jsonObject(with: data) as? [Any],
              array.count >= 2,
              let metaDict = array[0] as? [String: Any],
              let assetCtxsArray = array[1] as? [[String: Any]]
        else {
            throw HyperliquidError.decodingError(underlying: NSError(domain: "InfoAPI", code: -1))
        }

        let metaData = try JSONSerialization.data(withJSONObject: metaDict)
        let meta = try JSONDecoder().decode(Meta.self, from: metaData)

        let assetCtxsData = try JSONSerialization.data(withJSONObject: assetCtxsArray)
        let assetCtxs = try JSONDecoder().decode([PerpAssetCtx].self, from: assetCtxsData)

        return MetaAndAssetCtxs(meta: meta, assetCtxs: assetCtxs)
    }

    /// Retrieve exchange spot asset contexts
    /// Reference: Python info.py:spot_meta_and_asset_ctxs
    public func spotMetaAndAssetCtxs() async throws -> SpotMetaAndAssetCtxs {
        let payload = HTTPClient.infoPayload(type: "spotMetaAndAssetCtxs")
        let data = try await httpClient.postInfoRaw(payload)

        guard let array = try JSONSerialization.jsonObject(with: data) as? [Any],
              array.count >= 2,
              let metaDict = array[0] as? [String: Any],
              let assetCtxsArray = array[1] as? [[String: Any]]
        else {
            throw HyperliquidError.decodingError(underlying: NSError(domain: "InfoAPI", code: -1))
        }

        let metaData = try JSONSerialization.data(withJSONObject: metaDict)
        let meta = try JSONDecoder().decode(SpotMeta.self, from: metaData)

        let assetCtxsData = try JSONSerialization.data(withJSONObject: assetCtxsArray)
        let assetCtxs = try JSONDecoder().decode([SpotAssetCtx].self, from: assetCtxsData)

        return SpotMetaAndAssetCtxs(meta: meta, assetCtxs: assetCtxs)
    }

    /// Retrieve L2 snapshot for a given coin
    /// Reference: Python info.py:l2_snapshot
    public func l2Snapshot(name: String) async throws -> L2Book {
        let coin = nameToCoin[name] ?? name
        let payload = HTTPClient.infoPayload(type: "l2Book", additional: ["coin": coin])
        return try await httpClient.postInfo(payload)
    }

    /// Retrieve candles snapshot for a given coin
    /// Reference: Python info.py:candles_snapshot
    public func candlesSnapshot(
        name: String,
        interval: String,
        startTime: Int64,
        endTime: Int64
    ) async throws -> [Candle] {
        let coin = nameToCoin[name] ?? name
        let req: [String: Any] = [
            "coin": coin,
            "interval": interval,
            "startTime": startTime,
            "endTime": endTime,
        ]
        let payload = HTTPClient.infoPayload(type: "candleSnapshot", additional: ["req": req])
        return try await httpClient.postInfo(payload)
    }

    /// Retrieve funding history for a given coin
    /// Reference: Python info.py:funding_history
    public func fundingHistory(
        name: String,
        startTime: Int64,
        endTime: Int64? = nil
    ) async throws -> [FundingHistoryEntry] {
        let coin = nameToCoin[name] ?? name
        var additional: [String: Any] = [
            "coin": coin,
            "startTime": startTime,
        ]
        if let endTime {
            additional["endTime"] = endTime
        }
        let payload = HTTPClient.infoPayload(type: "fundingHistory", additional: additional)
        return try await httpClient.postInfo(payload)
    }

    /// Retrieve perp dexs
    /// Reference: Python info.py:perp_dexs
    public func perpDexs() async throws -> Any {
        let payload = HTTPClient.infoPayload(type: "perpDexs")
        let data = try await httpClient.postInfoRaw(payload)
        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: - User Account APIs

    /// Retrieve trading details about a user
    /// Reference: Python info.py:user_state
    public func userState(address: String, dex: String = "") async throws -> UserState {
        let payload = HTTPClient.infoPayload(
            type: "clearinghouseState",
            additional: ["user": address.normalizedAddress, "dex": dex]
        )
        return try await httpClient.postInfo(payload)
    }

    /// Retrieve spot user state
    /// Reference: Python info.py:spot_user_state
    public func spotUserState(address: String) async throws -> SpotUserState {
        let payload = HTTPClient.infoPayload(
            type: "spotClearinghouseState",
            additional: ["user": address.normalizedAddress]
        )
        return try await httpClient.postInfo(payload)
    }

    /// Retrieve a user's open orders
    /// Reference: Python info.py:open_orders
    public func openOrders(address: String, dex: String = "") async throws -> [OpenOrder] {
        let payload = HTTPClient.infoPayload(
            type: "openOrders",
            additional: ["user": address.normalizedAddress, "dex": dex]
        )
        return try await httpClient.postInfo(payload)
    }

    /// Retrieve a user's open orders with additional frontend info
    /// Reference: Python info.py:frontend_open_orders
    public func frontendOpenOrders(address: String, dex: String = "") async throws -> [FrontendOpenOrder] {
        let payload = HTTPClient.infoPayload(
            type: "frontendOpenOrders",
            additional: ["user": address.normalizedAddress, "dex": dex]
        )
        return try await httpClient.postInfo(payload)
    }

    /// Retrieve a given user's fills
    /// Reference: Python info.py:user_fills
    public func userFills(address: String) async throws -> [Fill] {
        let payload = HTTPClient.infoPayload(
            type: "userFills",
            additional: ["user": address.normalizedAddress]
        )
        return try await httpClient.postInfo(payload)
    }

    /// Retrieve a given user's fills by time
    /// Reference: Python info.py:user_fills_by_time
    public func userFillsByTime(
        address: String,
        startTime: Int64,
        endTime: Int64? = nil,
        aggregateByTime: Bool = false
    ) async throws -> [Fill] {
        var additional: [String: Any] = [
            "user": address.normalizedAddress,
            "startTime": startTime,
            "aggregateByTime": aggregateByTime,
        ]
        if let endTime {
            additional["endTime"] = endTime
        }
        let payload = HTTPClient.infoPayload(type: "userFillsByTime", additional: additional)
        return try await httpClient.postInfo(payload)
    }

    /// Retrieve a user's funding history
    /// Reference: Python info.py:user_funding_history
    public func userFundingHistory(
        user: String,
        startTime: Int64,
        endTime: Int64? = nil
    ) async throws -> [UserFunding] {
        var additional: [String: Any] = [
            "user": user.normalizedAddress,
            "startTime": startTime,
        ]
        if let endTime {
            additional["endTime"] = endTime
        }
        let payload = HTTPClient.infoPayload(type: "userFunding", additional: additional)
        return try await httpClient.postInfo(payload)
    }

    /// Retrieve the volume of trading activity associated with a user
    /// Reference: Python info.py:user_fees
    public func userFees(address: String) async throws -> UserFees {
        let payload = HTTPClient.infoPayload(
            type: "userFees",
            additional: ["user": address.normalizedAddress]
        )
        return try await httpClient.postInfo(payload)
    }

    /// Retrieve the staking summary associated with a user
    /// Reference: Python info.py:user_staking_summary
    public func userStakingSummary(address: String) async throws -> StakingSummary {
        let payload = HTTPClient.infoPayload(
            type: "delegatorSummary",
            additional: ["user": address.normalizedAddress]
        )
        return try await httpClient.postInfo(payload)
    }

    /// Alias for userStakingSummary
    public func delegatorSummary(address: String) async throws -> StakingSummary {
        try await userStakingSummary(address: address)
    }

    /// Retrieve the user's staking delegations
    /// Reference: Python info.py:user_staking_delegations
    public func userStakingDelegations(address: String) async throws -> [StakingDelegation] {
        let payload = HTTPClient.infoPayload(
            type: "delegations",
            additional: ["user": address.normalizedAddress]
        )
        return try await httpClient.postInfo(payload)
    }

    /// Retrieve the historic staking rewards associated with a user
    /// Reference: Python info.py:user_staking_rewards
    public func userStakingRewards(address: String) async throws -> [StakingReward] {
        let payload = HTTPClient.infoPayload(
            type: "delegatorRewards",
            additional: ["user": address.normalizedAddress]
        )
        return try await httpClient.postInfo(payload)
    }

    /// Retrieve comprehensive staking history for a user
    /// Reference: Python info.py:delegator_history
    public func delegatorHistory(user: String) async throws -> [DelegatorHistoryEntry] {
        let payload = HTTPClient.infoPayload(
            type: "delegatorHistory",
            additional: ["user": user.normalizedAddress]
        )
        return try await httpClient.postInfo(payload)
    }

    /// Query order status by order ID
    /// Reference: Python info.py:query_order_by_oid
    public func queryOrderByOid(user: String, oid: Int64) async throws -> OrderStatus {
        let payload = HTTPClient.infoPayload(
            type: "orderStatus",
            additional: ["user": user.normalizedAddress, "oid": oid]
        )
        return try await httpClient.postInfo(payload)
    }

    /// Alias for queryOrderByOid with address parameter
    public func orderStatus(address: String, oid: Int64) async throws -> OrderStatus {
        try await queryOrderByOid(user: address, oid: oid)
    }

    /// Query order status by client order ID
    /// Reference: Python info.py:query_order_by_cloid
    public func queryOrderByCloid(user: String, cloid: Cloid) async throws -> OrderStatus {
        let payload = HTTPClient.infoPayload(
            type: "orderStatus",
            additional: ["user": user.normalizedAddress, "oid": cloid.toRaw()]
        )
        return try await httpClient.postInfo(payload)
    }

    /// Query referral state
    /// Reference: Python info.py:query_referral_state
    public func queryReferralState(user: String) async throws -> ReferralState {
        let payload = HTTPClient.infoPayload(
            type: "referral",
            additional: ["user": user.normalizedAddress]
        )
        return try await httpClient.postInfo(payload)
    }

    /// Alias for queryReferralState with address parameter
    public func referralState(address: String) async throws -> ReferralState {
        try await queryReferralState(user: address)
    }

    /// Query sub accounts
    /// Reference: Python info.py:query_sub_accounts
    public func querySubAccounts(user: String) async throws -> [SubAccount] {
        let payload = HTTPClient.infoPayload(
            type: "subAccounts",
            additional: ["user": user.normalizedAddress]
        )
        let data = try await httpClient.postInfoRaw(payload)
        // API returns null when user has no sub accounts
        // Check for literal "null" JSON response
        if let str = String(data: data, encoding: .utf8),
           str.trimmingCharacters(in: .whitespacesAndNewlines) == "null"
        {
            return []
        }
        return try JSONDecoder().decode([SubAccount].self, from: data)
    }

    /// Alias for querySubAccounts with address parameter
    public func subAccounts(address: String) async throws -> [SubAccount] {
        try await querySubAccounts(user: address)
    }

    /// Query user to multi sig signers
    /// Reference: Python info.py:query_user_to_multi_sig_signers
    public func queryUserToMultiSigSigners(multiSigUser: String) async throws -> Any {
        let payload = HTTPClient.infoPayload(
            type: "userToMultiSigSigners",
            additional: ["user": multiSigUser.normalizedAddress]
        )
        let data = try await httpClient.postInfoRaw(payload)
        return try JSONSerialization.jsonObject(with: data)
    }

    /// Query perp deploy auction status
    /// Reference: Python info.py:query_perp_deploy_auction_status
    public func queryPerpDeployAuctionStatus() async throws -> Any {
        let payload = HTTPClient.infoPayload(type: "perpDeployAuctionStatus")
        let data = try await httpClient.postInfoRaw(payload)
        return try JSONSerialization.jsonObject(with: data)
    }

    /// Query user dex abstraction state
    /// Reference: Python info.py:query_user_dex_abstraction_state
    public func queryUserDexAbstractionState(user: String) async throws -> Any {
        let payload = HTTPClient.infoPayload(
            type: "userDexAbstraction",
            additional: ["user": user.normalizedAddress]
        )
        let data = try await httpClient.postInfoRaw(payload)
        return try JSONSerialization.jsonObject(with: data)
    }

    /// Retrieve a user's historical orders
    /// Reference: Python info.py:historical_orders
    public func historicalOrders(user: String) async throws -> [HistoricalOrder] {
        let payload = HTTPClient.infoPayload(
            type: "historicalOrders",
            additional: ["user": user.normalizedAddress]
        )
        return try await httpClient.postInfo(payload)
    }

    /// Retrieve non-funding ledger updates for a user
    /// Reference: Python info.py:user_non_funding_ledger_updates
    public func userNonFundingLedgerUpdates(
        user: String,
        startTime: Int64,
        endTime: Int64? = nil
    ) async throws -> [LedgerUpdate] {
        var additional: [String: Any] = [
            "user": user.normalizedAddress,
            "startTime": startTime,
        ]
        if let endTime {
            additional["endTime"] = endTime
        }
        let payload = HTTPClient.infoPayload(type: "userNonFundingLedgerUpdates", additional: additional)
        return try await httpClient.postInfo(payload)
    }

    /// Retrieve comprehensive portfolio performance data
    /// Reference: Python info.py:portfolio
    public func portfolio(user: String) async throws -> Any {
        let payload = HTTPClient.infoPayload(
            type: "portfolio",
            additional: ["user": user.normalizedAddress]
        )
        let data = try await httpClient.postInfoRaw(payload)
        return try JSONSerialization.jsonObject(with: data)
    }

    /// Retrieve a user's TWAP slice fills
    /// Reference: Python info.py:user_twap_slice_fills
    public func userTwapSliceFills(user: String) async throws -> [TwapSliceFill] {
        let payload = HTTPClient.infoPayload(
            type: "userTwapSliceFills",
            additional: ["user": user.normalizedAddress]
        )
        return try await httpClient.postInfo(payload)
    }

    /// Retrieve user's equity positions across all vaults
    /// Reference: Python info.py:user_vault_equities
    public func userVaultEquities(user: String) async throws -> [VaultEquity] {
        let payload = HTTPClient.infoPayload(
            type: "userVaultEquities",
            additional: ["user": user.normalizedAddress]
        )
        return try await httpClient.postInfo(payload)
    }

    /// Retrieve the role and account type information for a user
    /// Reference: Python info.py:user_role
    public func userRole(user: String) async throws -> UserRole {
        let payload = HTTPClient.infoPayload(
            type: "userRole",
            additional: ["user": user.normalizedAddress]
        )
        return try await httpClient.postInfo(payload)
    }

    /// Retrieve user's API rate limit configuration and usage
    /// Reference: Python info.py:user_rate_limit
    public func userRateLimit(user: String) async throws -> UserRateLimit {
        let payload = HTTPClient.infoPayload(
            type: "userRateLimit",
            additional: ["user": user.normalizedAddress]
        )
        return try await httpClient.postInfo(payload)
    }

    /// Query spot deploy auction status
    /// Reference: Python info.py:query_spot_deploy_auction_status
    public func querySpotDeployAuctionStatus(user: String) async throws -> Any {
        let payload = HTTPClient.infoPayload(
            type: "spotDeployState",
            additional: ["user": user.normalizedAddress]
        )
        let data = try await httpClient.postInfoRaw(payload)
        return try JSONSerialization.jsonObject(with: data)
    }

    /// Retrieve extra agents associated with a user
    /// Reference: Python info.py:extra_agents
    public func extraAgents(user: String) async throws -> [ExtraAgent] {
        let payload = HTTPClient.infoPayload(
            type: "extraAgents",
            additional: ["user": user.normalizedAddress]
        )
        return try await httpClient.postInfo(payload)
    }

    // MARK: - WebSocket Methods

    /// Subscribe to a WebSocket channel
    /// Reference: Python info.py:subscribe
    /// - Parameters:
    ///   - subscription: The subscription type
    ///   - callback: Callback to receive messages
    /// - Returns: Subscription ID for unsubscribing
    @discardableResult
    public func subscribe(
        _ subscription: Subscription,
        callback: @escaping SubscriptionCallback
    ) async throws -> Int {
        // Remap coin if needed
        let remappedSubscription = remapCoinSubscription(subscription)

        guard let wsManager else {
            // Create WebSocket manager on demand if not initialized
            let manager = WebSocketManager(network: network)
            try await manager.start()
            self.wsManager = manager
            return try await manager.subscribe(remappedSubscription, callback: callback)
        }

        return try await wsManager.subscribe(remappedSubscription, callback: callback)
    }

    /// Unsubscribe from a WebSocket channel
    /// Reference: Python info.py:unsubscribe
    /// - Parameters:
    ///   - subscription: The subscription to unsubscribe from
    ///   - subscriptionId: The ID returned from subscribe
    /// - Returns: True if unsubscribed successfully
    @discardableResult
    public func unsubscribe(_ subscription: Subscription, subscriptionId: Int) async throws -> Bool {
        let remappedSubscription = remapCoinSubscription(subscription)

        guard let wsManager else {
            throw WebSocketError.notConnected
        }

        return try await wsManager.unsubscribe(remappedSubscription, subscriptionId: subscriptionId)
    }

    /// Disconnect WebSocket
    /// Reference: Python info.py:disconnect_websocket
    public func disconnectWebSocket() async {
        await wsManager?.stop()
        wsManager = nil
    }

    /// Check if WebSocket is connected
    public var isWebSocketConnected: Bool {
        get async {
            await wsManager?.isConnected ?? false
        }
    }

    /// Remap coin names in subscriptions
    /// Reference: Python info.py:_remap_coin_subscription
    private func remapCoinSubscription(_ subscription: Subscription) -> Subscription {
        switch subscription {
        case let .l2Book(coin):
            if let mappedCoin = nameToCoin[coin] {
                return .l2Book(coin: mappedCoin)
            }
        case let .trades(coin):
            if let mappedCoin = nameToCoin[coin] {
                return .trades(coin: mappedCoin)
            }
        case let .candle(coin, interval):
            if let mappedCoin = nameToCoin[coin] {
                return .candle(coin: mappedCoin, interval: interval)
            }
        case let .bbo(coin):
            if let mappedCoin = nameToCoin[coin] {
                return .bbo(coin: mappedCoin)
            }
        case let .activeAssetCtx(coin):
            if let mappedCoin = nameToCoin[coin] {
                return .activeAssetCtx(coin: mappedCoin)
            }
        default:
            break
        }
        return subscription
    }
}
