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

public struct FanStatus: Equatable, Sendable {
    public let index: Int
    public let actualRPM: Float
    public let minimumRPM: Float
    public let maximumRPM: Float
    public let targetRPM: Float
    public let targetRaw: [UInt8]
    public let mode: UInt8
    public let modeRaw: [UInt8]

    public init(index: Int, actualRPM: Float, minimumRPM: Float, maximumRPM: Float, targetRPM: Float, targetRaw: [UInt8], mode: UInt8, modeRaw: [UInt8]) {
        self.index = index
        self.actualRPM = actualRPM
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
        self.targetRPM = targetRPM
        self.targetRaw = targetRaw
        self.mode = mode
        self.modeRaw = modeRaw
    }
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

    public init(serviceName: String, platform: String, fanCount: Int, fans: [FanStatus], ftst: UInt8?, activeAvailability: ActiveAvailability) {
        self.serviceName = serviceName
        self.platform = platform
        self.fanCount = fanCount
        self.fans = fans
        self.ftst = ftst
        self.activeAvailability = activeAvailability
    }
}

public enum FanRecoveryReason: Equatable, Sendable {
    case noLease
    case activeLease
    case corruptLease
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

public struct FanOwnerProcessInfo: Equatable, Sendable {
    public let pid: Int32
    public let parentPID: Int32?
    public let startTimeUnix: TimeInterval?

    public init(pid: Int32, parentPID: Int32?, startTimeUnix: TimeInterval?) {
        self.pid = pid
        self.parentPID = parentPID
        self.startTimeUnix = startTimeUnix
    }
}

public protocol FanProcessInspecting {
    func ownerProcessInfo(pid: Int32) -> FanOwnerProcessInfo?
}

public protocol FanControlClock {
    var nowUnix: TimeInterval { get }
    func sleep(seconds: Double)
}

public struct SystemFanControlClock: FanControlClock {
    public init() {}

    public var nowUnix: TimeInterval {
        Date().timeIntervalSince1970
    }

    public func sleep(seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
