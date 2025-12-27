import BigInt
import Foundation
import OrderedCollections

/// Action hash computation (Python SDK signing.py:166-177)
public enum ActionHash {
    /// Compute the action hash for L1 signing
    public static func compute(
        action: OrderedDictionary<String, Any>,
        vaultAddress: String?,
        nonce: Int64,
        expiresAfter: Int64?
    ) throws -> Data {
        let actionData = try packAction(action)
        var data = Data()

        data.append(actionData)
        data.append(contentsOf: withUnsafeBytes(of: nonce.bigEndian) { Array($0) })

        if let vaultAddress {
            data.append(0x01)
            guard let addressBytes = vaultAddress.addressToBytes() else {
                throw HyperliquidError.invalidAddress(vaultAddress)
            }
            data.append(addressBytes)
        } else {
            data.append(0x00)
        }

        if let expiresAfter {
            data.append(0x00)
            data.append(contentsOf: withUnsafeBytes(of: expiresAfter.bigEndian) { Array($0) })
        }

        return data.keccak256
    }

    /// Compute action hash with sorted keys (convenience overload)
    public static func compute(
        action: [String: Any],
        vaultAddress: String?,
        nonce: Int64,
        expiresAfter: Int64?
    ) throws -> Data {
        let orderedAction = OrderedDictionary<String, Any>(
            uniqueKeys: action.keys.sorted(),
            values: action.keys.sorted().map { action[$0]! }
        )
        return try compute(action: orderedAction, vaultAddress: vaultAddress, nonce: nonce, expiresAfter: expiresAfter)
    }

    private static func packAction(_ action: OrderedDictionary<String, Any>) throws -> Data {
        try MessagePackPacker.pack(action)
    }
}

/// Manual MessagePack packer preserving OrderedDictionary key order
enum MessagePackPacker {
    static func pack(_ value: Any) throws -> Data {
        var data = Data()
        try packValue(value, into: &data)
        return data
    }

    private static func packValue(_ value: Any, into data: inout Data) throws {
        switch value {
        case let string as String:
            try packString(string, into: &data)
        case let bigInt as BigInt:
            try packBigInt(bigInt, into: &data)
        case let int as Int:
            packInt(int, into: &data)
        case let int64 as Int64:
            packInt64(int64, into: &data)
        case let uint64 as UInt64:
            packUInt64(uint64, into: &data)
        case let bool as Bool:
            data.append(bool ? 0xC3 : 0xC2)
        case let orderedDict as OrderedDictionary<String, Any>:
            try packOrderedMap(orderedDict, into: &data)
        case let dict as [String: Any]:
            try packMap(dict, into: &data)
        case let orderedArray as [OrderedDictionary<String, Any>]:
            try packOrderedDictArray(orderedArray, into: &data)
        case let array as [Any]:
            try packArray(array, into: &data)
        case is NSNull:
            data.append(0xC0)
        case nil as Any?:
            data.append(0xC0)
        default:
            throw HyperliquidError.invalidParameter("Unsupported type for MessagePack: \(type(of: value))")
        }
    }

    private static func packBigInt(_ value: BigInt, into data: inout Data) throws {
        // BigInt can be positive or negative
        if value >= 0 {
            // Positive BigInt - use unsigned encoding
            let bigUInt = BigUInt(value)
            packBigUInt(bigUInt, into: &data)
        } else {
            // Negative BigInt - need to fit in int64
            guard let int64Value = Int64(exactly: value) else {
                throw HyperliquidError.invalidParameter("BigInt value \(value) is too large for MessagePack int64")
            }
            packInt64(int64Value, into: &data)
        }
    }

