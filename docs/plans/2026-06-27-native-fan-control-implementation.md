# Native Fan Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native, opt-in fan-control implementation that can eventually boost Apple Silicon fans before MLX workloads, verify the ramp, and restore macOS managed control without exposing arbitrary SMC writes.

**Architecture:** Keep `mlx-chill` permanently read-only. Build active fan control behind a separate `mlx-chill-control` executable, a typed fan-only hardware interface, a fake-SMC test backend, audit logging, and a lease/watchdog state machine. The controller remains execution-gated until crash recovery and sleep/wake recovery are validated.

**Tech Stack:** Swift 6, Swift Package Manager executable test runners, IOKit, JSON/JSONL persistence, `Process` for workload wrapping, and no runtime dependency on ThermalForge, MTPLX, TG Pro, or Macs Fan Control.

---

## Review Fixes Incorporated

This plan incorporates adversarial review findings:

- `mlx-chill` never imports or links the active fan-control stack.
- `mlx-chill-control` is mandatory, not a fallback.
- No public arbitrary SMC write API exists.
- Writes are available only as typed fan operations derived from a resolved capability.
- Capability resolution reads host model and SMC platform before active work.
- Active execution remains disabled until crash and sleep/wake recovery are verified.
- A lease containing raw pre-boost mode/target bytes is created before the first write.
- Any boost failure after lease creation attempts restore.
- Restore uses the lease snapshot, not current boosted state.
- Every write has audit logging: key, old raw bytes, new raw bytes, result, reason, service, capability, lease id.
- The watchdog includes heartbeat, expiry, signal handling, parent death, stale lease recovery, and sleep/wake validation gates.

## Source Spec

Implement against `docs/specs/2026-06-27-native-fan-control.md`.

The hardware-validated `Mac16,5` sequence is:

1. Read and snapshot fan state.
2. Create lease marker containing raw pre-boost mode/target bytes before writing.
3. Write `Ftst = 1`; poll until readback is `1`.
4. Request `F{n}Tg = F{n}Mx` while not manual.
5. Require targets to settle to at least `0.95 * F{n}Mn`.
6. Retry `F{n}Md = 1` until write succeeds and readback is `1`.
7. After manual readback, write `F{n}Tg = F{n}Mx`; poll until target readback matches max.
8. Verify actual RPM reaches `0.85 * maxRPM`.
9. Restore by keeping target high, writing release command `0`, polling `Ftst = 0`, waiting for non-manual mode, then clearing/restoring captured targets.

## File Structure

Create:

- `Sources/FanControlCore/FanControlTypes.swift`
  Core public value types, errors, explicit public initializers, status results, audit events, and operation results.

- `Sources/FanControlCore/FanCapability.swift`
  Capability model, mode-key strategy, validation flags, lease defaults, and capability fingerprint.

- `Sources/FanControlCore/FanCapabilityResolver.swift`
  Resolves the running model/platform, probes lowercase/uppercase mode keys, detects optional `Ftst`, and refuses unsupported hardware.

- `Sources/FanControlCore/FanHardware.swift`
  Typed hardware protocol. It exposes fan-only read/write operations, not arbitrary SMC writes.

- `Sources/FanControlCore/FanLease.swift`
  Lease persistence with owner PID, parent PID, heartbeat, phase, capability fingerprint, and captured pre-boost fan bytes.

- `Sources/FanControlCore/FanControlLogger.swift`
  JSONL audit logger for every attempted write and restore decision.

- `Sources/FanControlCore/FanController.swift`
  `status()`, `boostMax(lease:)`, `restoreAuto(reason:)`, and stale lease recovery state machine.

- `Sources/FanControlCore/FanControlCommand.swift`
  Parser shared by the active executable. It has no dependency on IOKit or raw writes.

- `Sources/SMCControlTransport/SMCControlTransport.swift`
  Real IOKit implementation of the typed `FanHardware` protocol. Raw write helpers are private.

- `Sources/mlx-chill-control/main.swift`
  Separate active-control executable. This is the only binary that links the write-capable transport.

- `Tests/FanControlCoreTestRunner/main.swift`
- `Tests/FanControlCoreTestRunner/TestSupport.swift`
- `Tests/FanControlCoreTestRunner/FakeSMC.swift`

Modify:

- `Package.swift`
  Add `FanControlCore`, `SMCControlTransport`, `mlx-chill-control`, and `FanControlCoreTestRunner`.

- `README.md`
  Document that `mlx-chill` is read-only and `mlx-chill-control` is experimental/gated.

Do not modify:

- `Sources/CSMC/CSMC.c`
- `Sources/CSMC/include/CSMC.h`
- `Sources/FanProbeCore/SMCClient.swift`
- `Sources/mlx-chill/main.swift`, except for comments/docs if needed. It must not import `FanControlCore`.

---

## Task 1: Package Boundaries

**Files:**
- Modify: `Package.swift`
- Create: `Sources/FanControlCore/FanControlTypes.swift`
- Create: `Sources/FanControlCore/FanCapability.swift`
- Create: `Sources/FanControlCore/FanHardware.swift`
- Create: `Sources/SMCControlTransport/SMCControlTransport.swift`
- Create: `Sources/mlx-chill-control/main.swift`
- Create: `Tests/FanControlCoreTestRunner/main.swift`
- Create: `Tests/FanControlCoreTestRunner/TestSupport.swift`

- [ ] **Step 1: Add failing boundary test**

Create `Tests/FanControlCoreTestRunner/TestSupport.swift`:

```swift
import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() {
        throw TestFailure(description: message)
    }
}

func repoRootFromThisFile() -> URL {
    var url = URL(fileURLWithPath: #filePath)
    while url.lastPathComponent != "mlx-chill" && url.path != "/" {
        url.deleteLastPathComponent()
    }
    return url
}
```

Create `Tests/FanControlCoreTestRunner/main.swift`:

```swift
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
```

- [ ] **Step 2: Verify the expected failure**

Run:

```sh
swift run FanControlCoreTestRunner
```

Expected:

```text
error: no executable product named 'FanControlCoreTestRunner'
```

- [ ] **Step 3: Add package targets**

Modify `Package.swift`:

```swift
products: [
    .executable(name: "mlx-chill", targets: ["mlx-chill"]),
    .executable(name: "mlx-chill-control", targets: ["mlx-chill-control"]),
    .library(name: "FanProbeCore", targets: ["FanProbeCore"])
],
targets: [
    .target(
        name: "CSMC",
        linkerSettings: [
            .linkedFramework("CoreFoundation"),
            .linkedFramework("IOKit")
        ]
    ),
    .target(
        name: "FanProbeCore",
        dependencies: ["CSMC"]
    ),
    .target(
        name: "FanControlCore"
    ),
    .target(
        name: "SMCControlTransport",
        dependencies: ["FanControlCore"],
        linkerSettings: [
            .linkedFramework("IOKit")
        ]
    ),
    .executableTarget(
        name: "mlx-chill",
        dependencies: ["FanProbeCore"]
    ),
    .executableTarget(
        name: "mlx-chill-control",
        dependencies: ["FanControlCore", "SMCControlTransport"]
    ),
    .executableTarget(
        name: "FanProbeCoreTestRunner",
        dependencies: ["FanProbeCore"],
        path: "Tests/FanProbeCoreTestRunner"
    ),
    .executableTarget(
        name: "FanControlCoreTestRunner",
        dependencies: ["FanControlCore"],
        path: "Tests/FanControlCoreTestRunner"
    )
]
```

Important: `mlx-chill` depends only on `FanProbeCore`.

- [ ] **Step 4: Add core types with public initializers**

Create `Sources/FanControlCore/FanControlTypes.swift`:

