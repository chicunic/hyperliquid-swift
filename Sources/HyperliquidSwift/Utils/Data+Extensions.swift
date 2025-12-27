import CryptoSwift
import Foundation

// MARK: - Data Extensions

extension Data {
    /// Initialize Data from a hex string (with or without 0x prefix)
    public init?(hex: String) {
        let hexString = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard hexString.count % 2 == 0 else { return nil }

        var data = Data(capacity: hexString.count / 2)
        var index = hexString.startIndex

        while index < hexString.endIndex {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }

    /// Hex string with 0x prefix
    public var hexString: String {
        "0x" + map { String(format: "%02x", $0) }.joined()
    }

    /// Convert Data to a hex string without 0x prefix
    public var hexStringWithoutPrefix: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// Compute Keccak-256 hash
    public var keccak256: Data {
        Data(SHA3(variant: .keccak256).calculate(for: bytes))
    }

    /// Pad data to specified length (prepend zeros)
    public func leftPadded(to length: Int) -> Data {
        if count >= length {
            return self
        }
        return Data(repeating: 0, count: length - count) + self
    }

    /// Pad data to specified length (append zeros)
    public func rightPadded(to length: Int) -> Data {
        if count >= length {
            return self
        }
        return self + Data(repeating: 0, count: length - count)
    }
}

// MARK: - String Extensions

extension String {
    /// Convert Ethereum address string to 20-byte Data
    public func addressToBytes() -> Data? {
        let hex = hasPrefix("0x") ? String(dropFirst(2)) : self
        guard hex.count == 40 else { return nil }
        return Data(hex: hex)
    }

    /// Normalize Ethereum address to lowercase with 0x prefix
    public var normalizedAddress: String {
        let hex = hasPrefix("0x") ? String(dropFirst(2)) : self
        return "0x" + hex.lowercased()
    }
}
