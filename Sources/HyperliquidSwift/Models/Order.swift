import Foundation
import OrderedCollections

// MARK: - Order Request Types

/// Order type for limit orders
public struct LimitOrderType: Sendable {
    /// Time in force
    public let tif: TimeInForce

    public init(tif: TimeInForce) {
        self.tif = tif
    }
}

/// Order type for trigger orders (TP/SL)
public struct TriggerOrderType: Sendable {
    /// Trigger price
    public let triggerPx: Decimal
    /// Whether this is a market order when triggered
    public let isMarket: Bool
    /// Take profit or stop loss
    public let tpsl: TpSl

    public init(triggerPx: Decimal, isMarket: Bool, tpsl: TpSl) {
        self.triggerPx = triggerPx
        self.isMarket = isMarket
        self.tpsl = tpsl
    }
}

/// Combined order type
public enum OrderType: Sendable {
    case limit(LimitOrderType)
    case trigger(TriggerOrderType)
}

/// Order request from user
public struct OrderRequest: Sendable {
    /// Coin name
    public let coin: String
    /// Whether this is a buy order
    public let isBuy: Bool
    /// Order size
    public let sz: Decimal
    /// Limit price
    public let limitPx: Decimal
    /// Order type
    public let orderType: OrderType
    /// Reduce only flag
    public let reduceOnly: Bool
    /// Optional client order ID
    public let cloid: Cloid?

    public init(
        coin: String,
        isBuy: Bool,
        sz: Decimal,
        limitPx: Decimal,
        orderType: OrderType,
        reduceOnly: Bool = false,
        cloid: Cloid? = nil
    ) {
        self.coin = coin
        self.isBuy = isBuy
        self.sz = sz
        self.limitPx = limitPx
        self.orderType = orderType
        self.reduceOnly = reduceOnly
        self.cloid = cloid
    }
}

/// Modify request
public struct ModifyRequest: Sendable {
    /// Order ID or Client order ID
    public let oidOrCloid: OidOrCloid
    /// New order parameters
    public let order: OrderRequest

    public init(oidOrCloid: OidOrCloid, order: OrderRequest) {
        self.oidOrCloid = oidOrCloid
        self.order = order
    }
}

/// Order ID or Client Order ID
public enum OidOrCloid: Sendable {
    case oid(Int64)
    case cloid(Cloid)
}

/// Cancel request by order ID
public struct CancelRequest: Sendable {
    /// Coin name
    public let coin: String
    /// Order ID
    public let oid: Int64

    public init(coin: String, oid: Int64) {
        self.coin = coin
        self.oid = oid
    }
}

/// Cancel request by client order ID
public struct CancelByCloidRequest: Sendable {
    /// Coin name
    public let coin: String
    /// Client order ID
    public let cloid: Cloid

    public init(coin: String, cloid: Cloid) {
        self.coin = coin
        self.cloid = cloid
    }
}

/// Order grouping type
public enum OrderGrouping: String, Sendable {
    case na
    case normalTpsl
    case positionTpsl
}

/// Builder info for fee sharing
public struct BuilderInfo: Sendable {
    /// Builder address
    public let address: String
    /// Fee in tenths of basis points (e.g., 10 = 1 basis point)
    public let fee: Int

    public init(address: String, fee: Int) {
        self.address = address
        self.fee = fee
    }

    public var asOrderedDictionary: OrderedDictionary<String, Any> {
        ["b": address.normalizedAddress, "f": fee]
    }

    public var asDictionary: [String: Any] {
        Dictionary(uniqueKeysWithValues: asOrderedDictionary.map { ($0.key, $0.value) })
    }
}

// MARK: - Order Wire Format

/// Order wire format for API
/// Reference: Python signing.py:51-62
public struct OrderWire: Sendable {
    /// Asset ID
    public let a: Int
    /// Is buy
    public let b: Bool
    /// Limit price (wire format)
    public let p: String
    /// Size (wire format)
    public let s: String
    /// Reduce only
    public let r: Bool
    /// Order type
    public let t: OrderTypeWire
    /// Optional client order ID
    public let c: String?

    /// Convert to ordered dictionary with Python SDK key order: a, b, p, s, r, t, [c]
    public var asOrderedDictionary: OrderedDictionary<String, Any> {
        var dict: OrderedDictionary<String, Any> = [
            "a": a,
            "b": b,
            "p": p,
            "s": s,
            "r": r,
            "t": t.asOrderedDictionary,
        ]
        if let c {
            dict["c"] = c
        }
        return dict
    }

    public var asDictionary: [String: Any] {
        Dictionary(uniqueKeysWithValues: asOrderedDictionary.map { ($0.key, $0.value) })
    }
}