```swift
import Foundation

public enum FanControlError: Error, CustomStringConvertible, Equatable {
    case invalidKey(String)
    case unsupportedModel(model: String, platform: String)
    case activeControlDisabled(model: String)
    case missingKey(String)
    case invalidReading(key: String, reason: String)
    case unsafeState(String)
    case writeRejected(key: String, smcResult: UInt8)
    case timeout(String)
    case restoreFailed(String)
    case leaseRequired(String)

    public var description: String {
        switch self {
        case .invalidKey(let key): return "invalid SMC key: \(key)"
        case .unsupportedModel(let model, let platform): return "unsupported model/platform: \(model) / \(platform)"
        case .activeControlDisabled(let model): return "active fan control is disabled for \(model)"
        case .missingKey(let key): return "missing required key: \(key)"
        case .invalidReading(let key, let reason): return "invalid reading for \(key): \(reason)"
        case .unsafeState(let message): return "unsafe fan-control state: \(message)"
        case .writeRejected(let key, let smcResult): return "write rejected for \(key): 0x\(String(format: "%02X", smcResult))"
        case .timeout(let message): return "timeout: \(message)"
        case .restoreFailed(let message): return "restore failed: \(message)"
        case .leaseRequired(let message): return "lease required: \(message)"
        }
    }
}

public struct FanKey: Equatable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public init(_ stringValue: String) throws {
        guard stringValue.utf8.count == 4 else {
            throw FanControlError.invalidKey(stringValue)
        }
        var value: UInt32 = 0
        for byte in stringValue.utf8 {
            guard byte <= 0x7F else {
                throw FanControlError.invalidKey(stringValue)
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

public struct FanReading: Equatable, Sendable {
    public let key: FanKey
    public let type: String
    public let size: UInt32
    public let attributes: UInt8
    public let bytes: [UInt8]

    public init(key: FanKey, type: String, size: UInt32, attributes: UInt8, bytes: [UInt8]) {
        self.key = key
        self.type = type
        self.size = size
        self.attributes = attributes
        self.bytes = bytes
    }
}

public struct FanWriteResult: Equatable, Sendable {
    public let kernReturn: Int32
    public let smcResult: UInt8
    public let smcStatus: UInt8

    public init(kernReturn: Int32, smcResult: UInt8, smcStatus: UInt8) {
        self.kernReturn = kernReturn
        self.smcResult = smcResult
        self.smcStatus = smcStatus
    }
}

public enum FanEncoding {
    public static func float32LittleEndian(_ value: Float) -> [UInt8] {
        var raw = value.bitPattern.littleEndian
        return withUnsafeBytes(of: &raw) { Array($0) }
    }

    public static func floatValue(_ bytes: [UInt8]) -> Float? {
        guard bytes.count >= 4 else { return nil }
        let raw = UInt32(bytes[0])
            | UInt32(bytes[1]) << 8
            | UInt32(bytes[2]) << 16
            | UInt32(bytes[3]) << 24
        let value = Float(bitPattern: raw)
        return value.isFinite ? value : nil
    }
}
```

- [ ] **Step 5: Add placeholder capability type**

Create `Sources/FanControlCore/FanCapability.swift`:

```swift
import Foundation

public struct FanCapability: Equatable, Sendable {
    public let model: String

    public init(model: String) {
        self.model = model
    }
}
```

Task 2 replaces this placeholder with the full allowlisted capability model before any controller logic exists.

- [ ] **Step 6: Add package-scoped typed hardware protocol**

Create `Sources/FanControlCore/FanHardware.swift`:

```swift
import Foundation

package enum FanWriteOperation: Equatable, Sendable {
    case unlock(value: UInt8)
    case mode(fan: Int, value: UInt8)
    case target(fan: Int, bytes: [UInt8])
}

public protocol FanReader {
    var serviceName: String { get }
    func read(_ key: FanKey) throws -> FanReading
}

package protocol FanHardware: FanReader {
    func write(_ operation: FanWriteOperation, capability: FanCapability, reason: String) throws -> FanWriteResult
}
```

This protocol is package-scoped and fan-specific. There is no public `write(key:bytes:)` method and no public fan-target raw-byte write surface.

- [ ] **Step 7: Add transport target marker**

Create `Sources/SMCControlTransport/SMCControlTransport.swift`:

```swift
import FanControlCore
import Foundation

public enum SMCControlTransportModule {
    public static let name = "SMCControlTransport"
}
```

- [ ] **Step 8: Add active executable shell**

Create `Sources/mlx-chill-control/main.swift`:

```swift
import Foundation

print("mlx-chill-control is experimental and not enabled yet")
```

- [ ] **Step 9: Run tests and boundary check**

Run:

```sh
swift run FanControlCoreTestRunner
swift run FanProbeCoreTestRunner
swift build -c release
nm -m .build/release/mlx-chill | rg 'SMCControlTransport|FanController|writeBytes' && exit 1 || echo 'mlx-chill read-only boundary clean'
```

Expected:

```text
PASS Core boundary
PASS 1/1 tests
PASS 7/7 tests
Build complete!
mlx-chill read-only boundary clean
```

- [ ] **Step 10: Commit**

```sh
git add Package.swift Sources/FanControlCore Sources/SMCControlTransport Sources/mlx-chill-control Tests/FanControlCoreTestRunner
git commit -m "Add active fan-control package boundary"
```

---

## Task 2: Capability Resolution

**Files:**
- Create: `Sources/FanControlCore/FanCapability.swift`
- Create: `Sources/FanControlCore/FanCapabilityResolver.swift`
- Modify: `Tests/FanControlCoreTestRunner/main.swift`

- [ ] **Step 1: Add capability tests**

Add to `main.swift`:

```swift
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
```

Add:

```swift
("Mac16,5 capability", testMac165Capability)
```

- [ ] **Step 2: Verify failure**

Run:

```sh
swift run FanControlCoreTestRunner
```

Expected:

```text
error: type 'FanCapability' has no member 'mac165ValidatedOneShot'
```

- [ ] **Step 3: Implement capability**

Replace `Sources/FanControlCore/FanCapability.swift`:

```swift
import Foundation

public struct FanValidationState: Equatable, Sendable {
    public let read: Bool
    public let boostMaxOneShot: Bool
    public let restoreAutoOneShot: Bool
    public let targetClearAfterNonManual: Bool
    public let crashRecovery: Bool
    public let parentDeathRecovery: Bool
    public let missedHeartbeatRecovery: Bool
    public let leaseExpiryRecovery: Bool
    public let signalRecovery: Bool
    public let sleepWakeRecovery: Bool

    public init(read: Bool, boostMaxOneShot: Bool, restoreAutoOneShot: Bool, targetClearAfterNonManual: Bool, crashRecovery: Bool, parentDeathRecovery: Bool, missedHeartbeatRecovery: Bool, leaseExpiryRecovery: Bool, signalRecovery: Bool, sleepWakeRecovery: Bool) {
        self.read = read
        self.boostMaxOneShot = boostMaxOneShot
        self.restoreAutoOneShot = restoreAutoOneShot
        self.targetClearAfterNonManual = targetClearAfterNonManual
        self.crashRecovery = crashRecovery
        self.parentDeathRecovery = parentDeathRecovery
        self.missedHeartbeatRecovery = missedHeartbeatRecovery
        self.leaseExpiryRecovery = leaseExpiryRecovery
        self.signalRecovery = signalRecovery
        self.sleepWakeRecovery = sleepWakeRecovery
    }

    public var activeControlEnabled: Bool {
        read
            && boostMaxOneShot
            && restoreAutoOneShot
            && targetClearAfterNonManual
            && crashRecovery
            && parentDeathRecovery
            && missedHeartbeatRecovery
            && leaseExpiryRecovery
            && signalRecovery
            && sleepWakeRecovery
    }
}

public struct FanCapability: Equatable, Sendable {
    public let model: String
    public let platform: String
    public let fanCount: Int
    public let modeKeyFormat: String
    public let unlockAvailable: Bool
    public let manualCommand: UInt8
    public let releaseCommand: UInt8
    public let managedObservedState: UInt8
    public let unlockOn: UInt8
    public let unlockOff: UInt8
    public let maxRPMCeiling: Float
    public let preManualMinimumMultiplier: Float
    public let boostVerificationMultiplier: Float
    public let defaultLeaseSeconds: Int
    public let maxLeaseSeconds: Int
    public let heartbeatSeconds: Int
    public let missedHeartbeatRestoreSeconds: Int
    public let validation: FanValidationState

    public init(model: String, platform: String, fanCount: Int, modeKeyFormat: String, unlockAvailable: Bool, manualCommand: UInt8, releaseCommand: UInt8, managedObservedState: UInt8, unlockOn: UInt8, unlockOff: UInt8, maxRPMCeiling: Float, preManualMinimumMultiplier: Float, boostVerificationMultiplier: Float, defaultLeaseSeconds: Int, maxLeaseSeconds: Int, heartbeatSeconds: Int, missedHeartbeatRestoreSeconds: Int, validation: FanValidationState) {
        self.model = model
        self.platform = platform
        self.fanCount = fanCount
        self.modeKeyFormat = modeKeyFormat
        self.unlockAvailable = unlockAvailable
        self.manualCommand = manualCommand
        self.releaseCommand = releaseCommand
        self.managedObservedState = managedObservedState
        self.unlockOn = unlockOn
        self.unlockOff = unlockOff
        self.maxRPMCeiling = maxRPMCeiling
        self.preManualMinimumMultiplier = preManualMinimumMultiplier
        self.boostVerificationMultiplier = boostVerificationMultiplier
        self.defaultLeaseSeconds = defaultLeaseSeconds
        self.maxLeaseSeconds = maxLeaseSeconds
        self.heartbeatSeconds = heartbeatSeconds
        self.missedHeartbeatRestoreSeconds = missedHeartbeatRestoreSeconds
        self.validation = validation
    }

    public var fingerprint: String {
        "\(model)|\(platform)|\(fanCount)|\(modeKeyFormat)|\(unlockAvailable)"
    }

    package func withValidation(_ validation: FanValidationState) -> FanCapability {
        FanCapability(model: model, platform: platform, fanCount: fanCount, modeKeyFormat: modeKeyFormat, unlockAvailable: unlockAvailable, manualCommand: manualCommand, releaseCommand: releaseCommand, managedObservedState: managedObservedState, unlockOn: unlockOn, unlockOff: unlockOff, maxRPMCeiling: maxRPMCeiling, preManualMinimumMultiplier: preManualMinimumMultiplier, boostVerificationMultiplier: boostVerificationMultiplier, defaultLeaseSeconds: defaultLeaseSeconds, maxLeaseSeconds: maxLeaseSeconds, heartbeatSeconds: heartbeatSeconds, missedHeartbeatRestoreSeconds: missedHeartbeatRestoreSeconds, validation: validation)
    }

    package func withResolvedHardware(modeKeyFormat: String, unlockAvailable: Bool) -> FanCapability {
        FanCapability(model: model, platform: platform, fanCount: fanCount, modeKeyFormat: modeKeyFormat, unlockAvailable: unlockAvailable, manualCommand: manualCommand, releaseCommand: releaseCommand, managedObservedState: managedObservedState, unlockOn: unlockOn, unlockOff: unlockOff, maxRPMCeiling: maxRPMCeiling, preManualMinimumMultiplier: preManualMinimumMultiplier, boostVerificationMultiplier: boostVerificationMultiplier, defaultLeaseSeconds: defaultLeaseSeconds, maxLeaseSeconds: maxLeaseSeconds, heartbeatSeconds: heartbeatSeconds, missedHeartbeatRestoreSeconds: missedHeartbeatRestoreSeconds, validation: validation)
    }

    public static let mac165ValidatedOneShot = FanCapability(
        model: "Mac16,5",
        platform: "j616c",
        fanCount: 2,
        modeKeyFormat: "F%dMd",
        unlockAvailable: true,
        manualCommand: 1,
        releaseCommand: 0,
        managedObservedState: 3,
        unlockOn: 1,
        unlockOff: 0,
        maxRPMCeiling: 10_000,
        preManualMinimumMultiplier: 0.95,
        boostVerificationMultiplier: 0.85,
        defaultLeaseSeconds: 600,
        maxLeaseSeconds: 7_200,
        heartbeatSeconds: 2,
        missedHeartbeatRestoreSeconds: 15,
        validation: FanValidationState(
            read: true,
            boostMaxOneShot: true,
            restoreAutoOneShot: true,
            targetClearAfterNonManual: true,
            crashRecovery: false,
            parentDeathRecovery: false,
            missedHeartbeatRecovery: false,
            leaseExpiryRecovery: false,
            signalRecovery: false,
            sleepWakeRecovery: false
        )
    )

    public static let allowlist = [mac165ValidatedOneShot]

    public func key(_ format: String, fan index: Int) throws -> FanKey {
        try FanKey(String(format: format, index))
    }

    public func actualKey(for index: Int) throws -> FanKey { try key("F%dAc", fan: index) }
    public func minimumKey(for index: Int) throws -> FanKey { try key("F%dMn", fan: index) }
    public func maximumKey(for index: Int) throws -> FanKey { try key("F%dMx", fan: index) }
    public func targetKey(for index: Int) throws -> FanKey { try key("F%dTg", fan: index) }
    public func modeKey(for index: Int) throws -> FanKey { try key(modeKeyFormat, fan: index) }
    public var unlockKey: FanKey { try! FanKey("Ftst") }
    public var fanCountKey: FanKey { try! FanKey("FNum") }
    public var platformKey: FanKey { try! FanKey("RPlt") }
}
```

