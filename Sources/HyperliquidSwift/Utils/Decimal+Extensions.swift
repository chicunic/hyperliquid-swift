import BigInt
import Foundation

extension Decimal {
    /// Convert Decimal to wire format string
    /// Reference: Python signing.py:457-464 float_to_wire
    ///
    /// - Returns: String representation with up to 8 decimal places, trailing zeros removed
    /// - Throws: If rounding causes precision loss >= 1e-12
    public func toWireString() throws -> String {
        let rounded = roundToScale(8)
        try validatePrecision(rounded: rounded, threshold: -12)

        let result = (rounded as NSDecimalNumber).stringValue
        if result == "-0" || result == "-0.0" {
            return "0"
        }

        return trimTrailingZeros(result)
    }

    private func roundToScale(_ scale: Int16) -> Decimal {
        let handler = NSDecimalNumberHandler(
            roundingMode: .plain,
            scale: scale,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        return (self as NSDecimalNumber).rounding(accordingToBehavior: handler) as Decimal
    }

    private func validatePrecision(rounded: Decimal, threshold: Int) throws {
        let difference = abs(rounded - self)
        let maxDifference = Decimal(sign: .plus, exponent: threshold, significand: 1)
        if difference >= maxDifference {
            throw HyperliquidError.precisionLoss(value: self)
        }
    }

    private func trimTrailingZeros(_ value: String) -> String {
        var result = value
        guard result.contains(".") else { return result }

        while result.hasSuffix("0") {
            result.removeLast()
        }
        if result.hasSuffix(".") {
            result.removeLast()
        }
        return result
    }

    /// Convert Decimal to BigInt for hashing (multiply by 10^8)
    /// Reference: Python signing.py:467-468 float_to_int_for_hashing
    /// - Returns: BigInt value
    /// - Throws: HyperliquidError.precisionLoss if value has too many decimal places
    public func toIntForHashing() throws -> BigInt {
        try toInt(power: 8)
    }

    /// Convert Decimal to USD integer (multiply by 10^6)
    /// Reference: Python signing.py:471-472 float_to_usd_int
    /// - Returns: BigInt value
    /// - Throws: HyperliquidError.precisionLoss if value has too many decimal places
    public func toUSDInt() throws -> BigInt {
        try toInt(power: 6)
    }

    /// Convert Decimal to BigInt by multiplying by 10^power
    /// Reference: Python signing.py:475-478 float_to_int
    /// - Returns: BigInt value
    /// - Throws: HyperliquidError.precisionLoss if rounding causes precision loss
    public func toInt(power: Int) throws -> BigInt {
        let multiplier = Decimal(sign: .plus, exponent: power, significand: 1)
        let scaled = self * multiplier
        let rounded = scaled.roundToScale(0)

        let difference = abs(scaled - rounded)
        if difference >= Decimal(string: "0.001")! {
            throw HyperliquidError.precisionLoss(value: self)
        }

        return BigInt((rounded as NSDecimalNumber).stringValue)!
    }
}

extension Double {
    /// Convert Double to wire format string
    public func toWireString() throws -> String { try Decimal(self).toWireString() }

    /// Convert Double to BigInt for hashing
    public func toIntForHashing() throws -> BigInt { try Decimal(self).toIntForHashing() }

    /// Convert Double to USD integer
    public func toUSDInt() throws -> BigInt { try Decimal(self).toUSDInt() }
}
