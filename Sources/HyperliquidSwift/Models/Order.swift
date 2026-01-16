import Foundation
import OrderedCollections

// MARK: - Order Request Types

public struct LimitOrderType: Sendable {
    public let tif: TimeInForce
    public init(tif: TimeInForce) { self.tif = tif }
}

public struct TriggerOrderType: Sendable {
    public let triggerPx: Decimal
    public let isMarket: Bool
    public let tpsl: TpSl
    public init(triggerPx: Decimal, isMarket: Bool, tpsl: TpSl) {
        self.triggerPx = triggerPx
        self.isMarket = isMarket
        self.tpsl = tpsl
    }
}

public enum OrderType: Sendable {
    case limit(LimitOrderType)
    case trigger(TriggerOrderType)
}

public struct OrderRequest: Sendable {
    public let coin: String
    public let isBuy: Bool
    public let sz: Decimal
    public let limitPx: Decimal
    public let orderType: OrderType
    public let reduceOnly: Bool
    public let cloid: Cloid?

    public init(
        coin: String, isBuy: Bool, sz: Decimal, limitPx: Decimal, orderType: OrderType, reduceOnly: Bool = false,
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

public struct ModifyRequest: Sendable {
    public let oidOrCloid: OidOrCloid
    public let order: OrderRequest
    public init(oidOrCloid: OidOrCloid, order: OrderRequest) {
        self.oidOrCloid = oidOrCloid
        self.order = order
    }
}

public enum OidOrCloid: Sendable {
    case oid(Int64)
    case cloid(Cloid)
}

public struct CancelRequest: Sendable {
    public let coin: String
    public let oid: Int64
    public init(coin: String, oid: Int64) {
        self.coin = coin
        self.oid = oid
    }
}

public struct CancelByCloidRequest: Sendable {
    public let coin: String
    public let cloid: Cloid
    public init(coin: String, cloid: Cloid) {
        self.coin = coin
        self.cloid = cloid
    }
}

public enum OrderGrouping: String, Sendable {
    case na
    case normalTpsl
    case positionTpsl
}

public struct BuilderInfo: Sendable, OrderedDictionaryConvertible {
    public let address: String
    public let fee: Int
    public init(address: String, fee: Int) {
        self.address = address
        self.fee = fee
    }

    public var asOrderedDictionary: OrderedDictionary<String, Sendable> {
        ["b": address.normalizedAddress, "f": fee]
    }
}

/// Protocol for types that can be converted to OrderedDictionary
public protocol OrderedDictionaryConvertible {
    var asOrderedDictionary: OrderedDictionary<String, Sendable> { get }
}

extension OrderedDictionaryConvertible {
    public var asDictionary: [String: Sendable] {
        Dictionary(uniqueKeysWithValues: asOrderedDictionary.map { ($0.key, $0.value) })
    }
}

// MARK: - Order Wire Format

public struct OrderWire: Sendable, OrderedDictionaryConvertible {
    public let a: Int
    public let b: Bool
    public let p: String
    public let s: String
    public let r: Bool
    public let t: OrderTypeWire
    public let c: String?

    public init(a: Int, b: Bool, p: String, s: String, r: Bool, t: OrderTypeWire, c: String?) {
        self.a = a
        self.b = b
        self.p = p
        self.s = s
        self.r = r
        self.t = t
        self.c = c
    }

    public var asOrderedDictionary: OrderedDictionary<String, Sendable> {
        var dict: OrderedDictionary<String, Sendable> = [
            "a": a, "b": b, "p": p, "s": s, "r": r, "t": t.asOrderedDictionary,
        ]
        if let c { dict["c"] = c }
        return dict
    }
}

public enum OrderTypeWire: Sendable, OrderedDictionaryConvertible {
    case limit(tif: TimeInForce)
    case trigger(triggerPx: String, isMarket: Bool, tpsl: TpSl)

    public var asOrderedDictionary: OrderedDictionary<String, Sendable> {
        switch self {
        case .limit(let tif):
            let inner: OrderedDictionary<String, Sendable> = ["tif": tif.rawValue]
            return ["limit": inner]
        case .trigger(let triggerPx, let isMarket, let tpsl):
            let inner: OrderedDictionary<String, Sendable> = [
                "isMarket": isMarket, "triggerPx": triggerPx, "tpsl": tpsl.rawValue,
            ]
            return ["trigger": inner]
        }
    }
}

public struct ModifyWire: Sendable, OrderedDictionaryConvertible {
    public let oid: Int64
    public let order: OrderWire

    public var asOrderedDictionary: OrderedDictionary<String, Sendable> {
        ["oid": oid, "order": order.asOrderedDictionary]
    }
}

// MARK: - Conversion Functions

public func orderTypeToWire(_ orderType: OrderType) throws -> OrderTypeWire {
    switch orderType {
    case .limit(let limit): return .limit(tif: limit.tif)
    case .trigger(let trigger):
        return .trigger(triggerPx: try trigger.triggerPx.toWireString(), isMarket: trigger.isMarket, tpsl: trigger.tpsl)
    }
}

public func orderRequestToOrderWire(_ order: OrderRequest, asset: Int) throws -> OrderWire {
    try OrderWire(
        a: asset, b: order.isBuy, p: order.limitPx.toWireString(), s: order.sz.toWireString(),
        r: order.reduceOnly, t: orderTypeToWire(order.orderType), c: order.cloid?.toRaw()
    )
}

public func orderWiresToOrderAction(orderWires: [OrderWire], builder: BuilderInfo? = nil, grouping: OrderGrouping = .na)
    -> OrderedDictionary<String, Sendable>
{
    var action: OrderedDictionary<String, Sendable> = [
        "type": "order", "orders": orderWires.map(\.asOrderedDictionary), "grouping": grouping.rawValue,
    ]
    if let builder { action["builder"] = builder.asOrderedDictionary }
    return action
}

// MARK: - Exchange Response Types

public struct OrderResponse: Codable, Sendable {
    public let status: String
    public let response: OrderResponseData?
}

public struct OrderResponseData: Codable, Sendable {
    public let type: String
    public let data: OrderResponseStatuses?
}

public struct OrderResponseStatuses: Codable, Sendable {
    public let statuses: [OrderPlacementStatus]
}

public struct OrderPlacementStatus: Codable, Sendable {
    public let oid: Int64?
    public let error: String?
    public let filled: FilledInfo?
    public let resting: RestingInfo?
}

public struct FilledInfo: Codable, Sendable {
    public let totalSz: String
    public let avgPx: String
    public let oid: Int64?
}

public struct RestingInfo: Codable, Sendable {
    public let oid: Int64
}

public struct CancelResponse: Codable, Sendable {
    public let status: String
    public let response: CancelResponseData?
}

public struct CancelResponseData: Codable, Sendable {
    public let type: String
    public let data: CancelResponseStatuses?
}

public struct CancelResponseStatuses: Codable, Sendable {
    public let statuses: [String]
}
