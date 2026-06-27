import FanControlCore
import Foundation

func testCoreBoundary() throws {
    let key = try FanKey("F0Tg")
    try expect(key.stringValue == "F0Tg", "FanKey should preserve four-character keys")
}

let tests: [(String, () throws -> Void)] = [
    ("Core boundary", testCoreBoundary)
]

var failures = 0
for (name, test) in tests {
    do {
        try test()
        print("PASS \(name)")
    } catch {
        failures += 1
        print("FAIL \(name): \(error)")
    }
}

if failures == 0 {
    print("PASS \(tests.count)/\(tests.count) tests")
} else {
    print("FAIL \(failures)/\(tests.count) tests")
    exit(1)
}
