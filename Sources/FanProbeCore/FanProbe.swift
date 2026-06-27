import Darwin
import Foundation

public struct HostInfo: Equatable, Sendable {
    public let model: String
    public let chip: String
    public let architecture: String
    public let thermalState: String
}

public struct FanSnapshot: Equatable, Sendable {
    public let index: Int
    public let current: SMCReading?
    public let minimum: SMCReading?
    public let maximum: SMCReading?
    public let target: SMCReading?
}

public struct FanProbeSnapshot: Equatable, Sendable {
    public let host: HostInfo
    public let smcError: String?
    public let keyCount: UInt32?
    public let fanCount: Int?
    public let fans: [FanSnapshot]
    public let temperatures: [SMCReading]
    public let powers: [SMCReading]
    public let warnings: [String]
}

public enum FanProbe {
    public static func snapshot() -> FanProbeSnapshot {
        let host = HostInfo.current()

        do {
            let client = try SMCClient()
            let keyCount = client.keyCount()
            let fanCount = readFanCount(client)
            let fans = readFans(client, fanCount: fanCount)
            let candidateKeys = discoverKeys(client, keyCount: keyCount)
            let temperatures = readSensorGroup(
                client,
                keys: candidateKeys.temperatureKeys,
                fallbackKeys: fallbackTemperatureKeys,
                limit: 32,
                include: { reading in
                    reading.decoded.numericValue.map { $0 > -50 && $0 < 150 } == true
                }
            )
            let powers = readSensorGroup(
                client,
                keys: candidateKeys.powerKeys,
                fallbackKeys: fallbackPowerKeys,
                limit: 16,
                include: { reading in
                    reading.decoded.numericValue != nil
                }
            )

            return FanProbeSnapshot(
                host: host,
                smcError: nil,
                keyCount: keyCount,
                fanCount: fanCount,
                fans: fans,
                temperatures: temperatures,
                powers: powers,
                warnings: candidateKeys.warnings
            )
        } catch {
            return FanProbeSnapshot(
                host: host,
                smcError: String(describing: error),
                keyCount: nil,
                fanCount: nil,
                fans: [],
                temperatures: [],
                powers: [],
                warnings: []
            )
        }
    }

