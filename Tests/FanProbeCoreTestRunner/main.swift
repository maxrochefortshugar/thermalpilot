import FanProbeCore
import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure(description: message)
    }
}

func expectClose(_ actual: Double?, _ expected: Double, _ message: String) throws {
    guard let actual else {
        throw TestFailure(description: "\(message): value was nil")
    }

    if abs(actual - expected) >= 0.001 {
        throw TestFailure(description: "\(message): expected \(expected), got \(actual)")
    }
}

func testFourCCRoundTripsPrintableKey() throws {
    let key = try SMCKeyCode("F0Ac")

    try expect(key.stringValue == "F0Ac", "FourCC should round-trip printable key")
}

func testFpe2DecodesFanRpmFixedPointValue() throws {
    let decoded = SMCValueDecoder.decode(type: "fpe2", bytes: [0x38, 0x00], size: 2)

    try expectClose(decoded.numericValue, 3584.0, "fpe2 should decode RPM")
    try expect(decoded.displayValue == "3584 rpm", "fpe2 should display RPM")
}

func testSp78DecodesSignedTemperatureValue() throws {
    let decoded = SMCValueDecoder.decode(type: "sp78", bytes: [0x2A, 0x80], size: 2)

    try expectClose(decoded.numericValue, 42.5, "sp78 should decode Celsius")
    try expect(decoded.displayValue == "42.5 C", "sp78 should display Celsius")
}

func testUnsignedIntegersDecodeBigEndianValues() throws {
    let decoded = SMCValueDecoder.decode(type: "ui16", bytes: [0x01, 0x2C], size: 2)

    try expectClose(decoded.numericValue, 300.0, "ui16 should decode big-endian value")
    try expect(decoded.displayValue == "300", "ui16 should display integer")
}

func testFloatDecodesIeeeSinglePrecision() throws {
    let decoded = SMCValueDecoder.decode(type: "flt ", bytes: [0x00, 0x00, 0x48, 0x42], size: 4)

    try expectClose(decoded.numericValue, 50.0, "flt should decode little-endian IEEE single-precision value")
    try expect(decoded.displayValue == "50", "flt should display compact number")
}

func testNonFiniteFloatFallsBackToRawHex() throws {
    let decoded = SMCValueDecoder.decode(type: "flt ", bytes: [0x00, 0x00, 0x80, 0xFF], size: 4)

    try expect(decoded.numericValue == nil, "non-finite flt should not expose a numeric value")
    try expect(decoded.displayValue == "0x000080FF", "non-finite flt should display raw bytes")
}

func testAppleSiliconFanFloatDecodesLittleEndian() throws {
    let decoded = SMCValueDecoder.decode(type: "flt ", bytes: [0x00, 0xC0, 0xA8, 0x44], size: 4)

    try expectClose(decoded.numericValue, 1350.0, "Apple Silicon fan float should decode little-endian")
    try expect(decoded.displayValue == "1350", "Apple Silicon fan float should display RPM-like value")
}

let tests: [(String, () throws -> Void)] = [
    ("FourCC round-trip", testFourCCRoundTripsPrintableKey),
    ("fpe2 RPM decode", testFpe2DecodesFanRpmFixedPointValue),
    ("sp78 temperature decode", testSp78DecodesSignedTemperatureValue),
    ("unsigned integer decode", testUnsignedIntegersDecodeBigEndianValues),
    ("float decode", testFloatDecodesIeeeSinglePrecision),
    ("non-finite float fallback", testNonFiniteFloatFallsBackToRawHex),
    ("Apple Silicon fan float decode", testAppleSiliconFanFloatDecodesLittleEndian)
]

var passed = 0

for (name, test) in tests {
    do {
        try test()
        passed += 1
        print("PASS \(name)")
    } catch {
        print("FAIL \(name): \(error)")
        exit(1)
    }
}

print("PASS \(passed)/\(tests.count) tests")
