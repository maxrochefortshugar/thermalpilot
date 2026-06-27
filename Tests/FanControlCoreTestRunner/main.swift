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

func testFakeSMCDelayedFtstReadback() throws {
    let smc = FakeSMC.mac165()
    let first = try smc.write(.unlock(value: 1), capability: .mac165ValidatedOneShot, reason: "test unlock")
    try expect(first.smcResult == 0, "Ftst write should be accepted")

    let immediate = try smc.read(try FanKey("Ftst"))
    try expect(immediate.bytes == [0], "first readback should still be delayed")

    smc.advanceTick()
    smc.advanceTick()
    smc.advanceTick()

    let settled = try smc.read(try FanKey("Ftst"))
    try expect(settled.bytes == [1], "readback should eventually become 1")
}

func testFakeSMCRejectsManualBeforeUnlockSettles() throws {
    let smc = FakeSMC.mac165()
    let result = try smc.write(.mode(fan: 0, value: 1), capability: .mac165ValidatedOneShot, reason: "manual too early")
    try expect(result.smcResult == 0x82, "manual mode should be rejected before unlock")
}

func testFakeSMCReleaseModeSettlesBackToManaged() throws {
    let smc = FakeSMC.mac165()

    let result = try smc.write(.mode(fan: 0, value: 0), capability: .mac165ValidatedOneShot, reason: "release fan")
    try expect(result.smcResult == 0, "release mode write should be accepted")

    smc.advanceTick()
    smc.advanceTick()

    let intermediate = try smc.read(try FanKey("F0Md"))
    try expect(intermediate.bytes == [0], "release should first read back as release mode")

    smc.advanceTick()
    smc.advanceTick()

    let settled = try smc.read(try FanKey("F0Md"))
    try expect(settled.bytes == [3], "release should settle back to managed mode")
}

func testFakeSMCPreManualTargetWriteDoesNotStickImmediately() throws {
    let smc = FakeSMC.mac165()
    let maxBytes = FanEncoding.float32LittleEndian(5_777)

    let result = try smc.write(.target(fan: 0, bytes: maxBytes), capability: .mac165ValidatedOneShot, reason: "target before manual")
    try expect(result.smcResult == 0, "pre-manual target write should be accepted")

    let readback = try smc.read(try FanKey("F0Tg"))
    try expect(readback.bytes != maxBytes, "pre-manual target write should not immediately stick")
}

func testFakeSMCPostManualTargetWriteSticks() throws {
    let smc = FakeSMC.mac165()
    let maxBytes = FanEncoding.float32LittleEndian(5_777)

    _ = try smc.write(.unlock(value: 1), capability: .mac165ValidatedOneShot, reason: "unlock")
    smc.advanceTick()
    smc.advanceTick()
    smc.advanceTick()
    _ = try smc.write(.mode(fan: 0, value: 1), capability: .mac165ValidatedOneShot, reason: "manual")
    smc.advanceTick()
    smc.advanceTick()

    let result = try smc.write(.target(fan: 0, bytes: maxBytes), capability: .mac165ValidatedOneShot, reason: "target after manual")
    try expect(result.smcResult == 0, "post-manual target write should be accepted")

    let readback = try smc.read(try FanKey("F0Tg"))
    try expect(readback.bytes == maxBytes, "post-manual target write should stick")

    smc.advanceTick()
    let actual = FanEncoding.floatValue(try smc.read(try FanKey("F0Ac")).bytes) ?? 0
    try expect(actual > 0, "post-manual target should drive ramp")
}

func testFakeSMCScriptedModeWriteRejection() throws {
    let smc = FakeSMC.mac165()
    smc.rejectWrite(operation: .mode(fan: 1, value: 1), key: "F1Md", smcResult: 0x84)

    let result = try smc.write(.mode(fan: 1, value: 1), capability: .mac165ValidatedOneShot, reason: "scripted rejection")

    try expect(result.smcResult == 0x84, "scripted F1Md=1 rejection should be returned")
    try expect(smc.writes.last?.key == "F1Md", "scripted rejection should still record the target key")
}

func testFakeSMCRawEntryBytesHelperMutatesAndReadsTargets() throws {
    let smc = FakeSMC.mac165()
    let fan0Target = FanEncoding.float32LittleEndian(2_222)
    let fan1Target = FanEncoding.float32LittleEndian(3_333)

    smc.setRawEntryBytes("F0Tg", fan0Target)
    smc.setRawEntryBytes("F1Tg", fan1Target)

    try expect(smc.rawEntryBytes("F0Tg") == fan0Target, "raw helper should read mutated F0Tg bytes")
    try expect(smc.rawEntryBytes("F1Tg") == fan1Target, "raw helper should read mutated F1Tg bytes")
    try expect(try smc.read(try FanKey("F0Tg")).bytes == fan0Target, "raw helper should mutate readable F0Tg entry")
    try expect(try smc.read(try FanKey("F1Tg")).bytes == fan1Target, "raw helper should mutate readable F1Tg entry")
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
    ("Resolver propagates unreadable Ftst", testResolverPropagatesUnreadableFtst),
    ("FakeSMC delayed Ftst readback", testFakeSMCDelayedFtstReadback),
    ("FakeSMC rejects early manual", testFakeSMCRejectsManualBeforeUnlockSettles),
    ("FakeSMC release mode settles back to managed", testFakeSMCReleaseModeSettlesBackToManaged),
    ("FakeSMC pre-manual target write does not stick immediately", testFakeSMCPreManualTargetWriteDoesNotStickImmediately),
    ("FakeSMC post-manual target write sticks", testFakeSMCPostManualTargetWriteSticks),
    ("FakeSMC scripted mode write rejection", testFakeSMCScriptedModeWriteRejection),
    ("FakeSMC raw entry bytes helper mutates and reads targets", testFakeSMCRawEntryBytesHelperMutatesAndReadsTargets)
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
