import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum FanLeasePhase: String, Codable, Equatable, Sendable {
    case created
    case unlocking
    case manual
    case boosted
    case restoring
}

public enum FanLeaseStoreError: Error, Equatable, Sendable {
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
    public let heartbeatAtUnix: TimeInterval
    public let phase: FanLeasePhase
    public let capturedFans: [CapturedFanState]
    public let reason: String

    public init(
        id: UUID,
        capabilityFingerprint: String,
        ownerPID: Int32,
        parentPID: Int32,
        createdAtUnix: TimeInterval,
        expiresAtUnix: TimeInterval,
        heartbeatAtUnix: TimeInterval,
        phase: FanLeasePhase,
        capturedFans: [CapturedFanState],
        reason: String
    ) {
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

    package func withHeartbeat(nowUnix: TimeInterval) -> FanLease {
        FanLease(
            id: id,
            capabilityFingerprint: capabilityFingerprint,
            ownerPID: ownerPID,
            parentPID: parentPID,
            createdAtUnix: createdAtUnix,
            expiresAtUnix: expiresAtUnix,
            heartbeatAtUnix: nowUnix,
            phase: phase,
            capturedFans: capturedFans,
            reason: reason
        )
    }
}

public struct FanLeaseStore {
    private let directory: URL
    private var leaseURL: URL {
        directory.appendingPathComponent("current-lease.json", isDirectory: false)
    }

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultStore() -> FanLeaseStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return FanLeaseStore(directory: base.appendingPathComponent("MLXChill/fan-control", isDirectory: true))
    }

    public func claim(_ lease: FanLease) throws {
        let data = try encode(lease)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fd = open(leaseURL.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        if fd < 0 {
            if errno == EEXIST {
                throw FanLeaseStoreError.leaseAlreadyExists
            }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        do {
            try writeAll(data, to: fd)
            guard fsync(fd) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            _ = close(fd)
            _ = unlink(leaseURL.path)
            throw error
        }

        guard close(fd) == 0 else {
            _ = unlink(leaseURL.path)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    public func overwriteForRecovery(_ lease: FanLease) throws {
        let data = try encode(lease)
        try replaceCurrentLease(with: data)
    }

    public func read() throws -> FanLease {
        try decode(Data(contentsOf: leaseURL))
    }

    public func readIfPresent() throws -> FanLease? {
        guard FileManager.default.fileExists(atPath: leaseURL.path) else { return nil }
        return try read()
    }

    public func heartbeat(nowUnix: TimeInterval) throws {
        let lease = try read().withHeartbeat(nowUnix: nowUnix)
        try overwriteForRecovery(lease)
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: leaseURL.path) else { return }
        try FileManager.default.removeItem(at: leaseURL)
    }

    private func replaceCurrentLease(with data: Data) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory.appendingPathComponent(".current-lease-\(UUID().uuidString).tmp", isDirectory: false)
        let fd = open(temporaryURL.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        do {
            try writeAll(data, to: fd)
            guard fsync(fd) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            _ = close(fd)
            _ = unlink(temporaryURL.path)
            throw error
        }

        guard close(fd) == 0 else {
            _ = unlink(temporaryURL.path)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        if rename(temporaryURL.path, leaseURL.path) != 0 {
            let capturedErrno = errno
            _ = unlink(temporaryURL.path)
            throw POSIXError(POSIXErrorCode(rawValue: capturedErrno) ?? .EIO)
        }
    }

    private func encode(_ lease: FanLease) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(lease)
    }

    private func decode(_ data: Data) throws -> FanLease {
        try JSONDecoder().decode(FanLease.self, from: data)
    }

    private func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard var pointer = buffer.baseAddress else { return }
            var remaining = buffer.count

            while remaining > 0 {
                let written = write(fd, pointer, remaining)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                if written == 0 { throw POSIXError(.EIO) }
                pointer = pointer.advanced(by: written)
                remaining -= written
            }
        }
    }
}