- [ ] **Step 4: Add resolver**

Create `Sources/FanControlCore/FanCapabilityResolver.swift`:

```swift
import Foundation

public struct HostIdentity: Equatable, Sendable {
    public let model: String
    public let platform: String

    public init(model: String, platform: String) {
        self.model = model
        self.platform = platform
    }
}

public struct FanCapabilityResolver {
    private let hardware: FanReader
    private let hostModel: () -> String

    public init(hardware: FanReader, hostModel: @escaping () -> String) {
        self.hardware = hardware
        self.hostModel = hostModel
    }

    public func resolve() throws -> FanCapability {
        let platform = try ascii(try hardware.read(FanCapability.mac165ValidatedOneShot.platformKey))
        let model = hostModel()
        guard let base = FanCapability.allowlist.first(where: { $0.model == model && $0.platform == platform }) else {
            throw FanControlError.unsupportedModel(model: model, platform: platform)
        }

        let fanCount = Int(try uint8(try hardware.read(base.fanCountKey)))
        guard fanCount == base.fanCount else {
            throw FanControlError.unsafeState("fan count mismatch: expected \(base.fanCount), got \(fanCount)")
        }

        if try canRead(String(format: "F%dmd", 0)) {
            throw FanControlError.unsupportedModel(model: model, platform: "lowercase mode key path not validated")
        }
        guard try canRead(String(format: base.modeKeyFormat, 0)) else {
            throw FanControlError.missingKey("fan mode key")
        }
        let unlockAvailable = try canRead("Ftst")

        for index in 0..<fanCount {
            _ = try hardware.read(base.actualKey(for: index))
            _ = try hardware.read(base.minimumKey(for: index))
            _ = try hardware.read(base.maximumKey(for: index))
            _ = try hardware.read(base.targetKey(for: index))
            _ = try hardware.read(base.modeKey(for: index))
        }

        return base.withResolvedHardware(modeKeyFormat: base.modeKeyFormat, unlockAvailable: unlockAvailable)
    }

    private func canRead(_ key: String) throws -> Bool {
        do {
            _ = try hardware.read(try FanKey(key))
            return true
        } catch {
            return false
        }
    }

    private func ascii(_ reading: FanReading) throws -> String {
        guard let value = String(bytes: reading.bytes.prefix { $0 != 0 }, encoding: .ascii) else {
            throw FanControlError.invalidReading(key: reading.key.stringValue, reason: "not ASCII")
        }
        return value
    }

    private func uint8(_ reading: FanReading) throws -> UInt8 {
        guard let value = reading.bytes.first else {
            throw FanControlError.invalidReading(key: reading.key.stringValue, reason: "missing ui8 byte")
        }
        return value
    }
}
```

- [ ] **Step 5: Run tests**

Run:

```sh
swift run FanControlCoreTestRunner
```

Expected includes:

```text
PASS Mac16,5 capability
```

- [ ] **Step 6: Commit**

```sh
git add Sources/FanControlCore Tests/FanControlCoreTestRunner/main.swift
git commit -m "Add fan capability resolver"
```

---

## Task 3: Fake SMC Backend

**Files:**
- Create: `Tests/FanControlCoreTestRunner/FakeSMC.swift`
- Modify: `Tests/FanControlCoreTestRunner/main.swift`

- [ ] **Step 1: Add fake-SMC tests**

Add:

```swift
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
```

Add:

```swift
("FakeSMC delayed Ftst readback", testFakeSMCDelayedFtstReadback),
("FakeSMC rejects early manual", testFakeSMCRejectsManualBeforeUnlockSettles)
```

- [ ] **Step 2: Verify failure**

Run:

```sh
swift run FanControlCoreTestRunner
```

Expected:

```text
error: cannot find 'FakeSMC' in scope
```

- [ ] **Step 3: Implement fake backend**

Create `Tests/FanControlCoreTestRunner/FakeSMC.swift`:

