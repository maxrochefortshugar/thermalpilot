import Foundation

public enum SMCKeyCodeError: Error, CustomStringConvertible {
    case invalidLength(String)
    case nonASCII(String)

    public var description: String {
        switch self {
        case .invalidLength(let value):
            return "SMC key must be exactly four characters: \(value)"
        case .nonASCII(let value):
            return "SMC key must contain ASCII characters only: \(value)"
        }
    }
}

public struct SMCKeyCode: Equatable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public init(_ stringValue: String) throws {
        guard stringValue.utf8.count == 4 else {
            throw SMCKeyCodeError.invalidLength(stringValue)
        }

        var value: UInt32 = 0
        for byte in stringValue.utf8 {
            guard byte <= 0x7F else {
                throw SMCKeyCodeError.nonASCII(stringValue)
            }
            value = (value << 8) | UInt32(byte)
        }

        rawValue = value
    }

    public var stringValue: String {
        let bytes: [UInt8] = [
            UInt8((rawValue >> 24) & 0xFF),
            UInt8((rawValue >> 16) & 0xFF),
            UInt8((rawValue >> 8) & 0xFF),
            UInt8(rawValue & 0xFF)
        ]

        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
}

public struct SMCDecodedValue: Equatable, Sendable {
    public let type: String
    public let size: UInt32
    public let bytes: [UInt8]
    public let numericValue: Double?
    public let displayValue: String
}

public enum SMCValueDecoder {
    public static func decode(type: String, bytes: [UInt8], size: UInt32) -> SMCDecodedValue {
        let valueBytes = Array(bytes.prefix(Int(size)))
        let normalizedType = type.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedType == "fpe2", valueBytes.count >= 2 {
            let raw = UInt16(valueBytes[0]) << 8 | UInt16(valueBytes[1])
            let value = Double(raw) / 4.0
            return decoded(type: type, size: size, bytes: valueBytes, value: value, suffix: " rpm")
        }

        if normalizedType == "sp78", valueBytes.count >= 2 {
            let integer = Int8(bitPattern: valueBytes[0])
            let fraction = Double(valueBytes[1]) / 256.0
            let value = Double(integer) + fraction
            return decoded(type: type, size: size, bytes: valueBytes, value: value, suffix: " C")
        }

        if normalizedType == "ui8", valueBytes.count >= 1 {
            let value = Double(valueBytes[0])
            return decoded(type: type, size: size, bytes: valueBytes, value: value, suffix: "")
        }

        if normalizedType == "ui16", valueBytes.count >= 2 {
            let raw = UInt16(valueBytes[0]) << 8 | UInt16(valueBytes[1])
            return decoded(type: type, size: size, bytes: valueBytes, value: Double(raw), suffix: "")
        }

        if normalizedType == "ui32", valueBytes.count >= 4 {
            let raw = UInt32(valueBytes[0]) << 24
                | UInt32(valueBytes[1]) << 16
                | UInt32(valueBytes[2]) << 8
                | UInt32(valueBytes[3])
            return decoded(type: type, size: size, bytes: valueBytes, value: Double(raw), suffix: "")
        }

        if type == "flt ", valueBytes.count >= 4 {
            let raw = UInt32(valueBytes[0])
                | UInt32(valueBytes[1]) << 8
                | UInt32(valueBytes[2]) << 16
                | UInt32(valueBytes[3]) << 24
            let value = Double(Float(bitPattern: raw))
            guard value.isFinite else {
                return rawDecoded(type: type, size: size, bytes: valueBytes)
            }
            return decoded(type: type, size: size, bytes: valueBytes, value: value, suffix: "")
        }

        return rawDecoded(type: type, size: size, bytes: valueBytes)
    }

    private static func decoded(
        type: String,
        size: UInt32,
        bytes: [UInt8],
        value: Double,
        suffix: String
    ) -> SMCDecodedValue {
        SMCDecodedValue(
            type: type,
            size: size,
            bytes: bytes,
            numericValue: value,
            displayValue: "\(format(value))\(suffix)"
        )
    }

    private static func format(_ value: Double) -> String {
        if abs(value) >= 1_000_000 || (abs(value) < 0.01 && value != 0) {
            return String(format: "%.3g", value)
        }

        let rounded = value.rounded()
        if rounded >= Double(Int64.min),
           rounded <= Double(Int64.max),
           abs(value - rounded) < 0.0005 {
            return "\(Int64(rounded))"
        }

        var text = String(format: "%.2f", value)
        while text.contains(".") && text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text
    }

    private static func rawDecoded(type: String, size: UInt32, bytes: [UInt8]) -> SMCDecodedValue {
        SMCDecodedValue(
            type: type,
            size: size,
            bytes: bytes,
            numericValue: nil,
            displayValue: hexString(bytes)
        )
    }

    private static func hexString(_ bytes: [UInt8]) -> String {
        if bytes.isEmpty {
            return "unavailable"
        }

        return "0x" + bytes.map { String(format: "%02X", $0) }.joined()
    }
}
