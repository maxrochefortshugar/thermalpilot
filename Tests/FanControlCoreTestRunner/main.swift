import FanControlCore
import Foundation

func testCoreBoundary() throws {
    let key = try FanKey("F0Tg")
    try expect(key.stringValue == "F0Tg", "FanKey should preserve four-character keys")
}

func testMac165Capability() throws {
    let capability = FanCapability.mac165ValidatedOneShot
    let mode0 = try capability.modeKey(for: 0)
    let target1 = try capability.targetKey(for: 1)

    try expect(capability.model == "Mac16,5", "model should match local validation")
    try expect(capability.platform == "j616c", "platform should match local validation")
    try expect(capability.fanCount == 2, "fan count should match local validation")
    try expect(mode0.stringValue == "F0Md", "M4 mode key should use uppercase Md")
    try expect(target1.stringValue == "F1Tg", "target key should format fan index")
    try expect(capability.validation.activeControlEnabled == false, "active control should remain disabled")
    try expect(FanEncoding.float32LittleEndian(5777) == [0x00, 0x88, 0xB4, 0x45], "max RPM bytes should match hardware log")
}

func testResolverSucceedsForValidatedMac165Inventory() throws {
    let resolver = try FanCapabilityResolver(hardware: fakeFanInventory(), hostModel: { "Mac16,5" })

    let capability = try resolver.resolve()

    try expect(capability.model == "Mac16,5", "resolver should return Mac16,5 capability")
    try expect(capability.platform == "j616c", "resolver should return validated platform")
    try expect(capability.fanCount == 2, "resolver should preserve fan count")
    try expect(capability.modeKeyFormat == "F%dMd", "resolver should preserve uppercase mode key")
    try expect(capability.unlockAvailable, "resolver should require Ftst for validated capability")
}

func testResolverRejectsWrongModel() throws {
    let resolver = try FanCapabilityResolver(hardware: fakeFanInventory(), hostModel: { "Mac99,9" })

    try expectThrows("wrong model should be unsupported", {
        _ = try resolver.resolve()
    }, matching: { error in
        error as? FanControlError == .unsupportedModel(model: "Mac99,9", platform: "j616c")
    })
}

func testResolverRejectsWrongPlatform() throws {
    let reader = try fakeFanInventory(overrides: ["RPlt": fakePlatformReading("j999x")])
    let resolver = FanCapabilityResolver(hardware: reader, hostModel: { "Mac16,5" })

    try expectThrows("wrong platform should be unsupported", {
        _ = try resolver.resolve()
    }, matching: { error in
        error as? FanControlError == .unsupportedModel(model: "Mac16,5", platform: "j999x")
    })
}

func testResolverRejectsFanCountMismatch() throws {
    let reader = try fakeFanInventory(overrides: ["FNum": fakeReading("FNum", bytes: [1])])
    let resolver = FanCapabilityResolver(hardware: reader, hostModel: { "Mac16,5" })

    try expectThrows("fan count mismatch should be unsafe", {
        _ = try resolver.resolve()
    }, matching: { error in
        guard case .unsafeState(let message) = error as? FanControlError else { return false }
        return message == "fan count mismatch: expected 2, got 1"
    })
}

func testResolverPropagatesMissingPerFanInventoryKey() throws {
    let reader = try fakeFanInventory(failures: ["F1Mx": FanControlError.missingKey("F1Mx")])
    let resolver = FanCapabilityResolver(hardware: reader, hostModel: { "Mac16,5" })

    try expectThrows("missing per-fan inventory key should propagate", {
        _ = try resolver.resolve()
    }, matching: { error in
        error as? FanControlError == .missingKey("F1Mx")
    })
}

func testResolverRejectsLowercaseModePathWhenPresent() throws {
    let reader = try fakeFanInventory(overrides: ["F0md": fakeReading("F0md", bytes: [3])])
    let resolver = FanCapabilityResolver(hardware: reader, hostModel: { "Mac16,5" })

    try expectThrows("lowercase mode path should be unsupported", {
        _ = try resolver.resolve()
    }, matching: { error in
        error as? FanControlError == .unsupportedModel(model: "Mac16,5", platform: "lowercase mode key path not validated")
    })
}

func testResolverPropagatesMissingUppercaseModeKey() throws {
    let reader = try fakeFanInventory(failures: ["F0Md": FanControlError.missingKey("F0Md")])
    let resolver = FanCapabilityResolver(hardware: reader, hostModel: { "Mac16,5" })

    try expectThrows("missing uppercase mode key should propagate", {
        _ = try resolver.resolve()
    }, matching: { error in
        error as? FanControlError == .missingKey("F0Md")
    })
}

func testResolverPropagatesMissingFtst() throws {
    let reader = try fakeFanInventory(failures: ["Ftst": FanControlError.missingKey("Ftst")])
    let resolver = FanCapabilityResolver(hardware: reader, hostModel: { "Mac16,5" })

    try expectThrows("missing Ftst should propagate", {
        _ = try resolver.resolve()
    }, matching: { error in
        error as? FanControlError == .missingKey("Ftst")
    })
}

func testResolverPropagatesUnreadableFtst() throws {
    let reader = try fakeFanInventory(failures: ["Ftst": FakeFanReadError.unreadable("Ftst")])
    let resolver = FanCapabilityResolver(hardware: reader, hostModel: { "Mac16,5" })

    try expectThrows("unreadable Ftst should propagate", {
        _ = try resolver.resolve()
    }, matching: { error in
        error as? FakeFanReadError == .unreadable("Ftst")
    })
}

let tests: [(String, () throws -> Void)] = [
    ("Core boundary", testCoreBoundary),
    ("Mac16,5 capability", testMac165Capability),
    ("Resolver succeeds for validated Mac16,5 inventory", testResolverSucceedsForValidatedMac165Inventory),
    ("Resolver rejects wrong model", testResolverRejectsWrongModel),
    ("Resolver rejects wrong platform", testResolverRejectsWrongPlatform),
    ("Resolver rejects fan count mismatch", testResolverRejectsFanCountMismatch),
    ("Resolver propagates missing per-fan inventory key", testResolverPropagatesMissingPerFanInventoryKey),
    ("Resolver rejects lowercase mode path when present", testResolverRejectsLowercaseModePathWhenPresent),
    ("Resolver propagates missing uppercase mode key", testResolverPropagatesMissingUppercaseModeKey),
    ("Resolver propagates missing Ftst", testResolverPropagatesMissingFtst),
    ("Resolver propagates unreadable Ftst", testResolverPropagatesUnreadableFtst)
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