```swift
import FanControlCore
import Foundation

final class FakeSMC: FanHardware {
    struct Entry {
        var type: String
        var size: UInt32
        var attributes: UInt8
        var bytes: [UInt8]
    }

    struct WriteEvent: Equatable {
        let operation: FanWriteOperation
        let key: String
        let bytes: [UInt8]
        let reason: String
        let smcResult: UInt8
    }

    let serviceName = "FakeSMC"
    private(set) var writes: [WriteEvent] = []
    private var entries: [String: Entry]
    private var tick = 0
    private var pending: [(applyAt: Int, key: String, bytes: [UInt8])] = []

    init(entries: [String: Entry]) {
        self.entries = entries
    }

    static func mac165() -> FakeSMC {
        FakeSMC(entries: [
            "FNum": Entry(type: "ui8 ", size: 1, attributes: 0, bytes: [2]),
            "RPlt": Entry(type: "ch8*", size: 8, attributes: 0, bytes: Array("j616c".utf8) + [0, 0, 0]),
            "Ftst": Entry(type: "ui8 ", size: 1, attributes: 0, bytes: [0]),
            "F0Ac": Entry(type: "flt ", size: 4, attributes: 0, bytes: FanEncoding.float32LittleEndian(0)),
            "F0Mn": Entry(type: "flt ", size: 4, attributes: 0, bytes: FanEncoding.float32LittleEndian(1350)),
            "F0Mx": Entry(type: "flt ", size: 4, attributes: 0, bytes: FanEncoding.float32LittleEndian(5777)),
            "F0Tg": Entry(type: "flt ", size: 4, attributes: 0, bytes: FanEncoding.float32LittleEndian(0)),
            "F0Md": Entry(type: "ui8 ", size: 1, attributes: 0, bytes: [3]),
            "F1Ac": Entry(type: "flt ", size: 4, attributes: 0, bytes: FanEncoding.float32LittleEndian(0)),
            "F1Mn": Entry(type: "flt ", size: 4, attributes: 0, bytes: FanEncoding.float32LittleEndian(1350)),
            "F1Mx": Entry(type: "flt ", size: 4, attributes: 0, bytes: FanEncoding.float32LittleEndian(5777)),
            "F1Tg": Entry(type: "flt ", size: 4, attributes: 0, bytes: FanEncoding.float32LittleEndian(0)),
            "F1Md": Entry(type: "ui8 ", size: 1, attributes: 0, bytes: [3])
        ])
    }

    func advanceTick() {
        tick += 1
        let ready = pending.filter { $0.applyAt <= tick }
        pending.removeAll { $0.applyAt <= tick }
        for item in ready {
            entries[item.key]?.bytes = item.bytes
        }
        simulateRamp()
    }

    func read(_ key: FanKey) throws -> FanReading {
        guard let entry = entries[key.stringValue] else {
            throw FanControlError.missingKey(key.stringValue)
        }
        return FanReading(key: key, type: entry.type, size: entry.size, attributes: entry.attributes, bytes: entry.bytes)
    }

    func write(_ operation: FanWriteOperation, capability: FanCapability, reason: String) throws -> FanWriteResult {
        let key: FanKey
        let bytes: [UInt8]
        switch operation {
        case .unlock(let value):
            key = capability.unlockKey
            bytes = [value]
        case .mode(let fan, let value):
            key = try capability.modeKey(for: fan)
            bytes = [value]
        case .target(let fan, let value):
            key = try capability.targetKey(for: fan)
            bytes = value
        }

        guard entries[key.stringValue] != nil else {
            throw FanControlError.missingKey(key.stringValue)
        }

        if case .mode(_, 1) = operation, entries["Ftst"]?.bytes != [1] {
            return record(operation, key: key, bytes: bytes, reason: reason, result: 0x82)
        }

        if key.stringValue == "Ftst" {
            pending.append((applyAt: tick + 3, key: key.stringValue, bytes: bytes))
            return record(operation, key: key, bytes: bytes, reason: reason, result: 0)
        }

        if key.stringValue.hasSuffix("Md") {
            pending.append((applyAt: tick + 2, key: key.stringValue, bytes: bytes))
            return record(operation, key: key, bytes: bytes, reason: reason, result: 0)
        }

        entries[key.stringValue]?.bytes = bytes
        return record(operation, key: key, bytes: bytes, reason: reason, result: 0)
    }

    private func record(_ operation: FanWriteOperation, key: FanKey, bytes: [UInt8], reason: String, result: UInt8) -> FanWriteResult {
        writes.append(WriteEvent(operation: operation, key: key.stringValue, bytes: bytes, reason: reason, smcResult: result))
        return FanWriteResult(kernReturn: 0, smcResult: result, smcStatus: 0)
    }

    private func simulateRamp() {
        for index in 0..<2 {
            guard entries["F\(index)Md"]?.bytes == [1],
                  let target = FanEncoding.floatValue(entries["F\(index)Tg"]?.bytes ?? []),
                  target > 0
            else { continue }
            let actualKey = "F\(index)Ac"
            let current = FanEncoding.floatValue(entries[actualKey]?.bytes ?? []) ?? 0
            entries[actualKey]?.bytes = FanEncoding.float32LittleEndian(min(target, current + 2_000))
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```sh
swift run FanControlCoreTestRunner
```

Expected includes:

```text
PASS FakeSMC delayed Ftst readback
PASS FakeSMC rejects early manual
```

- [ ] **Step 5: Commit**

```sh
git add Tests/FanControlCoreTestRunner
git commit -m "Add fake SMC fan-control backend"
```

---

## Task 4: Status And Availability

**Files:**
- Modify: `Sources/FanControlCore/FanControlTypes.swift`
- Create: `Sources/FanControlCore/FanController.swift`
- Modify: `Tests/FanControlCoreTestRunner/main.swift`

- [ ] **Step 1: Add status tests**

Add:

```swift
func testStatusReadsFanCountAndAvailability() throws {
    let smc = FakeSMC.mac165()
    let capability = FanCapability.mac165ValidatedOneShot
    let controller = FanController(hardware: smc, capability: capability, clock: TestClock())

    let status = try controller.status()

    try expect(status.serviceName == "FakeSMC", "status should include service name")
    try expect(status.fanCount == 2, "status should read FNum")
    try expect(status.platform == "j616c", "status should read platform")
    try expect(status.fans.count == 2, "status should include two fans")
    try expect(status.fans[0].mode == 3, "mode should decode")
    try expect(status.activeAvailability.allowed == false, "active control should not be allowed yet")
    try expect(status.activeAvailability.reasons.contains("crash recovery unverified"), "availability should explain crash gate")
}
```

- [ ] **Step 2: Implement status types**

Append to `FanControlTypes.swift`:

```swift
public struct FanStatus: Equatable, Sendable {
    public let index: Int
    public let actualRPM: Float
    public let minimumRPM: Float
    public let maximumRPM: Float
    public let targetRPM: Float
    public let targetRaw: [UInt8]
    public let mode: UInt8
    public let modeRaw: [UInt8]
}

public struct ActiveAvailability: Equatable, Sendable {
    public let allowed: Bool
    public let reasons: [String]

    public init(allowed: Bool, reasons: [String]) {
        self.allowed = allowed
        self.reasons = reasons
    }
}

public struct FanControlStatus: Equatable, Sendable {
    public let serviceName: String
    public let platform: String
    public let fanCount: Int
    public let fans: [FanStatus]
    public let ftst: UInt8?
    public let activeAvailability: ActiveAvailability
}

public protocol FanControlClock {
    func sleep(seconds: Double)
    var nowUnix: TimeInterval { get }
}

public struct SystemFanControlClock: FanControlClock {
    public init() {}
    public var nowUnix: TimeInterval { Date().timeIntervalSince1970 }
    public func sleep(seconds: Double) { Thread.sleep(forTimeInterval: seconds) }
}
```

- [ ] **Step 3: Add test clock**

Append to `TestSupport.swift`:

```swift
import FanControlCore

final class TestClock: FanControlClock {
    var nowUnix: TimeInterval
    private let onSleep: (() -> Void)?

    init(nowUnix: TimeInterval = 1_800_000_000, onSleep: (() -> Void)? = nil) {
        self.nowUnix = nowUnix
        self.onSleep = onSleep
    }

    func sleep(seconds: Double) {
        nowUnix += seconds
        onSleep?()
    }
}
```

- [ ] **Step 4: Implement controller status**

Create `Sources/FanControlCore/FanController.swift`:

```swift
import Foundation

