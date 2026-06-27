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

        return FanStatus(
            index: index,
            actualRPM: actual,
            minimumRPM: minimum,
            maximumRPM: maximum,
            targetRPM: targetRPM,
            targetRaw: target.bytes,
            mode: modeByte,
            modeRaw: mode.bytes
        )
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
