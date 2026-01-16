import Foundation
import OrderedCollections

/// Exchange API for trading operations on Hyperliquid. Reference: Python SDK hyperliquid/exchange.py
public actor ExchangeAPI {
    private let httpClient: HTTPClient
    private let network: HyperliquidNetwork
    private let signerType: SignerType
    private var infoAPI: InfoAPI

    /// Vault address for trading on behalf of a vault
    public var vaultAddress: String? {
        didSet { vaultAddress = vaultAddress?.normalizedAddress }
    }

    /// Account address (for sub-account operations)
    public var accountAddress: String? {
        didSet { accountAddress = accountAddress?.normalizedAddress }
    }

    /// Expiration timestamp for actions (optional)
    public var expiresAfter: Int64?

    /// Default slippage for market orders (5%)
    public static let defaultSlippage: Decimal = 0.05

    /// Internal enum to distinguish signer types
    private enum SignerType: Sendable {
        case hyperliquid(HyperliquidSigner)
        case eip712(EIP712Signer)

        var address: String {
            switch self {
            case .hyperliquid(let signer): signer.address
            case .eip712(let signer): signer.address
            }
        }

        func signL1(actionHash: Data, isMainnet: Bool) async throws -> Signature {
            switch self {
            case .hyperliquid(let signer):
                let messageHash = EIP712.hashTypedDataL1(actionHash: actionHash, isMainnet: isMainnet)
                return try await signer.sign(messageHash: messageHash)
            case .eip712(let signer):
                let typedData = EIP712.buildTypedDataL1(actionHash: actionHash, isMainnet: isMainnet)
                let hex = try await signer.signTypedData(typedData)
                return try Signature.fromHex(hex)
            }
        }

        func signUserSigned(
            action: [String: Sendable],
            signTypes: [TypedVariable],
            primaryType: UserSignedPrimaryType,
            isMainnet: Bool
        ) async throws -> Signature {
            switch self {
            case .hyperliquid(let signer):
                let messageHash = try EIP712.hashTypedDataUserSigned(
                    action: action,
                    signTypes: signTypes,
                    primaryType: primaryType,
                    isMainnet: isMainnet
                )
                return try await signer.sign(messageHash: messageHash)
            case .eip712(let signer):
                let typedData = EIP712.buildTypedDataUserSigned(
                    action: action,
                    signTypes: signTypes,
                    primaryType: primaryType,
                    isMainnet: isMainnet
                )
                let hex = try await signer.signTypedData(typedData)
                return try Signature.fromHex(hex)
            }
        }
    }

    /// Initialize Exchange API with HyperliquidSigner
    public init(
        signer: HyperliquidSigner,
        network: HyperliquidNetwork = .mainnet,
        vaultAddress: String? = nil,
        accountAddress: String? = nil
    ) async throws {
        self.init(type: .hyperliquid(signer), network: network, vault: vaultAddress, account: accountAddress)
    }

    /// Initialize Exchange API with EIP712Signer
    public init(
        eip712Signer: EIP712Signer,
        network: HyperliquidNetwork = .mainnet,
        vaultAddress: String? = nil,
        accountAddress: String? = nil
    ) async throws {
        self.init(type: .eip712(eip712Signer), network: network, vault: vaultAddress, account: accountAddress)
    }

    private init(
        type: SignerType,
        network: HyperliquidNetwork,
        vault: String?,
        account: String?
    ) {
        self.signerType = type
        self.network = network
        self.httpClient = HTTPClient(baseURL: network.baseURL)
        self.vaultAddress = vault?.normalizedAddress
        self.accountAddress = account?.normalizedAddress
        self.infoAPI = InfoAPI(network: network)
    }

    private var isMainnet: Bool { network == .mainnet }

    // MARK: - Internal Helpers

    private func postAction(
        action: Sendable,  // Can be [String: Sendable] or OrderedDictionary<String, Sendable>
        signature: Signature,
        nonce: Int64
    ) async throws -> Data {
        let actionDict: [String: Sendable] =
            (action as? OrderedDictionary<String, Sendable>).map(convertToSerializable)
            ?? (action as? [String: Sendable] ?? [:])

        var payload: [String: Sendable] = [
            "action": actionDict,
            "nonce": nonce,
            "signature": signature.asDictionary,
        ]

        let actionType = actionDict["type"] as? String ?? ""
        // User-signed actions (usdClassTransfer, sendAsset) are account-level and exclude vaultAddress
        if actionType != "usdClassTransfer", actionType != "sendAsset" {
            if let vault = vaultAddress { payload["vaultAddress"] = vault } else { payload["vaultAddress"] = NSNull() }
        } else {
            payload["vaultAddress"] = NSNull()
        }

        if let expires = expiresAfter { payload["expiresAfter"] = expires } else { payload["expiresAfter"] = NSNull() }

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        return try await httpClient.postExchangeRawData(jsonData)
    }

    private func convertToSerializable(_ dict: OrderedDictionary<String, Sendable>) -> [String: Sendable] {
        var result: [String: Sendable] = [:]
        for (key, value) in dict {
            if let nested = value as? OrderedDictionary<String, Sendable> {
                result[key] = convertToSerializable(nested)
            } else if let array = value as? [OrderedDictionary<String, Sendable>] {
                result[key] = array.map { convertToSerializable($0) }
            } else {
                result[key] = value
            }
        }
        return result
    }

    private func signL1Action(action: OrderedDictionary<String, Sendable>, nonce: Int64) async throws -> Signature {
        let actionHash = try ActionHash.compute(
            action: action,
            vaultAddress: vaultAddress,
            nonce: nonce,
            expiresAfter: expiresAfter
        )
        return try await signerType.signL1(actionHash: actionHash, isMainnet: isMainnet)
    }

    private func signL1Action(action: [String: Sendable], nonce: Int64) async throws -> Signature {
        let actionHash = try ActionHash.compute(
            action: action,
            vaultAddress: vaultAddress,
            nonce: nonce,
            expiresAfter: expiresAfter
        )
        return try await signerType.signL1(actionHash: actionHash, isMainnet: isMainnet)
    }

    // MARK: - Order Operations

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
        try await bulkOrders(
            orders: [
                OrderRequest(
                    coin: coin, isBuy: isBuy, sz: sz, limitPx: limitPx, orderType: orderType, reduceOnly: reduceOnly,
                    cloid: cloid)
            ], builder: builder)
    }

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
            orderWires.append(try orderRequestToOrderWire(order, asset: asset))
        }

        let action = orderWiresToOrderAction(orderWires: orderWires, builder: builder, grouping: grouping)
        let signature = try await signL1Action(action: action, nonce: timestamp)
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

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
        let req = OrderRequest(
            coin: coin, isBuy: isBuy, sz: sz, limitPx: limitPx, orderType: orderType, reduceOnly: reduceOnly,
            cloid: cloid)
        return try await bulkModifyOrders(modifies: [ModifyRequest(oidOrCloid: oid, order: req)])
    }

    public func bulkModifyOrders(modifies: [ModifyRequest]) async throws -> Data {
        let timestamp = currentTimestampMs()
        var modifyWires: [[String: Sendable]] = []

        for modify in modifies {
            guard let asset = await infoAPI.nameToAsset(modify.order.coin) else {
                throw HyperliquidError.invalidParameter("Unknown coin: \(modify.order.coin)")
            }
            let oidValue: Sendable =
                switch modify.oidOrCloid {
                case .oid(let oid): oid
                case .cloid(let cloid): cloid.toRaw()
                }
            modifyWires.append([
                "oid": oidValue,
                "order": (try orderRequestToOrderWire(modify.order, asset: asset)).asDictionary,
            ])
        }

        let action: [String: Sendable] = ["type": "batchModify", "modifies": modifyWires]
        let signature = try await signL1Action(action: action, nonce: timestamp)
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    public func cancel(coin: String, oid: Int64) async throws -> Data {
        try await bulkCancel(cancels: [CancelRequest(coin: coin, oid: oid)])
    }

    public func bulkCancel(cancels: [CancelRequest]) async throws -> Data {
        let timestamp = currentTimestampMs()
        var cancelWires: [[String: Sendable]] = []

        for cancel in cancels {
            guard let asset = await infoAPI.nameToAsset(cancel.coin) else {
                throw HyperliquidError.invalidParameter("Unknown coin: \(cancel.coin)")
            }
            cancelWires.append(["a": asset, "o": cancel.oid])
        }

        let action: [String: Sendable] = ["type": "cancel", "cancels": cancelWires]
        let signature = try await signL1Action(action: action, nonce: timestamp)
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    public func cancelByCloid(coin: String, cloid: Cloid) async throws -> Data {
        try await bulkCancelByCloid(cancels: [CancelByCloidRequest(coin: coin, cloid: cloid)])
    }

    public func bulkCancelByCloid(cancels: [CancelByCloidRequest]) async throws -> Data {
        let timestamp = currentTimestampMs()
        var cancelWires: [[String: Sendable]] = []

        for cancel in cancels {
            guard let asset = await infoAPI.nameToAsset(cancel.coin) else {
                throw HyperliquidError.invalidParameter("Unknown coin: \(cancel.coin)")
            }
            cancelWires.append(["asset": asset, "cloid": cancel.cloid.toRaw()])
        }

        let action: [String: Sendable] = ["type": "cancelByCloid", "cancels": cancelWires]
        let signature = try await signL1Action(action: action, nonce: timestamp)
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    public func scheduleCancel(time: Int64?) async throws -> Data {
        let timestamp = currentTimestampMs()
        var action: [String: Sendable] = ["type": "scheduleCancel"]
        if let time { action["time"] = time }

        let signature = try await signL1Action(action: action, nonce: timestamp)
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    // MARK: - Account Operations

    public func updateLeverage(leverage: Int, coin: String, isCross: Bool = true) async throws -> Data {
        try await runAction(
            coin: coin,
            builder: { asset in
                ["type": "updateLeverage", "asset": asset, "isCross": isCross, "leverage": leverage]
            }
        )
    }

    public func updateIsolatedMargin(amount: Decimal, coin: String) async throws -> Data {
        let amountInt = try amount.toUSDInt()
        return try await runAction(
            coin: coin,
            builder: { asset in
                ["type": "updateIsolatedMargin", "asset": asset, "isBuy": true, "ntli": amountInt]
            }
        )
    }

    private func runAction(coin: String, builder: (Int) -> [String: Sendable]) async throws -> Data {
        let timestamp = currentTimestampMs()
        guard let asset = await infoAPI.nameToAsset(coin) else {
            throw HyperliquidError.invalidParameter("Unknown coin: \(coin)")
        }
        let action = builder(asset)
        let signature = try await signL1Action(action: action, nonce: timestamp)
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    public func setReferrer(code: String) async throws -> Data {
        try await runVaultlessAction(action: ["type": "setReferrer", "code": code])
    }

    public func createSubAccount(name: String) async throws -> Data {
        try await runVaultlessAction(action: ["type": "createSubAccount", "name": name])
    }

    private func runVaultlessAction(action: [String: Sendable]) async throws -> Data {
        let timestamp = currentTimestampMs()
        let savedVault = vaultAddress
        vaultAddress = nil
        defer { vaultAddress = savedVault }
        let signature = try await signL1Action(action: action, nonce: timestamp)
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    // MARK: - Transfer Operations (User-Signed)

    public func usdClassTransfer(amount: Decimal, toPerp: Bool) async throws -> Data {
        let timestamp = currentTimestampMs()
        var strAmount = try amount.toWireString()
        if let vaultAddress { strAmount += " subaccount:\(vaultAddress)" }

        let action: [String: Sendable] = [
            "type": "usdClassTransfer",
            "amount": strAmount,
            "toPerp": toPerp,
            "nonce": timestamp,
        ]

        let signature = try await signerType.signUserSigned(
            action: action,
            signTypes: usdClassTransferSignTypes,
            primaryType: .usdClassTransfer,
            isMainnet: isMainnet
        )
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    public func sendAsset(
        destination: String, sourceDex: String = "", destinationDex: String = "", token: String, amount: Decimal
    ) async throws -> Data {
        let timestamp = currentTimestampMs()
        let action: [String: Sendable] = [
            "type": "sendAsset",
            "destination": destination.normalizedAddress,
            "sourceDex": sourceDex,
            "destinationDex": destinationDex,
            "token": token,
            "amount": try amount.toWireString(),
            "fromSubAccount": vaultAddress ?? "",
            "nonce": timestamp,
        ]

        let signature = try await signerType.signUserSigned(
            action: action,
            signTypes: sendAssetSignTypes,
            primaryType: .sendAsset,
            isMainnet: isMainnet
        )
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    public func subAccountTransfer(subAccountUser: String, isDeposit: Bool, usd: Int64) async throws -> Data {
        try await runVaultlessAction(action: [
            "type": "subAccountTransfer",
            "subAccountUser": subAccountUser.normalizedAddress,
            "isDeposit": isDeposit,
            "usd": usd,
        ])
    }

    public func subAccountSpotTransfer(subAccountUser: String, isDeposit: Bool, token: String, amount: Decimal)
        async throws -> Data
    {
        try await runVaultlessAction(action: [
            "type": "subAccountSpotTransfer",
            "subAccountUser": subAccountUser.normalizedAddress,
            "isDeposit": isDeposit,
            "token": token,
            "amount": try amount.toWireString(),
        ])
    }

    public func vaultUsdTransfer(vaultAddress: String, isDeposit: Bool, usd: Int64) async throws -> Data {
        let timestamp = currentTimestampMs()
        let action: [String: Sendable] = [
            "type": "vaultTransfer",
            "vaultAddress": vaultAddress.normalizedAddress,
            "isDeposit": isDeposit,
            "usd": usd,
        ]

        let savedVault = self.vaultAddress
        self.vaultAddress = nil
        defer { self.vaultAddress = savedVault }

        let signature = try await signL1Action(action: action, nonce: timestamp)
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    public func usdTransfer(amount: Decimal, destination: String) async throws -> Data {
        try await runUserSignedAction(
            action: [
                "type": "usdSend", "destination": destination.normalizedAddress, "amount": try amount.toWireString(),
            ],
            signTypes: usdSendSignTypes,
            primaryType: .usdSend
        )
    }

    public func spotTransfer(amount: Decimal, destination: String, token: String) async throws -> Data {
        try await runUserSignedAction(
            action: [
                "type": "spotSend", "destination": destination.normalizedAddress, "amount": try amount.toWireString(),
                "token": token,
            ],
            signTypes: spotTransferSignTypes,
            primaryType: .spotSend
        )
    }

    public func tokenDelegate(validator: String, wei: UInt64, isUndelegate: Bool) async throws -> Data {
        try await runUserSignedAction(
            action: [
                "type": "tokenDelegate", "validator": validator.normalizedAddress, "wei": wei,
                "isUndelegate": isUndelegate,
            ],
            signTypes: tokenDelegateSignTypes,
            primaryType: .tokenDelegate,
            includeNonceInAction: true
        )
    }

    public func withdrawFromBridge(amount: Decimal, destination: String) async throws -> Data {
        try await runUserSignedAction(
            action: [
                "type": "withdraw3", "destination": destination.normalizedAddress, "amount": try amount.toWireString(),
            ],
            signTypes: withdrawSignTypes,
            primaryType: .withdraw
        )
    }

    private func runUserSignedAction(
        action: [String: Sendable],
        signTypes: [TypedVariable],
        primaryType: UserSignedPrimaryType,
        includeNonceInAction: Bool = false
    ) async throws -> Data {
        let timestamp = currentTimestampMs()
        var fullAction = action
        if includeNonceInAction { fullAction["nonce"] = timestamp } else { fullAction["time"] = timestamp }

        let signature = try await signerType.signUserSigned(
            action: fullAction, signTypes: signTypes, primaryType: primaryType, isMainnet: isMainnet)
        return try await postAction(action: fullAction, signature: signature, nonce: timestamp)
    }

    // MARK: - Agent/Builder Operations

    public func approveAgent(agentAddress: String, agentName: String = "") async throws -> Data {
        let timestamp = currentTimestampMs()
        var action: [String: Sendable] = [
            "type": "approveAgent",
            "agentAddress": agentAddress.normalizedAddress,
            "nonce": timestamp,
        ]
        if !agentName.isEmpty { action["agentName"] = agentName }

        let signature = try await signerType.signUserSigned(
            action: action,
            signTypes: approveAgentSignTypes,
            primaryType: .approveAgent,
            isMainnet: isMainnet
        )
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    public func approveBuilderFee(builder: String, maxFeeRate: String) async throws -> Data {
        try await runUserSignedAction(
            action: ["type": "approveBuilderFee", "builder": builder.normalizedAddress, "maxFeeRate": maxFeeRate],
            signTypes: approveBuilderFeeSignTypes,
            primaryType: .approveBuilderFee,
            includeNonceInAction: true
        )
    }

    // MARK: - MultiSig & Dex Abstraction

    public func convertToMultiSigUser(authorizedUsers: [String], threshold: Int) async throws -> Data {
        let timestamp = currentTimestampMs()
        let signersConfig = MultiSigSignerConfig(authorizedUsers: authorizedUsers.sorted(), threshold: threshold)
        let signersData = try JSONEncoder().encode(signersConfig)
        guard let signersString = String(data: signersData, encoding: .utf8) else {
            throw HyperliquidError.invalidParameter("Failed to encode signers config")
        }

        return try await runUserSignedAction(
            action: [
                "type": "convertToMultiSigUser",
                "signers": signersString,
                "nonce": timestamp,
            ],
            signTypes: convertToMultiSigUserSignTypes,
            primaryType: .convertToMultiSigUser
        )
    }

    public func multiSig(
        multiSigUser: String,
        innerAction: [String: Sendable],
        signatures: [Signature],
        nonce: Int64
    ) async throws -> Data {
        let outerSigner = signerType.address.normalizedAddress
        let payload: [String: Sendable] = [
            "multiSigUser": multiSigUser.normalizedAddress,
            "outerSigner": outerSigner,
            "action": innerAction,
        ]

        let multiSigAction: [String: Sendable] = [
            "type": "multiSig",
            "signatureChainId": "0x66eee",
            "signatures": signatures.map { $0.asDictionary },
            "payload": payload,
        ]

        // Prepare action for hashing (remove type)
        var actionForHashing = multiSigAction
        actionForHashing.removeValue(forKey: "type")

        // Compute action hash (L1 style hashing)
        let multiSigActionHash = try ActionHash.compute(
            action: actionForHashing,
            vaultAddress: vaultAddress,
            nonce: nonce,
            expiresAfter: expiresAfter
        )

        let envelope: [String: Sendable] = [
            "multiSigActionHash": multiSigActionHash,
            "nonce": nonce,
        ]

        let signature = try await signerType.signUserSigned(
            action: envelope,
            signTypes: multiSigEnvelopeSignTypes,
            primaryType: .multiSigEnvelope,
            isMainnet: isMainnet
        )

        return try await postAction(action: multiSigAction, signature: signature, nonce: nonce)
    }

    public func useBigBlocks(enable: Bool) async throws -> Data {
        try await runAction(
            action: ["type": "evmUserModify", "usingBigBlocks": enable]
        )
    }

    public func agentEnableDexAbstraction() async throws -> Data {
        try await runAction(action: ["type": "agentEnableDexAbstraction"])
    }

    public func userDexAbstraction(user: String, enabled: Bool) async throws -> Data {
        try await runUserSignedAction(
            action: [
                "type": "userDexAbstraction",
                "user": user.normalizedAddress,
                "enabled": enabled,
            ],
            signTypes: userDexAbstractionSignTypes,
            primaryType: .userDexAbstraction,
            includeNonceInAction: true
        )
    }

    private func runAction(action: [String: Sendable]) async throws -> Data {
        let timestamp = currentTimestampMs()
        let signature = try await signL1Action(action: action, nonce: timestamp)
        return try await postAction(action: action, signature: signature, nonce: timestamp)
    }

    // MARK: - Spot Deployment

    public func spotDeployRegisterToken(
        tokenName: String, szDecimals: Int, weiDecimals: Int, maxGas: Int, fullName: String
    ) async throws -> Data {
        let spec: [String: Sendable] = ["name": tokenName, "szDecimals": szDecimals, "weiDecimals": weiDecimals]
        let registerToken2: [String: Sendable] = [
            "spec": spec,
            "maxGas": maxGas,
            "fullName": fullName,
        ]
        return try await runAction(action: ["type": "spotDeploy", "registerToken2": registerToken2])
    }

    public func spotDeployUserGenesis(
        token: Int, userAndWei: [(String, String)], existingTokenAndWei: [(Int, String)]
    ) async throws -> Data {
        let userAndWeiMapped: [[Sendable]] = userAndWei.map { [$0.0.normalizedAddress, $0.1] }
        let existingTokenAndWeiMapped: [[Sendable]] = existingTokenAndWei.map { [$0.0, $0.1] }
        let userGenesis: [String: Sendable] = [
            "token": token,
            "userAndWei": userAndWeiMapped,
            "existingTokenAndWei": existingTokenAndWeiMapped,
        ]
        return try await runAction(action: ["type": "spotDeploy", "userGenesis": userGenesis])
    }

    public func spotDeployGenesis(token: Int, maxSupply: String, noHyperliquidity: Bool) async throws -> Data {
        var genesis: [String: Sendable] = ["token": token, "maxSupply": maxSupply]
        if noHyperliquidity { genesis["noHyperliquidity"] = true }
        return try await runAction(action: ["type": "spotDeploy", "genesis": genesis])
    }

    public func spotDeployRegisterSpot(baseToken: Int, quoteToken: Int) async throws -> Data {
        let tokens: [Int] = [baseToken, quoteToken]
        let registerSpot: [String: Sendable] = ["tokens": tokens]
        return try await runAction(
            action: [
                "type": "spotDeploy",
                "registerSpot": registerSpot,
            ]
        )
    }

    public func spotDeployRegisterHyperliquidity(
        spot: Int, startPx: Decimal, orderSz: Decimal, nOrders: Int, nSeededLevels: Int? = nil
    ) async throws -> Data {
        var registerHyperliquidity: [String: Sendable] = [
            "spot": spot,
            "startPx": try startPx.toWireString(),
            "orderSz": try orderSz.toWireString(),
            "nOrders": nOrders,
        ]
        if let nSeededLevels { registerHyperliquidity["nSeededLevels"] = nSeededLevels }
        return try await runAction(action: ["type": "spotDeploy", "registerHyperliquidity": registerHyperliquidity])
    }

    public func spotDeploySetDeployerTradingFeeShare(token: Int, share: String) async throws -> Data {
        let payload: [String: Sendable] = ["token": token, "share": share]
        return try await runAction(
            action: [
                "type": "spotDeploy",
                "setDeployerTradingFeeShare": payload,
            ]
        )
    }

    public func spotDeployEnableFreezePrivilege(token: Int) async throws -> Data {
        try await spotDeployTokenActionInner(variant: "enableFreezePrivilege", token: token)
    }

    public func spotDeployFreezeUser(token: Int, user: String, freeze: Bool) async throws -> Data {
        let freezeUser: [String: Sendable] = [
            "token": token,
            "user": user.normalizedAddress,
            "freeze": freeze,
        ]
        return try await runAction(action: ["type": "spotDeploy", "freezeUser": freezeUser])
    }

    public func spotDeployRevokeFreezePrivilege(token: Int) async throws -> Data {
        try await spotDeployTokenActionInner(variant: "revokeFreezePrivilege", token: token)
    }

    public func spotDeployEnableQuoteToken(token: Int) async throws -> Data {
        try await spotDeployTokenActionInner(variant: "enableQuoteToken", token: token)
    }

    private func spotDeployTokenActionInner(variant: String, token: Int) async throws -> Data {
        let payload: [String: Sendable] = ["token": token]
        return try await runAction(
            action: [
                "type": "spotDeploy",
                variant: payload,
            ]
        )
    }

    // MARK: - Perp Deployment & Validator

    public func perpDeployRegisterAsset(
        dex: String,
        maxGas: Int?,
        coin: String,
        szDecimals: Int,
        oraclePx: Decimal,
        marginTableId: Int,
        onlyIsolated: Bool,
        schema: PerpDexSchemaInput?
    ) async throws -> Data {
        let assetRequest: [String: Sendable] = [
            "coin": coin,
            "szDecimals": szDecimals,
            "oraclePx": try oraclePx.toWireString(),
            "marginTableId": marginTableId,
            "onlyIsolated": onlyIsolated,
        ]

        var registerAsset: [String: Sendable] = [
            "dex": dex,
            "assetRequest": assetRequest,
        ]
        if let maxGas { registerAsset["maxGas"] = maxGas } else { registerAsset["maxGas"] = NSNull() }

        if let schema {
            var schemaWire: [String: Sendable] = [
                "fullName": schema.fullName,
                "collateralToken": schema.collateralToken,
            ]
            if let oracleUpdater = schema.oracleUpdater {
                schemaWire["oracleUpdater"] = oracleUpdater.normalizedAddress
            } else {
                schemaWire["oracleUpdater"] = NSNull()
            }
            registerAsset["schema"] = schemaWire
        } else {
            registerAsset["schema"] = NSNull()
        }

        return try await runAction(action: ["type": "perpDeploy", "registerAsset": registerAsset])
    }

    public func perpDeploySetOracle(
        dex: String,
        oraclePxs: [String: Decimal],
        allMarkPxs: [[String: Decimal]],
        externalPerpPxs: [String: Decimal]
    ) async throws -> Data {
        // Map tuples to [String: Sendable] compatible arrays (e.g. [[String]]) which are Sendable
        let oraclePxsWire: [[String]] = try oraclePxs.map { [$0.key, try $0.value.toWireString()] }.sorted {
            $0[0] < $1[0]
        }
        let allMarkPxsWire: [[[String]]] = try allMarkPxs.map { markPxs in
            try markPxs.map { [$0.key, try $0.value.toWireString()] }.sorted { $0[0] < $1[0] }
        }
        let externalPerpPxsWire: [[String]] = try externalPerpPxs.map { [$0.key, try $0.value.toWireString()] }.sorted {
            $0[0] < $1[0]
        }

        let setOracle: [String: Sendable] = [
            "dex": dex,
            "oraclePxs": oraclePxsWire,
            "markPxs": allMarkPxsWire,
            "externalPerpPxs": externalPerpPxsWire,
        ]

        return try await runAction(
            action: [
                "type": "perpDeploy",
                "setOracle": setOracle,
            ]
        )
    }

    public func cSignerUnjailSelf() async throws -> Data {
        try await cSignerInner(variant: "unjailSelf")
    }

    public func cSignerJailSelf() async throws -> Data {
        try await cSignerInner(variant: "jailSelf")
    }

    private func cSignerInner(variant: String) async throws -> Data {
        try await runAction(
            action: [
                "type": "CSignerAction",
                variant: NSNull(),
            ]
        )
    }

    public func cValidatorRegister(
        nodeIp: String,
        name: String,
        description: String,
        delegationsDisabled: Bool,
        commissionBps: Int,
        signer: String,
        unjailed: Bool,
        initialWei: UInt64
    ) async throws -> Data {
        let nodeIpDict: [String: Sendable] = ["Ip": nodeIp]
        let profile: [String: Sendable] = [
            "node_ip": nodeIpDict,
            "name": name,
            "description": description,
            "delegations_disabled": delegationsDisabled,
            "commission_bps": commissionBps,
            "signer": signer.normalizedAddress,
        ]
        let register: [String: Sendable] = [
            "profile": profile,
            "unjailed": unjailed,
            "initial_wei": initialWei,
        ]
        return try await runAction(action: ["type": "CValidatorAction", "register": register])
    }

    public func cValidatorChangeProfile(
        nodeIp: String?,
        name: String?,
        description: String?,
        unjailed: Bool,
        disableDelegations: Bool?,
        commissionBps: Int?,
        signer: String?
    ) async throws -> Data {
        let profile: [String: Sendable] = [
            "unjailed": unjailed,
            "node_ip": nodeIp.map { ["Ip": $0] as [String: Sendable] } ?? NSNull() as Sendable,
            "name": name ?? NSNull() as Sendable,
            "description": description ?? NSNull() as Sendable,
            "disable_delegations": disableDelegations ?? NSNull() as Sendable,
            "commission_bps": commissionBps ?? NSNull() as Sendable,
            "signer": signer?.normalizedAddress ?? NSNull() as Sendable,
        ]

        return try await runAction(action: ["type": "CValidatorAction", "changeProfile": profile])
    }

    public func cValidatorUnregister() async throws -> Data {
        try await runAction(action: ["type": "CValidatorAction", "unregister": NSNull()])
    }

    // MARK: - Market Orders (Convenience)

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

    public func marketClose(
        coin: String,
        sz: Decimal? = nil,
        px: Decimal? = nil,
        slippage: Decimal = defaultSlippage,
        cloid: Cloid? = nil,
        builder: BuilderInfo? = nil
    ) async throws -> Data {
        let address = accountAddress ?? vaultAddress ?? signerType.address
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

    private func calculateSlippagePrice(
        coin: String,
        isBuy: Bool,
        slippage: Decimal,
        px: Decimal?
    ) async throws -> Decimal {
        var price = px
        if price == nil {
            let mids = try await infoAPI.allMids()
            guard let midString = mids[await infoAPI.getCoin(for: coin) ?? coin],
                let mid = Decimal(string: midString)
            else {
                throw HyperliquidError.invalidParameter("No mid price for \(coin)")
            }
            price = mid
        }

        guard var finalPrice = price else { throw HyperliquidError.invalidParameter("Could not determine price") }
        finalPrice *= (isBuy ? 1 + slippage : 1 - slippage)

        guard let asset = await infoAPI.nameToAsset(coin) else {
            throw HyperliquidError.invalidParameter("Unknown coin: \(coin)")
        }

        return roundToSignificantFigures(finalPrice, sigFigs: 5, maxDecimals: asset >= 10000 ? 8 : 6)
    }

    private func roundToSignificantFigures(_ value: Decimal, sigFigs: Int, maxDecimals: Int) -> Decimal {
        let behavior = NSDecimalNumberHandler(
            roundingMode: .plain,
            scale: Int16(maxDecimals),
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        return (value as NSDecimalNumber).rounding(accordingToBehavior: behavior) as Decimal
    }
}