/// Order type wire format
public enum OrderTypeWire: Sendable {
    case limit(tif: TimeInForce)
    case trigger(triggerPx: String, isMarket: Bool, tpsl: TpSl)

    public var asOrderedDictionary: OrderedDictionary<String, Any> {
        switch self {
        case let .limit(tif):
            let inner: OrderedDictionary<String, Any> = ["tif": tif.rawValue]
            return ["limit": inner]
        case let .trigger(triggerPx, isMarket, tpsl):
            // Field order must match Python SDK: isMarket, triggerPx, tpsl
            let inner: OrderedDictionary<String, Any> = [
                "isMarket": isMarket,
                "triggerPx": triggerPx,
                "tpsl": tpsl.rawValue,
            ]
            return ["trigger": inner]
        }
    }

    public var asDictionary: [String: Any] {
        Dictionary(uniqueKeysWithValues: asOrderedDictionary.map { ($0.key, $0.value) })
    }
}

/// Modify wire format
public struct ModifyWire: Sendable {
    /// Order ID
    public let oid: Int64
    /// Order wire
    public let order: OrderWire

    public var asOrderedDictionary: OrderedDictionary<String, Any> {
        ["oid": oid, "order": order.asOrderedDictionary]
    }

    public var asDictionary: [String: Any] {
        Dictionary(uniqueKeysWithValues: asOrderedDictionary.map { ($0.key, $0.value) })
    }
}

// MARK: - Conversion Functions

/// Convert order type to wire format
/// Reference: Python signing.py:148-159
public func orderTypeToWire(_ orderType: OrderType) throws -> OrderTypeWire {
    switch orderType {
    case let .limit(limit):
        return .limit(tif: limit.tif)
    case let .trigger(trigger):
        let triggerPxWire = try trigger.triggerPx.toWireString()
        return .trigger(triggerPx: triggerPxWire, isMarket: trigger.isMarket, tpsl: trigger.tpsl)
    }
}

/// Convert order request to wire format
/// Reference: Python signing.py:487-498
public func orderRequestToOrderWire(_ order: OrderRequest, asset: Int) throws -> OrderWire {
    let orderTypeWire = try orderTypeToWire(order.orderType)

    return try OrderWire(
        a: asset,
        b: order.isBuy,
        p: order.limitPx.toWireString(),
        s: order.sz.toWireString(),
        r: order.reduceOnly,
        t: orderTypeWire,
        c: order.cloid?.toRaw()
    )
}

/// Build order action from order wires
/// Reference: Python signing.py:501-509
/// Key order: type, orders, grouping, [builder]
public func orderWiresToOrderAction(
    orderWires: [OrderWire],
    builder: BuilderInfo? = nil,
    grouping: OrderGrouping = .na
) -> OrderedDictionary<String, Any> {
    var action: OrderedDictionary<String, Any> = [
        "type": "order",
        "orders": orderWires.map(\.asOrderedDictionary),
        "grouping": grouping.rawValue,
    ]
    if let builder {
        action["builder"] = builder.asOrderedDictionary
    }
    return action
}

// MARK: - Exchange Response Types

/// Order placement response
public struct OrderResponse: Codable, Sendable {
    /// Status of the response
    public let status: String
    /// Response data
    public let response: OrderResponseData?
}

/// Order response data
public struct OrderResponseData: Codable, Sendable {
    /// Response type
    public let type: String
    /// Order statuses
    public let data: OrderResponseStatuses?
}

/// Order statuses in response
public struct OrderResponseStatuses: Codable, Sendable {
    /// List of order statuses
    public let statuses: [OrderPlacementStatus]
}

/// Individual order placement status
public struct OrderPlacementStatus: Codable, Sendable {
    /// Order ID if successful
    public let oid: Int64?
    /// Error message if failed
    public let error: String?
    /// Filled info
    public let filled: FilledInfo?
    /// Resting info
    public let resting: RestingInfo?
}

/// Filled order info
public struct FilledInfo: Codable, Sendable {
    /// Total size filled
    public let totalSz: String
    /// Average fill price
    public let avgPx: String
    /// Order ID
    public let oid: Int64?
}

/// Resting order info
public struct RestingInfo: Codable, Sendable {
    /// Order ID
    public let oid: Int64
}

/// Cancel response
public struct CancelResponse: Codable, Sendable {
    /// Status
    public let status: String
    /// Response data
    public let response: CancelResponseData?
}

/// Cancel response data
public struct CancelResponseData: Codable, Sendable {
    /// Response type
    public let type: String
    /// Cancel statuses
    public let data: CancelResponseStatuses?
}

/// Cancel statuses
public struct CancelResponseStatuses: Codable, Sendable {
    /// List of cancel statuses
    public let statuses: [String]
}