    public static func render(_ snapshot: FanProbeSnapshot) -> String {
        var lines: [String] = []

        lines.append("Coldfront")
        lines.append("")
        lines.append("Host")
        lines.append("  Model: \(snapshot.host.model)")
        lines.append("  Chip: \(snapshot.host.chip)")
        lines.append("  Architecture: \(snapshot.host.architecture)")
        lines.append("  Thermal state: \(snapshot.host.thermalState)")
        lines.append("")
        lines.append("SMC")

        if let smcError = snapshot.smcError {
            lines.append("  Status: unavailable")
            lines.append("  Error: \(smcError)")
            return lines.joined(separator: "\n")
        }

        lines.append("  Status: readable")
        lines.append("  Key count: \(snapshot.keyCount.map(String.init) ?? "unavailable")")
        lines.append("  Fan count: \(snapshot.fanCount.map(String.init) ?? "unavailable")")

        lines.append("")
        lines.append("Fans")
        if snapshot.fans.isEmpty {
            lines.append("  unavailable")
        } else {
            for fan in snapshot.fans {
                lines.append("  Fan \(fan.index)")
                lines.append("    Current: \(display(fan.current))")
                lines.append("    Minimum: \(display(fan.minimum))")
                lines.append("    Maximum: \(display(fan.maximum))")
                lines.append("    Target: \(display(fan.target))")
            }
        }

        lines.append("")
        lines.append("Temperatures")
        appendReadings(snapshot.temperatures, to: &lines)

        lines.append("")
        lines.append("Power")
        appendReadings(snapshot.powers, to: &lines)

        if !snapshot.warnings.isEmpty {
            lines.append("")
            lines.append("Warnings")
            for warning in snapshot.warnings {
                lines.append("  \(warning)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

public extension HostInfo {
    static func current() -> HostInfo {
        HostInfo(
            model: sysctlString("hw.model") ?? "unknown",
            chip: sysctlString("machdep.cpu.brand_string") ?? "unknown",
            architecture: sysctlString("hw.machine") ?? "unknown",
            thermalState: thermalStateDescription(ProcessInfo.processInfo.thermalState)
        )
    }
}

public func renderExplicitReadings(_ readings: [Result<SMCReading, Error>]) -> String {
    readings.map { result in
        switch result {
        case .success(let reading):
            return "\(reading.key.stringValue)  \(reading.type)  \(reading.decoded.displayValue)  raw=\(hexString(reading.bytes))"
        case .failure(let error):
            return "ERROR  \(error)"
        }
    }
    .joined(separator: "\n")
}

private struct DiscoveredKeys {
    let temperatureKeys: [SMCKeyCode]
    let powerKeys: [SMCKeyCode]
    let warnings: [String]
}

private let fallbackTemperatureKeys = [
    "TC0P", "TC0E", "TC0F", "TG0P", "TB0T", "TW0P",
    "Tp09", "Tp0T", "Tp01", "Tp05", "Te05", "Ts0S", "TM0P"
]

private let fallbackPowerKeys = [
    "PCPC", "PCPG", "PCPT", "PSTR"
]

private func readFanCount(_ client: SMCClient) -> Int? {
    guard let reading = try? client.read("FNum"),
          let value = reading.decoded.numericValue
    else {
        return nil
    }

    return max(0, min(Int(value), 8))
}

private func readFans(_ client: SMCClient, fanCount: Int?) -> [FanSnapshot] {
    guard let fanCount, fanCount > 0 else {
        return []
    }

    return (0..<fanCount).map { index in
        FanSnapshot(
            index: index,
            current: try? client.read("F\(index)Ac"),
            minimum: try? client.read("F\(index)Mn"),
            maximum: try? client.read("F\(index)Mx"),
            target: try? client.read("F\(index)Tg")
        )
    }
}

private func discoverKeys(_ client: SMCClient, keyCount: UInt32?) -> DiscoveredKeys {
    guard let keyCount, keyCount > 0 else {
        return DiscoveredKeys(temperatureKeys: [], powerKeys: [], warnings: [])
    }

    let boundedCount = min(keyCount, 8_192)
    var temperatureKeys: [SMCKeyCode] = []
    var powerKeys: [SMCKeyCode] = []
    var warnings: [String] = []

    if keyCount > boundedCount {
        warnings.append("SMC key enumeration capped at \(boundedCount) of \(keyCount) keys")
    }

    for index in UInt32(0)..<boundedCount {
        guard let key = try? client.key(at: index) else {
            continue
        }

        if key.stringValue.hasPrefix("T") {
            temperatureKeys.append(key)
        } else if key.stringValue.hasPrefix("P") {
            powerKeys.append(key)
        }
    }

    return DiscoveredKeys(
        temperatureKeys: temperatureKeys.sorted { $0.stringValue < $1.stringValue },
        powerKeys: powerKeys.sorted { $0.stringValue < $1.stringValue },
        warnings: warnings
    )
}

private func readSensorGroup(
    _ client: SMCClient,
    keys: [SMCKeyCode],
    fallbackKeys: [String],
    limit: Int,
    include: (SMCReading) -> Bool
) -> [SMCReading] {
    var seen = Set<SMCKeyCode>()
    var readings: [SMCReading] = []
    let combinedKeys = keys + fallbackKeys.compactMap { try? SMCKeyCode($0) }

    for key in combinedKeys where !seen.contains(key) {
        seen.insert(key)

        guard let reading = try? client.read(key), include(reading) else {
            continue
        }

        readings.append(reading)
        if readings.count >= limit {
            break
        }
    }

    return readings
}

private func appendReadings(_ readings: [SMCReading], to lines: inout [String]) {
    if readings.isEmpty {
        lines.append("  unavailable")
        return
    }

    for reading in readings {
        lines.append("  \(reading.key.stringValue): \(reading.decoded.displayValue) [\(reading.type)]")
    }
}

private func display(_ reading: SMCReading?) -> String {
    guard let reading else {
        return "unavailable"
    }

    return "\(reading.decoded.displayValue) [\(reading.type)]"
}

private func hexString(_ bytes: [UInt8]) -> String {
    if bytes.isEmpty {
        return "0x"
    }

    return "0x" + bytes.map { String(format: "%02X", $0) }.joined()
}

private func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
        return nil
    }

    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
        return nil
    }

    let bytes = buffer
        .prefix { $0 != 0 }
        .map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
}

private func thermalStateDescription(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal:
        return "nominal"
    case .fair:
        return "fair"
    case .serious:
        return "serious"
    case .critical:
        return "critical"
    @unknown default:
        return "unknown"
    }
}
