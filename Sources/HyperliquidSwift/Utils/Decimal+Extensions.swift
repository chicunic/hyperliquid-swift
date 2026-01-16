import BigInt
import Foundation

extension Decimal {
    /// Convert Decimal to wire format string
    /// Reference: Python signing.py:457-464 float_to_wire
    ///
    /// - Returns: String representation with up to 8 decimal places, trailing zeros removed
    /// - Throws: If rounding causes precision loss >= 1e-12
    public func toWireString() throws -> String {
        // Round to 8 decimal places
        let behavior = NSDecimalNumberHandler(
            roundingMode: .plain,
            scale: 8,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )

        let nsDecimal = self as NSDecimalNumber
        let rounded = nsDecimal.rounding(accordingToBehavior: behavior)

        // Check precision loss
        let difference = abs((rounded as Decimal) - self)
        let threshold = Decimal(sign: .plus, exponent: -12, significand: 1)  // 1e-12

        if difference >= threshold {
            throw HyperliquidError.precisionLoss(value: self)
        }

        // Convert to string and normalize
        var result = rounded.stringValue

        // Handle "-0" case
        if result == "-0" || result == "-0.0" {
            return "0"
        }

        // Remove trailing zeros after decimal point
        if result.contains(".") {
            // Remove trailing zeros
            while result.hasSuffix("0") {
                result.removeLast()
            }
            // Remove trailing decimal point
            if result.hasSuffix(".") {
                result.removeLast()
            }
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
        let withDecimals = self * multiplier

        // Round to integer
        let handler = NSDecimalNumberHandler(
            roundingMode: .plain,
            scale: 0,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        let rounded = NSDecimalNumber(decimal: withDecimals).rounding(accordingToBehavior: handler)
        let roundedDecimal = rounded as Decimal

        // Check precision loss
        let difference = abs(withDecimals - roundedDecimal)
        let threshold = Decimal(string: "0.001")!  // 1e-3

        if difference >= threshold {
            throw HyperliquidError.precisionLoss(value: self)
        }

        return BigInt(rounded.stringValue)!
    }
}

extension Double {
    /// Convert Double to wire format string
    public func toWireString() throws -> String {
        try Decimal(self).toWireString()
    }

    /// Convert Double to BigInt for hashing
    public func toIntForHashing() throws -> BigInt {
        try Decimal(self).toIntForHashing()
    }

    /// Convert Double to USD integer
    public func toUSDInt() throws -> BigInt {
        try Decimal(self).toUSDInt()
    }
}