package final class FanController {
    private let hardware: FanHardware
    private let capability: FanCapability
    private let clock: FanControlClock

    package init(hardware: FanHardware, capability: FanCapability, clock: FanControlClock = SystemFanControlClock()) {
        self.hardware = hardware
        self.capability = capability
        self.clock = clock
    }

    package func status() throws -> FanControlStatus {
        let fanCount = Int(try readUInt8(capability.fanCountKey))
        let platform = try readASCII(capability.platformKey)
        let fans = try (0..<fanCount).map { try readFan($0) }
        let ftst = try? readUInt8(capability.unlockKey)
        return FanControlStatus(
            serviceName: hardware.serviceName,
            platform: platform,
            fanCount: fanCount,
            fans: fans,
            ftst: ftst,
            activeAvailability: availability(fanCount: fanCount, platform: platform, fans: fans)
        )
    }

    private func availability(fanCount: Int, platform: String, fans: [FanStatus]) -> ActiveAvailability {
        var reasons: [String] = []
        if platform != capability.platform { reasons.append("platform mismatch") }
        if fanCount != capability.fanCount { reasons.append("fan count mismatch") }
        if !capability.validation.crashRecovery { reasons.append("crash recovery unverified") }
        if !capability.validation.parentDeathRecovery { reasons.append("parent-death recovery unverified") }
        if !capability.validation.missedHeartbeatRecovery { reasons.append("missed-heartbeat recovery unverified") }
        if !capability.validation.leaseExpiryRecovery { reasons.append("lease-expiry recovery unverified") }
        if !capability.validation.signalRecovery { reasons.append("signal recovery unverified") }
        if !capability.validation.sleepWakeRecovery { reasons.append("sleep/wake recovery unverified") }
        if fans.contains(where: { $0.minimumRPM <= 0 || $0.maximumRPM <= $0.minimumRPM || $0.maximumRPM > capability.maxRPMCeiling }) {
            reasons.append("fan min/max out of bounds")
        }
        return ActiveAvailability(allowed: reasons.isEmpty && capability.validation.activeControlEnabled, reasons: reasons)
    }

    private func readFan(_ index: Int) throws -> FanStatus {
        let actual = try readFloat(capability.actualKey(for: index))
        let minimum = try readFloat(capability.minimumKey(for: index))
        let maximum = try readFloat(capability.maximumKey(for: index))
        let target = try hardware.read(capability.targetKey(for: index))
        let mode = try hardware.read(capability.modeKey(for: index))
        guard let targetRPM = FanEncoding.floatValue(target.bytes), let modeByte = mode.bytes.first else {
            throw FanControlError.invalidReading(key: "fan \(index)", reason: "missing target or mode")
        }
        return FanStatus(index: index, actualRPM: actual, minimumRPM: minimum, maximumRPM: maximum, targetRPM: targetRPM, targetRaw: target.bytes, mode: modeByte, modeRaw: mode.bytes)
    }

    private func readFloat(_ key: FanKey) throws -> Float {
        let reading = try hardware.read(key)
        guard reading.type == "flt ", let value = FanEncoding.floatValue(reading.bytes) else {
            throw FanControlError.invalidReading(key: key.stringValue, reason: "expected flt")
        }
        return value
    }

    private func readUInt8(_ key: FanKey) throws -> UInt8 {
        let reading = try hardware.read(key)
        guard let value = reading.bytes.first else {
            throw FanControlError.invalidReading(key: key.stringValue, reason: "expected ui8")
        }
        return value
    }

    private func readASCII(_ key: FanKey) throws -> String {
        let reading = try hardware.read(key)
        guard let value = String(bytes: reading.bytes.prefix { $0 != 0 }, encoding: .ascii) else {
            throw FanControlError.invalidReading(key: key.stringValue, reason: "expected ASCII")
        }
        return value
    }
}
```

- [ ] **Step 5: Run tests and commit**

```sh
swift run FanControlCoreTestRunner
git add Sources/FanControlCore Tests/FanControlCoreTestRunner
git commit -m "Add fan-control status and availability"
```

---

## Task 5: Audit Logging

**Files:**
- Create: `Sources/FanControlCore/FanControlLogger.swift`
- Modify: `Sources/FanControlCore/FanController.swift`
- Modify: `Tests/FanControlCoreTestRunner/main.swift`

- [ ] **Step 1: Add audit tests**

Add:

```swift
func testAuditEventRecordsWriteDetails() throws {
    let logger = InMemoryFanControlLogger()
    let oldBytes = [UInt8](arrayLiteral: 0)
    let newBytes = [UInt8](arrayLiteral: 1)
    logger.record(FanWriteAuditEvent(
        timestampUnix: 1,
        serviceName: "FakeSMC",
        capabilityFingerprint: "Mac16,5|j616c|2|F%dMd|true",
        leaseID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        key: "Ftst",
        oldRaw: oldBytes,
        newRaw: newBytes,
        kernReturn: 0,
        smcResult: 0,
        smcStatus: 0,
        reason: "test"
    ))
    try expect(logger.events.count == 1, "logger should retain event")
    try expect(logger.events[0].oldRaw == oldBytes, "old bytes should be captured")
    try expect(logger.events[0].newRaw == newBytes, "new bytes should be captured")
}
```

- [ ] **Step 2: Implement logger**

Create `Sources/FanControlCore/FanControlLogger.swift`:

```swift
import Foundation

public struct FanWriteAuditEvent: Codable, Equatable, Sendable {
    public let timestampUnix: TimeInterval
    public let serviceName: String
    public let capabilityFingerprint: String
    public let leaseID: UUID?
    public let key: String
    public let oldRaw: [UInt8]
    public let newRaw: [UInt8]
    public let kernReturn: Int32
    public let smcResult: UInt8
    public let smcStatus: UInt8
    public let reason: String

    public init(timestampUnix: TimeInterval, serviceName: String, capabilityFingerprint: String, leaseID: UUID?, key: String, oldRaw: [UInt8], newRaw: [UInt8], kernReturn: Int32, smcResult: UInt8, smcStatus: UInt8, reason: String) {
        self.timestampUnix = timestampUnix
        self.serviceName = serviceName
        self.capabilityFingerprint = capabilityFingerprint
        self.leaseID = leaseID
        self.key = key
        self.oldRaw = oldRaw
        self.newRaw = newRaw
        self.kernReturn = kernReturn
        self.smcResult = smcResult
        self.smcStatus = smcStatus
        self.reason = reason
    }
}

public protocol FanControlLogger {
    func record(_ event: FanWriteAuditEvent)
}

public final class InMemoryFanControlLogger: FanControlLogger {
    public private(set) var events: [FanWriteAuditEvent] = []
    public init() {}
    public func record(_ event: FanWriteAuditEvent) { events.append(event) }
}

public final class JSONLFanControlLogger: FanControlLogger {
    private let url: URL
    public init(url: URL) { self.url = url }
    public func record(_ event: FanWriteAuditEvent) {
        guard let data = try? JSONEncoder().encode(event) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.write(contentsOf: Data("\n".utf8))
    }
}
```

- [ ] **Step 3: Inject logger into controller**

Change `FanController` initializer:

```swift
private let logger: FanControlLogger

package init(
    hardware: FanHardware,
    capability: FanCapability,
    clock: FanControlClock = SystemFanControlClock(),
    logger: FanControlLogger = InMemoryFanControlLogger()
) {
    self.hardware = hardware
    self.capability = capability
    self.clock = clock
    self.logger = logger
}
```

All future write helpers must read old bytes before the write, call typed hardware write, read result metadata, and record `FanWriteAuditEvent`.

- [ ] **Step 4: Run tests and commit**

```sh
swift run FanControlCoreTestRunner
git add Sources/FanControlCore Tests/FanControlCoreTestRunner
git commit -m "Add fan-control audit logging"
```

---

## Task 6: Lease And Watchdog Model

**Files:**
- Create: `Sources/FanControlCore/FanLease.swift`
- Modify: `Sources/FanControlCore/FanController.swift`
- Modify: `Tests/FanControlCoreTestRunner/main.swift`

- [ ] **Step 1: Add lease tests**

Add:

```swift
func testLeaseStoresPreBoostBytesAndHeartbeat() throws {
    let dir = try temporaryDirectory()
    let store = FanLeaseStore(directory: dir)
    let lease = FanLease(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        capabilityFingerprint: FanCapability.mac165ValidatedOneShot.fingerprint,
        ownerPID: 10,
        parentPID: 9,
        createdAtUnix: 1_800_000_000,
        expiresAtUnix: 1_800_000_600,
        heartbeatAtUnix: 1_800_000_000,
        phase: .created,
        capturedFans: [
            CapturedFanState(index: 0, modeRaw: [3], targetRaw: [0, 0, 0, 0]),
            CapturedFanState(index: 1, modeRaw: [3], targetRaw: [0, 0, 0, 0])
        ],
        reason: "test"
    )

    try store.claim(lease)
    try expect(try store.read() == lease, "lease should round-trip")
    try store.heartbeat(nowUnix: 1_800_000_002)
    try expect(try store.read().heartbeatAtUnix == 1_800_000_002, "heartbeat should update")
    do {
        try store.claim(lease)
        throw TestFailure(description: "duplicate lease claim should fail")
    } catch FanLeaseStoreError.leaseAlreadyExists {
    }
}
```

- [ ] **Step 2: Add temp directory helper**

Append to `TestSupport.swift`:

```swift
func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("mlx-chill-tests")
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
```

- [ ] **Step 3: Implement lease model**

Create `Sources/FanControlCore/FanLease.swift`:

```swift
import Foundation
import Darwin

public enum FanLeasePhase: String, Codable, Equatable, Sendable {
    case created
    case unlocking
    case manual
    case boosted
    case restoring
}

public enum FanLeaseStoreError: Error, Equatable {
    case leaseAlreadyExists
}

public struct CapturedFanState: Codable, Equatable, Sendable {
    public let index: Int
    public let modeRaw: [UInt8]
    public let targetRaw: [UInt8]
    public init(index: Int, modeRaw: [UInt8], targetRaw: [UInt8]) {
        self.index = index
        self.modeRaw = modeRaw
        self.targetRaw = targetRaw
    }
}

public struct FanLease: Codable, Equatable, Sendable {
    public let id: UUID
    public let capabilityFingerprint: String
    public let ownerPID: Int32
    public let parentPID: Int32
    public let createdAtUnix: TimeInterval
    public let expiresAtUnix: TimeInterval
    public var heartbeatAtUnix: TimeInterval
    public var phase: FanLeasePhase
    public let capturedFans: [CapturedFanState]
    public let reason: String

    public init(id: UUID, capabilityFingerprint: String, ownerPID: Int32, parentPID: Int32, createdAtUnix: TimeInterval, expiresAtUnix: TimeInterval, heartbeatAtUnix: TimeInterval, phase: FanLeasePhase, capturedFans: [CapturedFanState], reason: String) {
        self.id = id
        self.capabilityFingerprint = capabilityFingerprint
        self.ownerPID = ownerPID
        self.parentPID = parentPID
        self.createdAtUnix = createdAtUnix
        self.expiresAtUnix = expiresAtUnix
        self.heartbeatAtUnix = heartbeatAtUnix
        self.phase = phase
        self.capturedFans = capturedFans
        self.reason = reason
    }
}

public final class FanLeaseStore {
    private let directory: URL
    private let fileURL: URL

