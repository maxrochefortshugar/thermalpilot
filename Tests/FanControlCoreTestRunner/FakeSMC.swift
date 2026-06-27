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
            "F0Mn": Entry(type: "flt ", size: 4, attributes: 0, bytes: FanEncoding.float32LittleEndian(1_350)),
            "F0Mx": Entry(type: "flt ", size: 4, attributes: 0, bytes: FanEncoding.float32LittleEndian(5_777)),
            "F0Tg": Entry(type: "flt ", size: 4, attributes: 0, bytes: FanEncoding.float32LittleEndian(0)),
            "F0Md": Entry(type: "ui8 ", size: 1, attributes: 0, bytes: [3]),
            "F1Ac": Entry(type: "flt ", size: 4, attributes: 0, bytes: FanEncoding.float32LittleEndian(0)),
            "F1Mn": Entry(type: "flt ", size: 4, attributes: 0, bytes: FanEncoding.float32LittleEndian(1_350)),
            "F1Mx": Entry(type: "flt ", size: 4, attributes: 0, bytes: FanEncoding.float32LittleEndian(5_777)),
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
