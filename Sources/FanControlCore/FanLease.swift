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
    case leaseMissing
    case leaseIdentityMismatch
    case corruptLease
    case unreadableLease
}

package struct FanLeaseStorePersistenceHooks {
    package let failBeforeClaimPublish: (any Error)?

    package init(failBeforeClaimPublish: (any Error)? = nil) {
        self.failBeforeClaimPublish = failBeforeClaimPublish
    }
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
    public let ownerStartTimeUnix: TimeInterval?
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
        ownerStartTimeUnix: TimeInterval? = nil,
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
        self.ownerStartTimeUnix = ownerStartTimeUnix
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
            ownerStartTimeUnix: ownerStartTimeUnix,
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
    private let persistenceHooks: FanLeaseStorePersistenceHooks
    private var leaseURL: URL {
        directory.appendingPathComponent("current-lease.json", isDirectory: false)
    }
    private var lockURL: URL {
        directory.appendingPathComponent(".current-lease.lock", isDirectory: false)
    }

    public init(directory: URL) {
        self.directory = directory
        self.persistenceHooks = FanLeaseStorePersistenceHooks()
    }

    package init(directory: URL, persistenceHooks: FanLeaseStorePersistenceHooks) {
        self.directory = directory
        self.persistenceHooks = persistenceHooks
    }

    public static func defaultStore() -> FanLeaseStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return FanLeaseStore(directory: base.appendingPathComponent("MLXChill/fan-control", isDirectory: true))
    }

    public func claim(_ lease: FanLease) throws {
        let data = try encode(lease)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try withMutationLock {
            let temporaryURL = try writeDurableTemporaryLease(data)
            var published = false
            defer {
                if !published {
                    _ = unlink(temporaryURL.path)
                }
            }

            if let failure = persistenceHooks.failBeforeClaimPublish {
                throw failure
            }

            if link(temporaryURL.path, leaseURL.path) != 0 {
                let capturedErrno = errno
                if capturedErrno == EEXIST {
                    throw FanLeaseStoreError.leaseAlreadyExists
                }
                throw POSIXError(POSIXErrorCode(rawValue: capturedErrno) ?? .EIO)
            }
            published = true
            try fsyncDirectory()

            if unlink(temporaryURL.path) != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try fsyncDirectory()
        }
    }

    public func overwriteForRecovery(_ lease: FanLease, replacingLeaseID expectedLeaseID: UUID) throws {
        let data = try encode(lease)
        try withMutationLock {
            let current = try readExistingLease()
            guard current.id == expectedLeaseID else {
                throw FanLeaseStoreError.leaseIdentityMismatch
            }
            try replaceCurrentLease(with: data)
        }
    }

    public func read() throws -> FanLease {
        guard FileManager.default.fileExists(atPath: leaseURL.path) else {
            throw FanLeaseStoreError.leaseMissing
        }
        let data: Data
        do {
            data = try Data(contentsOf: leaseURL)
        } catch {
            if FileManager.default.fileExists(atPath: leaseURL.path) {
                throw FanLeaseStoreError.unreadableLease
            }
            throw FanLeaseStoreError.leaseMissing
        }
        return try decode(data)
    }

    public func readIfPresent() throws -> FanLease? {
        guard FileManager.default.fileExists(atPath: leaseURL.path) else { return nil }
        return try read()
    }

    public func heartbeat(leaseID: UUID, nowUnix: TimeInterval) throws {
        try withMutationLock {
            let current = try readExistingLease()
            guard current.id == leaseID else {
                throw FanLeaseStoreError.leaseIdentityMismatch
            }
            let lease = current.withHeartbeat(nowUnix: nowUnix)
            try replaceCurrentLease(with: try encode(lease))
        }
    }

    public func clear(leaseID: UUID) throws {
        try withMutationLock {
            let current = try readExistingLease()
            guard current.id == leaseID else {
                throw FanLeaseStoreError.leaseIdentityMismatch
            }
            if unlink(leaseURL.path) != 0 {
                let capturedErrno = errno
                if capturedErrno == ENOENT {
                    throw FanLeaseStoreError.leaseMissing
                }
                throw POSIXError(POSIXErrorCode(rawValue: capturedErrno) ?? .EIO)
            }
            try fsyncDirectory()
        }
    }

    private func replaceCurrentLease(with data: Data) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = try writeDurableTemporaryLease(data)

        if rename(temporaryURL.path, leaseURL.path) != 0 {
            let capturedErrno = errno
            _ = unlink(temporaryURL.path)
            throw POSIXError(POSIXErrorCode(rawValue: capturedErrno) ?? .EIO)
        }
        try fsyncDirectory()
    }

    private func writeDurableTemporaryLease(_ data: Data) throws -> URL {
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

        return temporaryURL
    }

    private func encode(_ lease: FanLease) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(lease)
    }

    private func decode(_ data: Data) throws -> FanLease {
        do {
            return try JSONDecoder().decode(FanLease.self, from: data)
        } catch {
            throw FanLeaseStoreError.corruptLease
        }
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

    private func readExistingLease() throws -> FanLease {
        guard let lease = try readIfPresent() else {
            throw FanLeaseStoreError.leaseMissing
        }
        return lease
    }

    private func withMutationLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(lockURL.path, O_RDWR | O_CREAT, 0o600)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { _ = close(fd) }

        guard flock(fd, LOCK_EX) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { _ = flock(fd, LOCK_UN) }

        return try body()
    }

    private func fsyncDirectory() throws {
        let fd = open(directory.path, O_RDONLY)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { _ = close(fd) }

        guard fsync(fd) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
