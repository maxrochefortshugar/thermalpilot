import CSMC
import Foundation

public enum SMCClientError: Error, CustomStringConvertible {
    case openFailed(kern_return_t)
    case readFailed(key: String, kern_return_t)
    case indexReadFailed(index: UInt32, kern_return_t)

    public var description: String {
        switch self {
        case .openFailed(let code):
            return "failed to open AppleSMC user client (\(formatKernReturn(code)))"
        case .readFailed(let key, let code):
            return "failed to read SMC key \(key) (\(formatKernReturn(code)))"
        case .indexReadFailed(let index, let code):
            return "failed to read SMC key at index \(index) (\(formatKernReturn(code)))"
        }
    }
}

public struct SMCReading: Equatable, Sendable {
    public let key: SMCKeyCode
    public let type: String
    public let size: UInt32
    public let bytes: [UInt8]
    public let decoded: SMCDecodedValue
}

public final class SMCClient {
    private let connection: io_connect_t

    public init() throws {
        var connection: io_connect_t = 0
        let result = CSMCOpen(&connection)
        guard result == KERN_SUCCESS else {
            throw SMCClientError.openFailed(result)
        }
        self.connection = connection
    }

    deinit {
        CSMCClose(connection)
    }

    public func read(_ key: SMCKeyCode) throws -> SMCReading {
        var value = CSMCValue()
        let result = CSMCReadKey(connection, key.rawValue, &value)
        guard result == KERN_SUCCESS else {
            throw SMCClientError.readFailed(key: key.stringValue, result)
        }

        let type = SMCKeyCode(rawValue: value.dataType).stringValue
        let bytes = withUnsafeBytes(of: value.bytes) { buffer in
            Array(buffer.prefix(Int(value.dataSize)))
        }
        let decoded = SMCValueDecoder.decode(type: type, bytes: bytes, size: value.dataSize)

        return SMCReading(
            key: key,
            type: type,
            size: value.dataSize,
            bytes: bytes,
            decoded: decoded
        )
    }

    public func read(_ key: String) throws -> SMCReading {
        try read(SMCKeyCode(key))
    }

    public func key(at index: UInt32) throws -> SMCKeyCode {
        var rawKey: UInt32 = 0
        let result = CSMCReadKeyAtIndex(connection, index, &rawKey)
        guard result == KERN_SUCCESS else {
            throw SMCClientError.indexReadFailed(index: index, result)
        }

        return SMCKeyCode(rawValue: rawKey)
    }

    public func keyCount() -> UInt32? {
        guard let reading = try? read("#KEY"),
              let value = reading.decoded.numericValue,
              value >= 0
        else {
            return nil
        }

        return UInt32(value)
    }
}

private func formatKernReturn(_ code: kern_return_t) -> String {
    String(format: "0x%08X", UInt32(bitPattern: code))
}