    public init(directory: URL) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("current-lease.json")
    }

    public static func defaultStore() -> FanLeaseStore {
        FanLeaseStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MLXChill/fan-control", isDirectory: true))
    }

    public func claim(_ lease: FanLease) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(lease)
        let fd = open(fileURL.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            if errno == EEXIST { throw FanLeaseStoreError.leaseAlreadyExists }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(fd) }
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var written = 0
            while written < rawBuffer.count {
                let result = Darwin.write(fd, base.advanced(by: written), rawBuffer.count - written)
                guard result > 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                written += result
            }
        }
        guard fsync(fd) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    public func overwriteForRecovery(_ lease: FanLease) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(lease).write(to: fileURL, options: [.atomic])
    }

    public func read() throws -> FanLease {
        try JSONDecoder().decode(FanLease.self, from: Data(contentsOf: fileURL))
    }

    public func readIfPresent() -> FanLease? { try? read() }

    public func heartbeat(nowUnix: TimeInterval) throws {
        var lease = try read()
        lease.heartbeatAtUnix = nowUnix
        try overwriteForRecovery(lease)
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}
```

- [ ] **Step 4: Wire store into controller**

Replace the `FanController` stored properties and initializer with:

```swift
private let hardware: FanHardware
private let capability: FanCapability
private let clock: FanControlClock
private let logger: FanControlLogger
private let leaseStore: FanLeaseStore

package init(
    hardware: FanHardware,
    capability: FanCapability,
    clock: FanControlClock = SystemFanControlClock(),
    logger: FanControlLogger = InMemoryFanControlLogger(),
    leaseStore: FanLeaseStore = .defaultStore()
) {
    self.hardware = hardware
    self.capability = capability
    self.clock = clock
    self.logger = logger
    self.leaseStore = leaseStore
}
```

- [ ] **Step 5: Add restore trigger tests**

Add recovery decision types to `FanControlTypes.swift`:

```swift
public enum FanRecoveryReason: String, Equatable, Sendable {
    case noLease
    case activeLease
    case missedHeartbeat
    case expiredLease
    case parentExited
    case capabilityMismatch
}

public struct FanRecoveryDecision: Equatable, Sendable {
    public let shouldRestore: Bool
    public let reason: FanRecoveryReason

    public init(shouldRestore: Bool, reason: FanRecoveryReason) {
        self.shouldRestore = shouldRestore
        self.reason = reason
    }
}
```

Add to `FanController`:

```swift
package func recoveryDecision(nowUnix: TimeInterval? = nil, currentParentPID: Int32? = nil) -> FanRecoveryDecision {
    guard let lease = leaseStore.readIfPresent() else {
        return FanRecoveryDecision(shouldRestore: false, reason: .noLease)
    }
    let now = nowUnix ?? clock.nowUnix
    if lease.capabilityFingerprint != capability.fingerprint {
        return FanRecoveryDecision(shouldRestore: true, reason: .capabilityMismatch)
    }
    if now >= lease.expiresAtUnix {
        return FanRecoveryDecision(shouldRestore: true, reason: .expiredLease)
    }
    if now - lease.heartbeatAtUnix > TimeInterval(capability.missedHeartbeatRestoreSeconds) {
        return FanRecoveryDecision(shouldRestore: true, reason: .missedHeartbeat)
    }
    if let parent = currentParentPID, parent != lease.parentPID {
        return FanRecoveryDecision(shouldRestore: true, reason: .parentExited)
    }
    return FanRecoveryDecision(shouldRestore: false, reason: .activeLease)
}
```

Add tests:

```swift
func sampleLease(
    capabilityFingerprint: String = FanCapability.mac165ValidatedOneShot.fingerprint,
    parentPID: Int32 = 9,
    expiresAtUnix: TimeInterval = 1_800_000_600,
    heartbeatAtUnix: TimeInterval = 1_800_000_000
) -> FanLease {
    FanLease(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        capabilityFingerprint: capabilityFingerprint,
        ownerPID: 10,
        parentPID: parentPID,
        createdAtUnix: 1_800_000_000,
        expiresAtUnix: expiresAtUnix,
        heartbeatAtUnix: heartbeatAtUnix,
        phase: .boosted,
        capturedFans: [
            CapturedFanState(index: 0, modeRaw: [3], targetRaw: [0, 0, 0, 0]),
            CapturedFanState(index: 1, modeRaw: [3], targetRaw: [0, 0, 0, 0])
        ],
        reason: "test"
    )
}

func testMissedHeartbeatRequiresRecovery() throws {
    let dir = try temporaryDirectory()
    let store = FanLeaseStore(directory: dir)
    try store.claim(sampleLease(heartbeatAtUnix: 1_800_000_000))
    let controller = FanController(hardware: FakeSMC.mac165(), capability: .mac165ValidatedOneShot, leaseStore: store)
    let decision = controller.recoveryDecision(nowUnix: 1_800_000_016)
    try expect(decision == FanRecoveryDecision(shouldRestore: true, reason: .missedHeartbeat), "missed heartbeat should require restore")
}

func testExpiredLeaseRequiresRecovery() throws {
    let dir = try temporaryDirectory()
    let store = FanLeaseStore(directory: dir)
    try store.claim(sampleLease(expiresAtUnix: 1_800_000_010))
    let controller = FanController(hardware: FakeSMC.mac165(), capability: .mac165ValidatedOneShot, leaseStore: store)
    let decision = controller.recoveryDecision(nowUnix: 1_800_000_010)
    try expect(decision == FanRecoveryDecision(shouldRestore: true, reason: .expiredLease), "expired lease should require restore")
}

func testParentDeathRequiresRecovery() throws {
    let dir = try temporaryDirectory()
    let store = FanLeaseStore(directory: dir)
    try store.claim(sampleLease(parentPID: 9))
    let controller = FanController(hardware: FakeSMC.mac165(), capability: .mac165ValidatedOneShot, leaseStore: store)
    let decision = controller.recoveryDecision(nowUnix: 1_800_000_001, currentParentPID: 1)
    try expect(decision == FanRecoveryDecision(shouldRestore: true, reason: .parentExited), "parent change should require restore")
}

