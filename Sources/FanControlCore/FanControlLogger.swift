import Foundation

package struct FanWriteAuditEvent: Equatable, Sendable, Codable {
    package let timestampUnix: TimeInterval
    package let serviceName: String
    package let key: FanKey
    package let reason: String
    package let requestedBytes: [UInt8]
    package let oldBytes: [UInt8]
    package let resultBytes: [UInt8]
    package let kernReturn: Int32
    package let smcResult: UInt8
    package let smcStatus: UInt8

    package init(
        timestampUnix: TimeInterval,
        serviceName: String,
        key: FanKey,
        reason: String,
        requestedBytes: [UInt8],
        oldBytes: [UInt8],
        resultBytes: [UInt8],
        kernReturn: Int32,
        smcResult: UInt8,
        smcStatus: UInt8
    ) {
        self.timestampUnix = timestampUnix
        self.serviceName = serviceName
        self.key = key
        self.reason = reason
        self.requestedBytes = requestedBytes
        self.oldBytes = oldBytes
        self.resultBytes = resultBytes
        self.kernReturn = kernReturn
        self.smcResult = smcResult
        self.smcStatus = smcStatus
    }

    private enum CodingKeys: String, CodingKey {
        case timestampUnix
        case serviceName
        case key
        case reason
        case requestedBytes
        case oldBytes
        case resultBytes
        case kernReturn
        case smcResult
        case smcStatus
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestampUnix = try container.decode(TimeInterval.self, forKey: .timestampUnix)
        serviceName = try container.decode(String.self, forKey: .serviceName)
        key = try FanKey(container.decode(String.self, forKey: .key))
        reason = try container.decode(String.self, forKey: .reason)
        requestedBytes = try container.decode([UInt8].self, forKey: .requestedBytes)
        oldBytes = try container.decode([UInt8].self, forKey: .oldBytes)
        resultBytes = try container.decode([UInt8].self, forKey: .resultBytes)
        kernReturn = try container.decode(Int32.self, forKey: .kernReturn)
        smcResult = try container.decode(UInt8.self, forKey: .smcResult)
        smcStatus = try container.decode(UInt8.self, forKey: .smcStatus)
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestampUnix, forKey: .timestampUnix)
        try container.encode(serviceName, forKey: .serviceName)
        try container.encode(key.stringValue, forKey: .key)
        try container.encode(reason, forKey: .reason)
        try container.encode(requestedBytes, forKey: .requestedBytes)
        try container.encode(oldBytes, forKey: .oldBytes)
        try container.encode(resultBytes, forKey: .resultBytes)
        try container.encode(kernReturn, forKey: .kernReturn)
        try container.encode(smcResult, forKey: .smcResult)
        try container.encode(smcStatus, forKey: .smcStatus)
    }
}

package protocol FanControlLogger: AnyObject {
    func record(_ event: FanWriteAuditEvent) throws
}

package final class InMemoryFanControlLogger: FanControlLogger {
    package private(set) var events: [FanWriteAuditEvent] = []

    package init() {}

    package func record(_ event: FanWriteAuditEvent) throws {
        events.append(event)
    }
}

package final class JSONLFanControlLogger: FanControlLogger {
    private let url: URL
    private let encoder: JSONEncoder

    package init(url: URL, encoder: JSONEncoder = JSONEncoder()) {
        self.url = url
        self.encoder = encoder
    }

    package func record(_ event: FanWriteAuditEvent) throws {
        var data = try encoder.encode(event)
        data.append(0x0A)

        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }
}
