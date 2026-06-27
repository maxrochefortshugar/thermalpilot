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