func testModelMismatchRequiresRecovery() throws {
    let dir = try temporaryDirectory()
    let store = FanLeaseStore(directory: dir)
    try store.claim(sampleLease(capabilityFingerprint: "different"))
    let controller = FanController(hardware: FakeSMC.mac165(), capability: .mac165ValidatedOneShot, leaseStore: store)
    let decision = controller.recoveryDecision(nowUnix: 1_800_000_001)
    try expect(decision == FanRecoveryDecision(shouldRestore: true, reason: .capabilityMismatch), "capability mismatch should require restore")
}
```

- [ ] **Step 6: Run tests and commit**

```sh
swift run FanControlCoreTestRunner
git add Sources/FanControlCore Tests/FanControlCoreTestRunner
git commit -m "Add fan-control lease watchdog model"
```

---

## Task 7: Boost State Machine

**Files:**
- Modify: `Sources/FanControlCore/FanController.swift`
- Modify: `Sources/FanControlCore/FanControlTypes.swift`
- Modify: `Tests/FanControlCoreTestRunner/main.swift`

- [ ] **Step 1: Add boost tests**

Add tests that prove:

```swift
func testBoostCreatesLeaseBeforeFirstWrite() throws
func testBoostRestoresOnWriteFailureAfterLeaseCreation() throws
func testBoostUsesHardwareValidatedSequence() throws
func testBoostRefusesWhenActiveControlDisabled() throws
```

Append the package-scoped test fixture to `TestSupport.swift`:

```swift
func activeTestCapability() -> FanCapability {
    FanCapability.mac165ValidatedOneShot.withValidation(FanValidationState(
        read: true,
        boostMaxOneShot: true,
        restoreAutoOneShot: true,
        targetClearAfterNonManual: true,
        crashRecovery: true,
        parentDeathRecovery: true,
        missedHeartbeatRecovery: true,
        leaseExpiryRecovery: true,
        signalRecovery: true,
        sleepWakeRecovery: true
    ))
}
```

Use `activeTestCapability()` in the lease creation, write-failure, and validated-sequence tests. Use `FanCapability.mac165ValidatedOneShot` only in `testBoostRefusesWhenActiveControlDisabled`.

The first test asserts `FanLeaseStore.readIfPresent()` is non-nil before the first `FakeSMC.writes` entry.

The failure test configures `FakeSMC` to reject `F1Md=1`; expected result:

```swift
try expect(smc.writes.contains { $0.operation == .unlock(value: 0) }, "boost failure should restore Ftst")
try expect(smc.writes.contains { $0.operation == .mode(fan: 0, value: 0) }, "boost failure should release fan 0")
try expect(smc.writes.contains { $0.operation == .mode(fan: 1, value: 0) }, "boost failure should release fan 1")
```

- [ ] **Step 2: Implement boost with lease-before-write**

Add result:

```swift
public struct FanBoostResult: Equatable, Sendable {
    public let leaseID: UUID
    public let verified: Bool
    public let maxActualRPM: Float
}
```

Add `boostMax(leaseSeconds:reason:)`:

```swift
package func boostMax(leaseSeconds: Int, reason: String) throws -> FanBoostResult {
    guard capability.validation.activeControlEnabled else {
        throw FanControlError.activeControlDisabled(model: capability.model)
    }
    guard leaseSeconds > 0 && leaseSeconds <= capability.maxLeaseSeconds else {
        throw FanControlError.unsafeState("lease duration outside allowed range")
    }

    let snapshot = try status()
    try validate(snapshot)
    let lease = try createLease(from: snapshot, leaseSeconds: leaseSeconds, reason: reason)
    try leaseStore.claim(lease)

    do {
        try writeUnlock(capability.unlockOn, lease: lease, reason: "unlock fan test mode")
        try pollUnlock(capability.unlockOn)
        try requestTargetsToMax(snapshot, lease: lease)
        try waitForSafePreManualTargets(snapshot)
        try enterManual(snapshot, lease: lease)
        try confirmTargetsToMax(snapshot, lease: lease)
        let result = try verifyRamp(snapshot, lease: lease)
        return FanBoostResult(leaseID: lease.id, verified: true, maxActualRPM: result)
    } catch {
        try? restoreAuto(reason: "boost failed: \(error)", recoveryMode: true)
        throw error
    }
}
```

Every write helper must:

1. Read old raw bytes.
2. Call typed hardware write.
3. Record `FanWriteAuditEvent`.
4. Throw on unexpected SMC result.

- [ ] **Step 3: Run tests and commit**

```sh
swift run FanControlCoreTestRunner
git add Sources/FanControlCore Tests/FanControlCoreTestRunner
git commit -m "Implement leased fan boost state machine"
```

---

## Task 8: Restore State Machine

**Files:**
- Modify: `Sources/FanControlCore/FanController.swift`
- Modify: `Sources/FanControlCore/FanControlTypes.swift`
- Modify: `Tests/FanControlCoreTestRunner/main.swift`

- [ ] **Step 1: Add restore tests**

Add tests that prove:

```swift
func testRestoreUsesCapturedLeaseTargetsNotCurrentTargets() throws
func testRestoreNeverClearsTargetWhileManual() throws
func testRestoreClearsLeaseOnlyAfterManagedSettle() throws
func testAutoNoopsWhenNoLeaseExists() throws
```

For `testRestoreUsesCapturedLeaseTargetsNotCurrentTargets`, set current `F0Tg/F1Tg` to max in `FakeSMC`, write a lease with captured target `[0,0,0,0]`, run restore, and assert target clear writes use captured zero bytes only after mode writes.

- [ ] **Step 2: Implement restore from lease**

Add:

```swift
public struct FanRestoreResult: Equatable, Sendable {
    public let restored: Bool
    public let finalModes: [UInt8]
    public let finalTargets: [Float]
}
```

Add:

```swift
@discardableResult
package func restoreAuto(reason: String, recoveryMode: Bool = false) throws -> FanRestoreResult {
    guard let lease = leaseStore.readIfPresent() else {
        if recoveryMode { throw FanControlError.leaseRequired("recovery requested without lease") }
        return FanRestoreResult(restored: true, finalModes: [], finalTargets: [])
    }
    guard lease.capabilityFingerprint == capability.fingerprint else {
        throw FanControlError.unsafeState("lease capability fingerprint mismatch; refusing restore writes")
    }

    let current = try status()
    for fan in current.fans {
        try writeTarget(fan: fan.index, bytes: FanEncoding.float32LittleEndian(fan.maximumRPM), lease: lease, reason: "safe high target before release: \(reason)")
    }
    for fan in current.fans {
        try writeMode(fan: fan.index, value: capability.releaseCommand, lease: lease, reason: "release manual mode: \(reason)")
    }
    if capability.unlockAvailable {
        try writeUnlock(capability.unlockOff, lease: lease, reason: "restore unlock: \(reason)")
        try pollUnlock(capability.unlockOff)
    }
    try pollNonManual()

    for captured in lease.capturedFans {
        try writeTarget(fan: captured.index, bytes: captured.targetRaw, lease: lease, reason: "restore captured target after non-manual: \(reason)")
    }

    let final = try pollManagedSettle()
    try leaseStore.clear()
    return FanRestoreResult(restored: true, finalModes: final.fans.map(\.mode), finalTargets: final.fans.map(\.targetRPM))
}
```

`pollManagedSettle()` must require:

- no fan mode equals manual command
- `Ftst == 0` when unlock is available
- target and actual RPM settle to managed idle for this capability

- [ ] **Step 3: Run tests and commit**

```sh
swift run FanControlCoreTestRunner
git add Sources/FanControlCore Tests/FanControlCoreTestRunner
git commit -m "Implement lease-based fan restore"
```

---

## Task 9: CLI Parser And Active Executable Gate

**Files:**
- Create: `Sources/FanControlCore/FanControlCommand.swift`
- Modify: `Sources/mlx-chill-control/main.swift`
- Modify: `README.md`
- Modify: `Tests/FanControlCoreTestRunner/main.swift`

- [ ] **Step 1: Add parser tests**

Add tests for:

```swift
func testCLIParsesBoundedBoostDuration() throws
func testCLIRejectsMissingAcknowledgement() throws
func testCLIRejectsLeaseOverTwoHours() throws
func testCLIRunParsesWorkloadAndDuration() throws
func testCLIRunIgnoresWorkloadFlagsAfterDelimiter() throws
```

Expected duration behavior:

- `--for 1s` allowed
- `--for 10m` allowed
- `--for 120m` allowed
- `--for 121m` rejected
- `--for 0s` rejected
- negative values rejected

- [ ] **Step 2: Implement parser**

Create `Sources/FanControlCore/FanControlCommand.swift`:

```swift
import Foundation

public enum FanControlCommand: Equatable, Sendable {
    case statusJSON
    case boostMax(durationSeconds: Int, acknowledgedRisk: Bool)
    case auto
    case runBoostMax(durationSeconds: Int, workload: [String], acknowledgedRisk: Bool)

    public static func parse(_ args: [String], maxDurationSeconds: Int = 7_200) throws -> FanControlCommand {
        if args == ["status", "--json"] { return .statusJSON }
        if args == ["auto"] { return .auto }
        if args.prefix(2) == ["boost", "max"] {
            let duration = try parseDuration(args, maxDurationSeconds: maxDurationSeconds)
            try requireAcknowledgement(args)
            return .boostMax(durationSeconds: duration, acknowledgedRisk: true)
        }
        if args.prefix(3) == ["run", "--boost", "max"] {
            guard let split = args.firstIndex(of: "--") else {
                throw FanControlError.unsafeState("run requires workload after --")
            }
            let controlArgs = Array(args[..<split])
            let duration = try parseDuration(controlArgs, maxDurationSeconds: maxDurationSeconds)
            try requireAcknowledgement(controlArgs)
            let workload = Array(args[args.index(after: split)...])
            guard !workload.isEmpty else {
                throw FanControlError.unsafeState("run requires workload after --")
            }
            return .runBoostMax(durationSeconds: duration, workload: workload, acknowledgedRisk: true)
        }
        throw FanControlError.unsafeState("unknown fan-control command")
    }

    private static func requireAcknowledgement(_ args: [String]) throws {
        guard args.contains("--i-understand-active-fan-control") else {
            throw FanControlError.unsafeState("active fan control requires --i-understand-active-fan-control acknowledgement")
        }
    }

    private static func parseDuration(_ args: [String], maxDurationSeconds: Int) throws -> Int {
        guard let index = args.firstIndex(of: "--for"), args.index(after: index) < args.endIndex else {
            return 600
        }
        let raw = args[args.index(after: index)]
        let seconds: Int?
        if raw.hasSuffix("m") {
            seconds = Int(raw.dropLast()).map { $0 * 60 }
        } else if raw.hasSuffix("s") {
            seconds = Int(raw.dropLast())
        } else {
            seconds = nil
        }
        guard let value = seconds, value > 0, value <= maxDurationSeconds else {
            throw FanControlError.unsafeState("duration must be between 1s and \(maxDurationSeconds)s")
        }
        return value
    }
}
```

- [ ] **Step 3: Wire `mlx-chill-control` without enabling boost execution**

Modify `Sources/mlx-chill-control/main.swift`:

```swift
import FanControlCore
import Foundation

