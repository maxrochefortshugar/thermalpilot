import Foundation

public struct FanWriteAuditEvent: Equatable, Sendable, Codable {
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

    public init(
        timestampUnix: TimeInterval,
        serviceName: String,
        capabilityFingerprint: String,
        leaseID: UUID?,
        key: String,
        oldRaw: [UInt8],
        newRaw: [UInt8],
        kernReturn: Int32,
        smcResult: UInt8,
        smcStatus: UInt8,
        reason: String
    ) {
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
