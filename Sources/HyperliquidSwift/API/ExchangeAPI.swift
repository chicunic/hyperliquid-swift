import Foundation
import OrderedCollections

/// Exchange API for trading operations on Hyperliquid
/// Reference: Python SDK hyperliquid/exchange.py
public actor ExchangeAPI {
    private let httpClient: HTTPClient
    private let network: HyperliquidNetwork
    private let signer: HyperliquidSigner
    private var infoAPI: InfoAPI

    /// Vault address for trading on behalf of a vault
    public var vaultAddress: String?

    /// Account address (for sub-account operations)
    public var accountAddress: String?

    /// Expiration timestamp for actions (optional)
    public var expiresAfter: Int64?

    /// Default slippage for market orders (5%)
    public static let defaultSlippage: Decimal = 0.05

    /// Initialize Exchange API
    /// - Parameters:
    ///   - signer: Signer for transaction signing
    ///   - network: Network to connect to
    ///   - vaultAddress: Optional vault address
    ///   - accountAddress: Optional account address for sub-accounts
    public init(
        signer: HyperliquidSigner,
        network: HyperliquidNetwork = .mainnet,
        vaultAddress: String? = nil,
        accountAddress: String? = nil
    ) async throws {
        self.signer = signer
        self.network = network
        httpClient = HTTPClient(baseURL: network.baseURL)
        self.vaultAddress = vaultAddress?.normalizedAddress
        self.accountAddress = accountAddress?.normalizedAddress
        infoAPI = try await InfoAPI(network: network)
    }

    /// Check if running on mainnet
    private var isMainnet: Bool {
        network == .mainnet
    }

    // MARK: - Internal Helpers

    /// Post an action to the exchange
    private func postAction(
        action: OrderedDictionary<String, Any>,
        signature: Signature,
        nonce: Int64
    ) async throws -> Data {
        // Convert OrderedDictionary to regular dict for JSON serialization
        let actionDict = convertToSerializable(action)
        return try await postActionImpl(action: actionDict, signature: signature, nonce: nonce)
    }

    /// Post an action to the exchange
    private func postAction(
        action: [String: Any],
        signature: Signature,
        nonce: Int64
    ) async throws -> Data {
        try await postActionImpl(action: action, signature: signature, nonce: nonce)
    }

    /// Internal implementation for posting actions
    private func postActionImpl(
        action: [String: Any],
        signature: Signature,
        nonce: Int64
    ) async throws -> Data {
        var payload: [String: Any] = [
            "action": action,
            "nonce": nonce,
            "signature": signature.asDictionary,
        ]

        // Only include vault address for certain action types
        let actionType = action["type"] as? String ?? ""
        if actionType != "usdClassTransfer", actionType != "sendAsset" {
            payload["vaultAddress"] = vaultAddress
        } else {
            payload["vaultAddress"] = NSNull()
        }

        if let expiresAfter {
            payload["expiresAfter"] = expiresAfter
        } else {
            payload["expiresAfter"] = NSNull()
        }

        // Serialize to Data before crossing actor boundary to avoid Sendable issues
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        return try await httpClient.postExchangeRawData(jsonData)
    }

    /// Convert OrderedDictionary to JSON-serializable [String: Any]
    private func convertToSerializable(_ dict: OrderedDictionary<String, Any>) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dict {
            if let nested = value as? OrderedDictionary<String, Any> {
                result[key] = convertToSerializable(nested)
            } else if let array = value as? [OrderedDictionary<String, Any>] {
                result[key] = array.map { convertToSerializable($0) }
            } else {
                result[key] = value
            }
        }
        return result
    }

    /// Sign an L1 action (OrderedDictionary version - preserves key order for msgpack)
    private func signL1Action(action: OrderedDictionary<String, Any>, nonce: Int64) async throws -> Signature {
        let actionHash = try ActionHash.compute(
            action: action,
            vaultAddress: vaultAddress,
            nonce: nonce,
            expiresAfter: expiresAfter
        )

        let messageHash = EIP712.hashTypedDataL1(
            actionHash: actionHash,
            isMainnet: isMainnet
        )

        return try await signer.sign(messageHash: messageHash)
    }

    /// Sign an L1 action (regular dict version - sorts keys alphabetically)
    private func signL1Action(action: [String: Any], nonce: Int64) async throws -> Signature {
        let actionHash = try ActionHash.compute(
            action: action,
            vaultAddress: vaultAddress,
            nonce: nonce,
            expiresAfter: expiresAfter
        )

        let messageHash = EIP712.hashTypedDataL1(
            actionHash: actionHash,
            isMainnet: isMainnet
        )

        return try await signer.sign(messageHash: messageHash)
    }

    /// Sign a user-signed action
    private func signUserSignedAction(
        action: [String: Any],
        signTypes: [TypedVariable],
        primaryType: UserSignedPrimaryType
    ) async throws -> Signature {
        let messageHash = try EIP712.hashTypedDataUserSigned(
            action: action,
            signTypes: signTypes,
            primaryType: primaryType,
            isMainnet: isMainnet
        )

        return try await signer.sign(messageHash: messageHash)
    }

    // MARK: - Order Operations

    /// Place a single order
    /// Reference: Python exchange.py:117-138
    public func order(
        coin: String,
        isBuy: Bool,
        sz: Decimal,
        limitPx: Decimal,
        orderType: OrderType,
        reduceOnly: Bool = false,
        cloid: Cloid? = nil,
        builder: BuilderInfo? = nil
    ) async throws -> Data {
        let request = OrderRequest(
            coin: coin,
            isBuy: isBuy,
            sz: sz,
            limitPx: limitPx,
            orderType: orderType,
            reduceOnly: reduceOnly,
            cloid: cloid
        )
        return try await bulkOrders(orders: [request], builder: builder)
    }

    /// Place multiple orders
    /// Reference: Python exchange.py:140-165
    public func bulkOrders(
        orders: [OrderRequest],
        builder: BuilderInfo? = nil,
        grouping: OrderGrouping = .na
    ) async throws -> Data {
        let timestamp = currentTimestampMs()

        var orderWires: [OrderWire] = []
        for order in orders {
            guard let asset = await infoAPI.nameToAsset(order.coin) else {
                throw HyperliquidError.invalidParameter("Unknown coin: \(order.coin)")
            }
            let wire = try orderRequestToOrderWire(order, asset: asset)
            orderWires.append(wire)
        }

        let action = orderWiresToOrderAction(
            orderWires: orderWires,
            builder: builder,
            grouping: grouping
        )

        let signature = try await signL1Action(action: action, nonce: timestamp)
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    /// Modify an order
    /// Reference: Python exchange.py:167-190
    public func modifyOrder(
        oid: OidOrCloid,
        coin: String,
        isBuy: Bool,
        sz: Decimal,
        limitPx: Decimal,
        orderType: OrderType,
        reduceOnly: Bool = false,
        cloid: Cloid? = nil
    ) async throws -> Data {
        let request = OrderRequest(
            coin: coin,
            isBuy: isBuy,
            sz: sz,
            limitPx: limitPx,
            orderType: orderType,
            reduceOnly: reduceOnly,
            cloid: cloid
        )
        let modify = ModifyRequest(oidOrCloid: oid, order: request)
        return try await bulkModifyOrders(modifies: [modify])
    }

    /// Modify multiple orders
    /// Reference: Python exchange.py:192-220
    public func bulkModifyOrders(modifies: [ModifyRequest]) async throws -> Data {
        let timestamp = currentTimestampMs()

        var modifyWires: [[String: Any]] = []
        for modify in modifies {
            guard let asset = await infoAPI.nameToAsset(modify.order.coin) else {
                throw HyperliquidError.invalidParameter("Unknown coin: \(modify.order.coin)")
            }

            let orderWire = try orderRequestToOrderWire(modify.order, asset: asset)

            let oidValue: Any = switch modify.oidOrCloid {
            case let .oid(oid):
                oid
            case let .cloid(cloid):
                cloid.toRaw()
            }

            modifyWires.append([
                "oid": oidValue,
                "order": orderWire.asDictionary,
            ])
        }

        let action: [String: Any] = [
            "type": "batchModify",
            "modifies": modifyWires,
        ]

        let signature = try await signL1Action(action: action, nonce: timestamp)
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    /// Cancel an order by order ID
    /// Reference: Python exchange.py:277-278
    public func cancel(coin: String, oid: Int64) async throws -> Data {
        try await bulkCancel(cancels: [CancelRequest(coin: coin, oid: oid)])
    }

    /// Cancel multiple orders by order ID
    /// Reference: Python exchange.py:283-308
    public func bulkCancel(cancels: [CancelRequest]) async throws -> Data {
        let timestamp = currentTimestampMs()

        var cancelWires: [[String: Any]] = []
        for cancel in cancels {
            guard let asset = await infoAPI.nameToAsset(cancel.coin) else {
                throw HyperliquidError.invalidParameter("Unknown coin: \(cancel.coin)")
            }
            cancelWires.append([
                "a": asset,
                "o": cancel.oid,
            ])
        }

        let action: [String: Any] = [
            "type": "cancel",
            "cancels": cancelWires,
        ]

        let signature = try await signL1Action(action: action, nonce: timestamp)
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    /// Cancel an order by client order ID
    /// Reference: Python exchange.py:280-281
    public func cancelByCloid(coin: String, cloid: Cloid) async throws -> Data {
        try await bulkCancelByCloid(cancels: [CancelByCloidRequest(coin: coin, cloid: cloid)])
    }

    /// Cancel multiple orders by client order ID
    /// Reference: Python exchange.py:310-336
    public func bulkCancelByCloid(cancels: [CancelByCloidRequest]) async throws -> Data {
        let timestamp = currentTimestampMs()

        var cancelWires: [[String: Any]] = []
        for cancel in cancels {
            guard let asset = await infoAPI.nameToAsset(cancel.coin) else {
                throw HyperliquidError.invalidParameter("Unknown coin: \(cancel.coin)")
            }
            cancelWires.append([
                "asset": asset,
                "cloid": cancel.cloid.toRaw(),
            ])
        }

        let action: [String: Any] = [
            "type": "cancelByCloid",
            "cancels": cancelWires,
        ]

        let signature = try await signL1Action(action: action, nonce: timestamp)
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    /// Schedule cancel all orders at a future time
    /// Reference: Python exchange.py:338-364
    public func scheduleCancel(time: Int64?) async throws -> Data {
        let timestamp = currentTimestampMs()

        var action: [String: Any] = ["type": "scheduleCancel"]
        if let time {
            action["time"] = time
        }

        let signature = try await signL1Action(action: action, nonce: timestamp)
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    // MARK: - Account Operations

    /// Update leverage for an asset
    /// Reference: Python exchange.py:366-386
    public func updateLeverage(leverage: Int, coin: String, isCross: Bool = true) async throws -> Data {
        let timestamp = currentTimestampMs()

        guard let asset = await infoAPI.nameToAsset(coin) else {
            throw HyperliquidError.invalidParameter("Unknown coin: \(coin)")
        }

        let action: [String: Any] = [
            "type": "updateLeverage",
            "asset": asset,
            "isCross": isCross,
            "leverage": leverage,
        ]

        let signature = try await signL1Action(action: action, nonce: timestamp)
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    /// Update isolated margin for an asset
    /// Reference: Python exchange.py:388-409
    public func updateIsolatedMargin(amount: Decimal, coin: String) async throws -> Data {
        let timestamp = currentTimestampMs()

        guard let asset = await infoAPI.nameToAsset(coin) else {
            throw HyperliquidError.invalidParameter("Unknown coin: \(coin)")
        }

        let amountInt = try amount.toUSDInt()

        let action: [String: Any] = [
            "type": "updateIsolatedMargin",
            "asset": asset,
            "isBuy": true,
            "ntli": amountInt,
        ]

        let signature = try await signL1Action(action: action, nonce: timestamp)
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    /// Set referrer code
    /// Reference: Python exchange.py:411-429
    public func setReferrer(code: String) async throws -> Data {
        let timestamp = currentTimestampMs()

        let action: [String: Any] = [
            "type": "setReferrer",
            "code": code,
        ]

        // Note: vault_address is None for setReferrer
        let savedVault = vaultAddress
        vaultAddress = nil
        defer { vaultAddress = savedVault }

        let signature = try await signL1Action(action: action, nonce: timestamp)
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    /// Create a sub-account
    /// Reference: Python exchange.py:431-449
    public func createSubAccount(name: String) async throws -> Data {
        let timestamp = currentTimestampMs()

        let action: [String: Any] = [
            "type": "createSubAccount",
            "name": name,
        ]

        // Note: vault_address is None for createSubAccount
        let savedVault = vaultAddress
        vaultAddress = nil
        defer { vaultAddress = savedVault }

        let signature = try await signL1Action(action: action, nonce: timestamp)
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    // MARK: - Transfer Operations (User-Signed)

    /// Transfer USD between perp and spot
    /// Reference: Python exchange.py:451-468
    public func usdClassTransfer(amount: Decimal, toPerp: Bool) async throws -> Data {
        let timestamp = currentTimestampMs()

        var strAmount = try amount.toWireString()
        if let vaultAddress {
            strAmount += " subaccount:\(vaultAddress)"
        }

        let action: [String: Any] = [
            "type": "usdClassTransfer",
            "amount": strAmount,
            "toPerp": toPerp,
            "nonce": timestamp,
        ]

        let signature = try await signUserSignedAction(
            action: action,
            signTypes: USD_CLASS_TRANSFER_SIGN_TYPES,
            primaryType: .usdClassTransfer
        )

        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    /// Send asset across DEXes
    /// Reference: Python exchange.py:470-493
    public func sendAsset(
        destination: String,
        sourceDex: String = "",
        destinationDex: String = "",
        token: String,
        amount: Decimal
    ) async throws -> Data {
        let timestamp = currentTimestampMs()
        let strAmount = try amount.toWireString()

        let action: [String: Any] = [
            "type": "sendAsset",
            "destination": destination.normalizedAddress,
            "sourceDex": sourceDex,
            "destinationDex": destinationDex,
            "token": token,
            "amount": strAmount,
            "fromSubAccount": vaultAddress ?? "",
            "nonce": timestamp,
        ]

        let signature = try await signUserSignedAction(
            action: action,
            signTypes: SEND_ASSET_SIGN_TYPES,
            primaryType: .sendAsset
        )

        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    /// Transfer USD to sub-account
    /// Reference: Python exchange.py:495-515
    public func subAccountTransfer(
        subAccountUser: String,
        isDeposit: Bool,
        usd: Int64
    ) async throws -> Data {
        let timestamp = currentTimestampMs()

        let action: [String: Any] = [
            "type": "subAccountTransfer",
            "subAccountUser": subAccountUser.normalizedAddress,
            "isDeposit": isDeposit,
            "usd": usd,
        ]

        // Note: vault_address is None for subAccountTransfer
        let savedVault = vaultAddress
        vaultAddress = nil
        defer { vaultAddress = savedVault }

        let signature = try await signL1Action(action: action, nonce: timestamp)
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    /// Transfer spot tokens to sub-account
    /// Reference: Python exchange.py:517-538
    public func subAccountSpotTransfer(
        subAccountUser: String,
        isDeposit: Bool,
        token: String,
        amount: Decimal
    ) async throws -> Data {
        let timestamp = currentTimestampMs()
        let strAmount = try amount.toWireString()

        let action: [String: Any] = [
            "type": "subAccountSpotTransfer",
            "subAccountUser": subAccountUser.normalizedAddress,
            "isDeposit": isDeposit,
            "token": token,
            "amount": strAmount,
        ]

        // Note: vault_address is None for subAccountSpotTransfer
        let savedVault = vaultAddress
        vaultAddress = nil
        defer { vaultAddress = savedVault }

        let signature = try await signL1Action(action: action, nonce: timestamp)
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    /// Transfer USD to vault
    /// Reference: Python exchange.py:540-554
    public func vaultUsdTransfer(
        vaultAddress: String,
        isDeposit: Bool,
        usd: Int64
    ) async throws -> Data {
        let timestamp = currentTimestampMs()

        let action: [String: Any] = [
            "type": "vaultTransfer",
            "vaultAddress": vaultAddress.normalizedAddress,
            "isDeposit": isDeposit,
            "usd": usd,
        ]

        // Note: vault_address is None for vaultTransfer
        let savedVault = self.vaultAddress
        self.vaultAddress = nil
        defer { self.vaultAddress = savedVault }

        let signature = try await signL1Action(action: action, nonce: timestamp)
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    /// Transfer USD to another user
    /// Reference: Python exchange.py:556-565
    public func usdTransfer(amount: Decimal, destination: String) async throws -> Data {
        let timestamp = currentTimestampMs()
        let strAmount = try amount.toWireString()

        let action: [String: Any] = [
            "type": "usdSend",
            "destination": destination.normalizedAddress,
            "amount": strAmount,
            "time": timestamp,
        ]

        let signature = try await signUserSignedAction(
            action: action,
            signTypes: USD_SEND_SIGN_TYPES,
            primaryType: .usdSend
        )

        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    /// Transfer spot tokens to another user
    /// Reference: Python exchange.py:567-582
    public func spotTransfer(amount: Decimal, destination: String, token: String) async throws -> Data {
        let timestamp = currentTimestampMs()
        let strAmount = try amount.toWireString()

        let action: [String: Any] = [
            "type": "spotSend",
            "destination": destination.normalizedAddress,
            "amount": strAmount,
            "token": token,
            "time": timestamp,
        ]

        let signature = try await signUserSignedAction(
            action: action,
            signTypes: SPOT_TRANSFER_SIGN_TYPES,
            primaryType: .spotSend
        )

        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    /// Delegate or undelegate tokens for staking
    /// Reference: Python exchange.py:584-599
    public func tokenDelegate(validator: String, wei: UInt64, isUndelegate: Bool) async throws -> Data {
        let timestamp = currentTimestampMs()

        let action: [String: Any] = [
            "type": "tokenDelegate",
            "validator": validator.normalizedAddress,
            "wei": wei,
            "isUndelegate": isUndelegate,
            "nonce": timestamp,
        ]

        let signature = try await signUserSignedAction(
            action: action,
            signTypes: TOKEN_DELEGATE_SIGN_TYPES,
            primaryType: .tokenDelegate
        )

        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    /// Withdraw from bridge
    /// Reference: Python exchange.py:601-610
    public func withdrawFromBridge(amount: Decimal, destination: String) async throws -> Data {
        let timestamp = currentTimestampMs()
        let strAmount = try amount.toWireString()

        let action: [String: Any] = [
            "type": "withdraw3",
            "destination": destination.normalizedAddress,
            "amount": strAmount,
            "time": timestamp,
        ]

        let signature = try await signUserSignedAction(
            action: action,
            signTypes: WITHDRAW_SIGN_TYPES,
            primaryType: .withdraw
        )

        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    // MARK: - Agent/Builder Operations

    /// Approve an agent
    /// Reference: Python exchange.py:612-634
    public func approveAgent(agentAddress: String, agentName: String = "") async throws -> Data {
        let timestamp = currentTimestampMs()

        var action: [String: Any] = [
            "type": "approveAgent",
            "agentAddress": agentAddress.normalizedAddress,
            "agentName": agentName,
            "nonce": timestamp,
        ]

        let signature = try await signUserSignedAction(
            action: action,
            signTypes: APPROVE_AGENT_SIGN_TYPES,
            primaryType: .approveAgent
        )

        // Remove agentName from action if empty (matches Python behavior)
        if agentName.isEmpty {
            action.removeValue(forKey: "agentName")
        }

        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    /// Approve builder fee
    /// Reference: Python exchange.py:636-641
    public func approveBuilderFee(builder: String, maxFeeRate: String) async throws -> Data {
        let timestamp = currentTimestampMs()

        let action: [String: Any] = [
            "type": "approveBuilderFee",
            "builder": builder.normalizedAddress,
            "maxFeeRate": maxFeeRate,
            "nonce": timestamp,
        ]

        let signature = try await signUserSignedAction(
            action: action,
            signTypes: APPROVE_BUILDER_FEE_SIGN_TYPES,
            primaryType: .approveBuilderFee
        )

        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    // MARK: - Market Orders (Convenience)

    /// Open a market position
    /// Reference: Python exchange.py:222-237
    public func marketOpen(
        coin: String,
        isBuy: Bool,
        sz: Decimal,
        px: Decimal? = nil,
        slippage: Decimal = defaultSlippage,
        cloid: Cloid? = nil,
        builder: BuilderInfo? = nil
    ) async throws -> Data {
        let slippagePx = try await calculateSlippagePrice(coin: coin, isBuy: isBuy, slippage: slippage, px: px)

        return try await order(
            coin: coin,
            isBuy: isBuy,
            sz: sz,
            limitPx: slippagePx,
            orderType: .limit(LimitOrderType(tif: .ioc)),
            reduceOnly: false,
            cloid: cloid,
            builder: builder
        )
    }

    /// Close a market position
    /// Reference: Python exchange.py:239-275
    public func marketClose(
        coin: String,
        sz: Decimal? = nil,
        px: Decimal? = nil,
        slippage: Decimal = defaultSlippage,
        cloid: Cloid? = nil,
        builder: BuilderInfo? = nil
    ) async throws -> Data {
        let address = accountAddress ?? vaultAddress ?? signer.address

        let userState = try await infoAPI.userState(address: address)
        guard let position = userState.assetPositions.first(where: { $0.position.coin == coin }) else {
            throw HyperliquidError.invalidParameter("No position found for \(coin)")
        }

        guard let sziDecimal = Decimal(string: position.position.szi) else {
            throw HyperliquidError.invalidParameter("Invalid position size")
        }

        let closeSize = sz ?? abs(sziDecimal)
        let isBuy = sziDecimal < 0

        let slippagePx = try await calculateSlippagePrice(coin: coin, isBuy: isBuy, slippage: slippage, px: px)

        return try await order(
            coin: coin,
            isBuy: isBuy,
            sz: closeSize,
            limitPx: slippagePx,
            orderType: .limit(LimitOrderType(tif: .ioc)),
            reduceOnly: true,
            cloid: cloid,
            builder: builder
        )
    }

    /// Calculate slippage-adjusted price
    private func calculateSlippagePrice(
        coin: String,
        isBuy: Bool,
        slippage: Decimal,
        px: Decimal?
    ) async throws -> Decimal {
        var price = px
        if price == nil {
            let mids = try await infoAPI.allMids()
            let actualCoin = await infoAPI.getCoin(for: coin) ?? coin
            guard let midString = mids[actualCoin],
                  let mid = Decimal(string: midString)
            else {
                throw HyperliquidError.invalidParameter("No mid price for \(coin)")
            }
            price = mid
        }

        guard var finalPrice = price else {
            throw HyperliquidError.invalidParameter("Could not determine price")
        }

        // Apply slippage
        if isBuy {
            finalPrice *= (1 + slippage)
        } else {
            finalPrice *= (1 - slippage)
        }

        // Round to appropriate precision
        guard let asset = await infoAPI.nameToAsset(coin) else {
            throw HyperliquidError.invalidParameter("Unknown coin: \(coin)")
        }

        let isSpot = asset >= 10000
        let decimals = isSpot ? 8 : 6

        // Round to significant figures
        let rounded = roundToSignificantFigures(finalPrice, sigFigs: 5, maxDecimals: decimals)
        return rounded
    }

    /// Round to significant figures with max decimals
    private func roundToSignificantFigures(_ value: Decimal, sigFigs: Int, maxDecimals: Int) -> Decimal {
        let behavior = NSDecimalNumberHandler(
            roundingMode: .plain,
            scale: Int16(maxDecimals),
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        let nsValue = value as NSDecimalNumber
        return nsValue.rounding(accordingToBehavior: behavior) as Decimal
    }
}