do {
    let command = try FanControlCommand.parse(Array(CommandLine.arguments.dropFirst()))
    print("Parsed active fan-control command: \(command)")
    print("Execution remains disabled until crash and sleep/wake recovery are validated.")
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
```

Do not modify `Sources/mlx-chill/main.swift`.

- [ ] **Step 4: Verify CLI boundary**

Run:

```sh
swift run FanControlCoreTestRunner
swift build -c release
.build/release/mlx-chill FNum
.build/release/mlx-chill-control boost max --for 10m
.build/release/mlx-chill-control boost max --for 10m --i-understand-active-fan-control
nm -m .build/release/mlx-chill | rg 'SMCControlTransport|FanController|writeBytes' && exit 1 || echo 'mlx-chill read-only boundary clean'
```

Expected:

```text
FNum  ui8   2  raw=0x02
active fan control requires --i-understand-active-fan-control acknowledgement
Parsed active fan-control command: boostMax(durationSeconds: 600, acknowledgedRisk: true)
mlx-chill read-only boundary clean
```

- [ ] **Step 5: Commit**

```sh
git add Sources/FanControlCore/FanControlCommand.swift Sources/mlx-chill-control/main.swift README.md Tests/FanControlCoreTestRunner/main.swift
git commit -m "Add gated active fan-control CLI"
```

---

## Task 10: Real Typed SMC Transport

**Files:**
- Modify: `Sources/SMCControlTransport/SMCControlTransport.swift`
- Modify: `Tests/FanControlCoreTestRunner/main.swift`

- [ ] **Step 1: Add static safety tests**

Add:

```swift
func testReadOnlyCSMCHeaderHasNoWriteAPI() throws {
    let headerURL = repoRootFromThisFile().appendingPathComponent("Sources/CSMC/include/CSMC.h")
    let header = try String(contentsOf: headerURL)
    try expect(!header.contains("Write"), "read-only CSMC header must not expose write functions")
}
```

Add:

```swift
("Read-only CSMC header has no write API", testReadOnlyCSMCHeaderHasNoWriteAPI)
```

- [ ] **Step 2: Implement private raw transport**

Replace `Sources/SMCControlTransport/SMCControlTransport.swift` with a Swift-native IOKit implementation that conforms to `FanHardware`.

Requirements:

- package surface is only `package final class SMCFanHardware: FanHardware`
- raw IOKit method is private
- raw `write(key:bytes:)` is private
- package `write(_ operation: FanWriteOperation, capability: FanCapability, reason: String)` switches over typed operations and derives keys from `capability`
- operation `.unlock` can only write `Ftst`
- operation `.mode` can only write `F{n}Md`/`F{n}md` from capability
- operation `.target` can only write `F{n}Tg` from capability
- unsupported fan index throws before any write

Implementation outline:

```swift
import FanControlCore
import Foundation
import IOKit

package final class SMCFanHardware: FanHardware {
    public let serviceName: String
    private let connection: io_connect_t

    package init() throws {
        // Try AppleSMC, then AppleSMCKeysEndpoint; pin selected service for lifetime.
    }

    deinit {
        IOServiceClose(connection)
    }

    package func read(_ key: FanKey) throws -> FanReading {
        // Read key info, then read bytes.
    }

    package func write(_ operation: FanWriteOperation, capability: FanCapability, reason: String) throws -> FanWriteResult {
        let key: FanKey
        let bytes: [UInt8]
        switch operation {
        case .unlock(let value):
            guard capability.unlockAvailable else { throw FanControlError.missingKey("Ftst") }
            key = capability.unlockKey
            bytes = [value]
        case .mode(let fan, let value):
            guard fan >= 0 && fan < capability.fanCount else { throw FanControlError.unsafeState("fan index out of range") }
            key = try capability.modeKey(for: fan)
            bytes = [value]
        case .target(let fan, let value):
            guard fan >= 0 && fan < capability.fanCount else { throw FanControlError.unsafeState("fan index out of range") }
            key = try capability.targetKey(for: fan)
            bytes = value
        }
        return try privateWrite(key: key, bytes: bytes)
    }

    private func privateWrite(key: FanKey, bytes: [UInt8]) throws -> FanWriteResult {
        // Read key info, verify size, call IOConnectCallStructMethod selector 2 command 6.
    }
}
```

Use the validated scratch-probe struct layout and command values from the spec.

- [ ] **Step 3: Verify no public raw write**

Run:

```sh
rg -n 'public func write\\(key|func write\\(key' Sources/SMCControlTransport Sources/FanControlCore
```

Expected: no matches.

- [ ] **Step 4: Run tests and boundary check**

```sh
swift run FanControlCoreTestRunner
swift run FanProbeCoreTestRunner
swift build -c release
nm -m .build/release/mlx-chill | rg 'SMCControlTransport|FanController|writeBytes' && exit 1 || echo 'mlx-chill read-only boundary clean'
```

Expected:

```text
PASS Read-only CSMC header has no write API
PASS 7/7 tests
Build complete!
mlx-chill read-only boundary clean
```

- [ ] **Step 5: Commit**

```sh
git add Sources/SMCControlTransport Tests/FanControlCoreTestRunner
git commit -m "Add typed SMC fan hardware transport"
```

---

## Task 11: Recovery Execution Gates

**Files:**
- Modify: `Sources/mlx-chill-control/main.swift`
- Create: `docs/hardware/2026-06-27-mac16-5-fan-control-validation.md`
- Modify: `README.md`

- [ ] **Step 1: Add hardware validation record**

Create `docs/hardware/2026-06-27-mac16-5-fan-control-validation.md`:

```markdown
# Mac16,5 Fan Control Validation

Date: 2026-06-27
Model: Mac16,5
Platform: j616c
macOS: Version 26.5.1 (Build 25F80)

## Result

One-shot max boost and restore succeeded.

## Observed Sequence

- `Ftst=1` required polling before readback changed.
- `F0Md/F1Md=1` initially returned SMC result `0x82`, then accepted.
- `F0Tg/F1Tg=5777` stuck after manual mode readback.
- Fan 0 reached `5505 RPM`.
- Fan 1 reached `5199 RPM`.
- Restore settled to `F0Md/F1Md=3`, `F0Tg/F1Tg=0`, `Ftst=0`, actual RPM `0`.

## Still Unverified

- Crash recovery.
- Sleep/wake recovery.
- Parent process death recovery.
- Missed-heartbeat recovery.
- Lease-expiry recovery.
- Signal handling recovery.
- Long-running workload wrapper.

## Active Control Decision

Keep `activeControlEnabled=false` until every recovery flag in `FanValidationState` is validated on hardware.
```

- [ ] **Step 2: Keep execution disabled**

Modify `mlx-chill-control` so `boost` and `run` parse but refuse execution unless `resolvedCapability.validation.activeControlEnabled == true`.

Keep `auto` available as a recovery-only command:

- if no lease exists, `auto` exits zero without writing
- if a lease exists and `lease.capabilityFingerprint == resolvedCapability.fingerprint`, `auto` may call `restoreAuto(reason: "explicit auto", recoveryMode: true)`
- if a lease exists with a mismatched fingerprint, `auto` refuses to write and reports the mismatch

Expected active command output:

```text
active fan control is disabled for Mac16,5
```

- [ ] **Step 3: Add recovery validation tasks to README**

Document:

```markdown
`mlx-chill-control` is present for active-control development, but boost
execution remains disabled until crash recovery, parent-death recovery,
missed-heartbeat recovery, lease-expiry recovery, signal recovery, and
sleep/wake recovery are validated on hardware. `auto` remains recovery-only for
compatible existing MLX & Chill leases.
```

- [ ] **Step 4: Final verification**

Run:

```sh
swift run FanControlCoreTestRunner
swift run FanProbeCoreTestRunner
swift build -c release
.build/release/mlx-chill FNum F0Ac F0Tg F0Md F1Ac F1Tg F1Md Ftst RPlt
.build/release/mlx-chill-control boost max --for 10m --i-understand-active-fan-control
nm -m .build/release/mlx-chill | rg 'SMCControlTransport|FanController|writeBytes' && exit 1 || echo 'mlx-chill read-only boundary clean'
git status --short --branch
```

Expected:

```text
PASS
Build complete!
F0Tg  flt   0
F0Md  ui8   3
F1Tg  flt   0
F1Md  ui8   3
Ftst  ui8   0
active fan control is disabled for Mac16,5
mlx-chill read-only boundary clean
## main...origin/main
```

- [ ] **Step 5: Commit**

```sh
git add Sources/mlx-chill-control README.md docs/hardware
git commit -m "Document fan-control hardware gate"
```

---

## Follow-Up Plan Required Before Enabling Boost

Write a separate plan before setting any capability to active:

- crash recovery hardware validation
- parent-process-death validation
- missed-heartbeat validation
- lease-expiry validation
- signal handling validation
- sleep/wake restore validation
- `mlx-chill-control run --boost max -- <workload>` execution path
- final hardware log showing restore after each failure mode

## Self-Review

- Spec coverage: typed write transport, no raw public write API, model/platform allowlist, mode-key detection, delayed `Ftst`/mode/target polling, lease-before-write, restore-on-failure, captured target restore, target-clear phase barrier, audit logging, heartbeat/watchdog model, read-only `mlx-chill` boundary, and final hardware gate are covered.
- Deliberate non-goal: active boost/run execution remains disabled in production until crash, parent-death, missed-heartbeat, lease-expiry, signal, and sleep/wake recovery are validated.
- Red-flag scan: this plan avoids vague markers and open-ended implementation steps.
- Review-agent fixes: the prior P0/P1 issues are addressed by mandatory `mlx-chill-control`, package-scoped typed writes, capability resolver, `Ftst`/fan inventory detection, atomic lease ownership, watchdog model, recovery-only `auto`, audit logging, bounded durations, public initializers, throwing-safe tests, and package-root-safe file reads.

## Execution Options

1. **Subagent-Driven (recommended)** - Dispatch a fresh implementation subagent per task, review between tasks, and keep commits small.
2. **Inline Execution** - Execute tasks in this session with checkpoints after each task.