    private static func packBigUInt(_ value: BigUInt, into data: inout Data) {
        if value < 128 {
            // positive fixint
            data.append(UInt8(value))
        } else if value < 256 {
            // uint 8
            data.append(0xCC)
            data.append(UInt8(value))
        } else if value < 65536 {
            // uint 16
            data.append(0xCD)
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8(value & 0xFF))
        } else if value < BigUInt(4_294_967_296) {
            // uint 32
            data.append(0xCE)
            data.append(UInt8((value >> 24) & 0xFF))
            data.append(UInt8((value >> 16) & 0xFF))
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8(value & 0xFF))
        } else {
            // uint 64
            data.append(0xCF)
            data.append(UInt8((value >> 56) & 0xFF))
            data.append(UInt8((value >> 48) & 0xFF))
            data.append(UInt8((value >> 40) & 0xFF))
            data.append(UInt8((value >> 32) & 0xFF))
            data.append(UInt8((value >> 24) & 0xFF))
            data.append(UInt8((value >> 16) & 0xFF))
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8(value & 0xFF))
        }
    }

    private static func packString(_ string: String, into data: inout Data) throws {
        let utf8 = Array(string.utf8)
        let length = utf8.count

        if length < 32 {
            // fixstr
            data.append(UInt8(0xA0 | length))
        } else if length < 256 {
            // str 8
            data.append(0xD9)
            data.append(UInt8(length))
        } else if length < 65536 {
            // str 16
            data.append(0xDA)
            data.append(UInt8((length >> 8) & 0xFF))
            data.append(UInt8(length & 0xFF))
        } else {
            // str 32
            data.append(0xDB)
            data.append(UInt8((length >> 24) & 0xFF))
            data.append(UInt8((length >> 16) & 0xFF))
            data.append(UInt8((length >> 8) & 0xFF))
            data.append(UInt8(length & 0xFF))
        }
        data.append(contentsOf: utf8)
    }

    private static func packInt(_ value: Int, into data: inout Data) {
        if value >= 0 {
            packUInt64(UInt64(value), into: &data)
        } else {
            packInt64(Int64(value), into: &data)
        }
    }

    private static func packInt64(_ value: Int64, into data: inout Data) {
        if value >= 0 {
            packUInt64(UInt64(value), into: &data)
        } else if value >= -32 {
            // negative fixint
            data.append(UInt8(bitPattern: Int8(value)))
        } else if value >= Int64(Int8.min) {
            // int 8
            data.append(0xD0)
            data.append(UInt8(bitPattern: Int8(value)))
        } else if value >= Int64(Int16.min) {
            // int 16
            data.append(0xD1)
            let v = Int16(value)
            data.append(UInt8((v >> 8) & 0xFF))
            data.append(UInt8(v & 0xFF))
        } else if value >= Int64(Int32.min) {
            // int 32
            data.append(0xD2)
            let v = Int32(value)
            data.append(UInt8((v >> 24) & 0xFF))
            data.append(UInt8((v >> 16) & 0xFF))
            data.append(UInt8((v >> 8) & 0xFF))
            data.append(UInt8(v & 0xFF))
        } else {
            // int 64
            data.append(0xD3)
            data.append(UInt8((value >> 56) & 0xFF))
            data.append(UInt8((value >> 48) & 0xFF))
            data.append(UInt8((value >> 40) & 0xFF))
            data.append(UInt8((value >> 32) & 0xFF))
            data.append(UInt8((value >> 24) & 0xFF))
            data.append(UInt8((value >> 16) & 0xFF))
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8(value & 0xFF))
        }
    }

    private static func packUInt64(_ value: UInt64, into data: inout Data) {
        if value < 128 {
            // positive fixint
            data.append(UInt8(value))
        } else if value < 256 {
            // uint 8
            data.append(0xCC)
            data.append(UInt8(value))
        } else if value < 65536 {
            // uint 16
            data.append(0xCD)
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8(value & 0xFF))
        } else if value < 4_294_967_296 {
            // uint 32
            data.append(0xCE)
            data.append(UInt8((value >> 24) & 0xFF))
            data.append(UInt8((value >> 16) & 0xFF))
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8(value & 0xFF))
        } else {
            // uint 64
            data.append(0xCF)
            data.append(UInt8((value >> 56) & 0xFF))
            data.append(UInt8((value >> 48) & 0xFF))
            data.append(UInt8((value >> 40) & 0xFF))
            data.append(UInt8((value >> 32) & 0xFF))
            data.append(UInt8((value >> 24) & 0xFF))
            data.append(UInt8((value >> 16) & 0xFF))
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8(value & 0xFF))
        }
    }

    private static func packOrderedMap(_ map: OrderedDictionary<String, Any>, into data: inout Data) throws {
        let count = map.count

        if count < 16 {
            // fixmap
            data.append(UInt8(0x80 | count))
        } else if count < 65536 {
            // map 16
            data.append(0xDE)
            data.append(UInt8((count >> 8) & 0xFF))
            data.append(UInt8(count & 0xFF))
        } else {
            // map 32
            data.append(0xDF)
            data.append(UInt8((count >> 24) & 0xFF))
            data.append(UInt8((count >> 16) & 0xFF))
            data.append(UInt8((count >> 8) & 0xFF))
            data.append(UInt8(count & 0xFF))
        }

        // Pack key-value pairs in order
        for (key, value) in map {
            try packString(key, into: &data)
            try packValue(value, into: &data)
        }
    }

    private static func packMap(_ map: [String: Any], into data: inout Data) throws {
        // Convert to OrderedDictionary with sorted keys for consistency
        let orderedMap = OrderedDictionary<String, Any>(
            uniqueKeys: map.keys.sorted(),
            values: map.keys.sorted().map { map[$0]! }
        )
        try packOrderedMap(orderedMap, into: &data)
    }

    private static func packOrderedDictArray(_ array: [OrderedDictionary<String, Any>], into data: inout Data) throws {
        let count = array.count

        if count < 16 {
            // fixarray
            data.append(UInt8(0x90 | count))
        } else if count < 65536 {
            // array 16
            data.append(0xDC)
            data.append(UInt8((count >> 8) & 0xFF))
            data.append(UInt8(count & 0xFF))
        } else {
            // array 32
            data.append(0xDD)
            data.append(UInt8((count >> 24) & 0xFF))
            data.append(UInt8((count >> 16) & 0xFF))
            data.append(UInt8((count >> 8) & 0xFF))
            data.append(UInt8(count & 0xFF))
        }

        for item in array {
            try packOrderedMap(item, into: &data)
        }
    }

    private static func packArray(_ array: [Any], into data: inout Data) throws {
        let count = array.count

        if count < 16 {
            // fixarray
            data.append(UInt8(0x90 | count))
        } else if count < 65536 {
            // array 16
            data.append(0xDC)
            data.append(UInt8((count >> 8) & 0xFF))
            data.append(UInt8(count & 0xFF))
        } else {
            // array 32
            data.append(0xDD)
            data.append(UInt8((count >> 24) & 0xFF))
            data.append(UInt8((count >> 16) & 0xFF))
            data.append(UInt8((count >> 8) & 0xFF))
            data.append(UInt8(count & 0xFF))
        }

        for item in array {
            try packValue(item, into: &data)
        }
    }
}
