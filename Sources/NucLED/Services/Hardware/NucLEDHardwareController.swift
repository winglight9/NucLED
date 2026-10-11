import Foundation
import IOKit

/// Real hardware backend. It never assumes a write worked: every user-visible
/// state is derived from a read through the driver user client.
actor NucLEDHardwareController: LEDHardwareControlling {
    private let driver: NUCLEDDriverClient
    private let snapshotStore: LEDStateSnapshotStore

    init(driver: NUCLEDDriverClient = NUCLEDDriverClient()) {
        self.driver = driver
        self.snapshotStore = LEDStateSnapshotStore()
    }

    func readLEDEnabled() async throws -> Bool {
        let inventory = try driver.readInventory()
        try Self.requireDisableSupport(inventory)
        let states = try Self.readStates(inventory: inventory, using: driver)
        // A mixed state is reported as enabled because at least one zone is
        // still assigned a live indicator mode.
        return states.values.contains { $0 != NUCLEDIndicator.disabled }
    }

    func setLEDEnabled(_ enabled: Bool) async throws {
        if enabled {
            try restoreFromSnapshot()
        } else {
            try disableAndPersistSnapshot()
        }
    }

    private func disableAndPersistSnapshot() throws {
        let inventory = try driver.readInventory()
        try Self.requireDisableSupport(inventory)
        let current = try Self.readStates(inventory: inventory, using: driver)

        if let existing = try snapshotStore.load() {
            try Self.validate(existing, against: inventory)
            if existing.operation == .initializePowerState {
                try Self.validateInitialPowerStateProgress(existing, current: current, inventory: inventory)
                try snapshotStore.remove()
            } else {
                let allDisabled = current.values.allSatisfy { $0 == NUCLEDIndicator.disabled }
                if allDisabled { return }

                // A prior failed transaction may have rolled back completely but
                // failed while deleting its journal. Clear only if every region
                // still matches that exact saved state; otherwise fail closed.
                if current == existing.indicatorsByZone {
                    try snapshotStore.remove()
                } else {
                    throw NUCLEDHardwareError.unexpectedCurrentState
                }
            }
        }

        guard current.values.contains(where: { $0 != NUCLEDIndicator.disabled }) else {
            // The pre-existing all-disabled state has no recoverable "on"
            // mode. Do not fabricate one or claim that it can be restored.
            return
        }

        let snapshot = LEDStateSnapshot(inventory: inventory, indicatorsByZone: current)
        // Durably materialize the restore point before the first firmware
        // write. A failure here leaves the hardware untouched.
        try snapshotStore.save(snapshot)

        var attempted: [UInt8] = []
        do {
            for zone in Self.zones(in: inventory.presentMask) {
                guard current[zone] != NUCLEDIndicator.disabled else { continue }
                // A failed ACPI write may still have reached firmware, so add
                // to the rollback set before making the call.
                attempted.append(zone)
                try driver.setIndicator(zone: zone, indicator: NUCLEDIndicator.disabled)
                try Self.verify(zone: zone, expected: NUCLEDIndicator.disabled, using: driver)
            }
        } catch {
            let operationFailure = error.localizedDescription
            let rollbackFailures = Self.restore(snapshot.indicatorsByZone, zones: attempted, using: driver)
            if rollbackFailures.isEmpty {
                do {
                    try snapshotStore.remove()
                } catch {
                    throw NUCLEDHardwareError.rollbackSucceededButJournalCleanupFailed(
                        operation: operationFailure,
                        cleanup: error.localizedDescription
                    )
                }
                throw NUCLEDHardwareError.operationFailed(operationFailure)
            }
            throw NUCLEDHardwareError.rollbackFailed(
                operation: operationFailure,
                rollback: rollbackFailures
            )
        }
    }

    private func restoreFromSnapshot() throws {
        let inventory = try driver.readInventory()
        try Self.requireDisableSupport(inventory)
        let current = try Self.readStates(inventory: inventory, using: driver)
        guard let snapshot = try snapshotStore.load() else {
            try initializePowerState(inventory: inventory, current: current)
            return
        }
        try Self.validate(snapshot, against: inventory)
        if snapshot.operation == .initializePowerState {
            try continueInitialPowerState(snapshot, inventory: inventory, current: current)
            return
        }
        let target = snapshot.indicatorsByZone
        guard snapshot.indicators.contains(where: { $0.indicator != NUCLEDIndicator.disabled }) else {
            throw NUCLEDHardwareError.noRecoverableSnapshot
        }

        // Resume a previously interrupted restore only when each present zone
        // is either still disabled or already at the exact snapshotted mode.
        // Any third value suggests an external change, so do not overwrite it.
        for (zone, value) in current {
            guard let prior = target[zone], value == prior || value == NUCLEDIndicator.disabled else {
                throw NUCLEDHardwareError.unexpectedCurrentState
            }
        }
        if current == target {
            try snapshotStore.remove()
            return
        }

        var attempted: [UInt8] = []
        do {
            for zone in Self.zones(in: inventory.presentMask) {
                guard let prior = target[zone] else {
                    throw NUCLEDHardwareError.snapshotMismatch
                }
                guard prior != NUCLEDIndicator.disabled,
                      current[zone] == NUCLEDIndicator.disabled else { continue }
                attempted.append(zone)
                try driver.setIndicator(zone: zone, indicator: prior)
                try Self.verify(zone: zone, expected: prior, using: driver)
            }
        } catch {
            let operationFailure = error.localizedDescription
            let rollbackFailures = Self.restore(
                Dictionary(uniqueKeysWithValues: Self.zones(in: inventory.presentMask).map {
                    ($0, NUCLEDIndicator.disabled)
                }),
                zones: attempted,
                using: driver
            )
            if rollbackFailures.isEmpty {
                throw NUCLEDHardwareError.operationFailed(operationFailure)
            }
            throw NUCLEDHardwareError.rollbackFailed(
                operation: operationFailure,
                rollback: rollbackFailures
            )
        }

        // Keep the journal if removal fails; the next turn-on still checks
        // actual hardware state and reports a clear mismatch rather than
        // making an unverified change.
        do {
            try snapshotStore.remove()
        } catch {
            throw NUCLEDHardwareError.restoredButJournalCleanupFailed(error.localizedDescription)
        }
    }

    /// On a first turn-on from a fully disabled firmware state there is no
    /// prior light mode to restore. Use the documented Power State mode only
    /// for zones that report support for indicator ID 0, and journal the
    /// pre-write state so an interrupted transaction can be safely retried.
    private func initializePowerState(inventory: NUCLEDInventory,
                                      current: [UInt8: UInt8]) throws {
        guard current.values.allSatisfy({ $0 == NUCLEDIndicator.disabled }) else {
            throw NUCLEDHardwareError.noRecoverableSnapshot
        }
        let eligible = Self.zones(in: inventory.presentMask).filter {
            current[$0] == NUCLEDIndicator.disabled &&
            inventory.powerStateSupportedMask & (1 << $0) != 0
        }
        let unsupported = Self.zones(in: inventory.presentMask).filter {
            current[$0] == NUCLEDIndicator.disabled &&
            inventory.powerStateSupportedMask & (1 << $0) == 0
        }
        guard !eligible.isEmpty, unsupported.isEmpty else {
            throw NUCLEDHardwareError.powerStateUnsupported(unsupported.map(NUCLEDZone.name(for:)))
        }
        let snapshot = LEDStateSnapshot(
            inventory: inventory,
            indicatorsByZone: current,
            operation: .initializePowerState
        )
        try snapshotStore.save(snapshot)
        try continueInitialPowerState(snapshot, inventory: inventory, current: current)
    }

    private func continueInitialPowerState(_ snapshot: LEDStateSnapshot,
                                          inventory: NUCLEDInventory,
                                          current: [UInt8: UInt8]) throws {
        try Self.validateInitialPowerStateProgress(snapshot, current: current, inventory: inventory)
        let eligible = Self.zones(in: inventory.presentMask).filter {
            snapshot.indicatorsByZone[$0] == NUCLEDIndicator.disabled &&
            inventory.powerStateSupportedMask & (1 << $0) != 0
        }
        var attempted: [UInt8] = []
        do {
            for zone in eligible where current[zone] == NUCLEDIndicator.disabled {
                attempted.append(zone)
                try driver.setIndicator(zone: zone, indicator: NUCLEDIndicator.powerState)
                try Self.verify(zone: zone, expected: NUCLEDIndicator.powerState, using: driver)
            }
        } catch {
            let operationFailure = error.localizedDescription
            let rollbackFailures = Self.restore(
                Dictionary(uniqueKeysWithValues: attempted.map { ($0, NUCLEDIndicator.disabled) }),
                zones: attempted,
                using: driver
            )
            if rollbackFailures.isEmpty {
                do {
                    try snapshotStore.remove()
                } catch {
                    throw NUCLEDHardwareError.rollbackSucceededButJournalCleanupFailed(
                        operation: operationFailure,
                        cleanup: error.localizedDescription
                    )
                }
                throw NUCLEDHardwareError.operationFailed(operationFailure)
            }
            throw NUCLEDHardwareError.rollbackFailed(
                operation: operationFailure,
                rollback: rollbackFailures
            )
        }

        do {
            try snapshotStore.remove()
        } catch {
            throw NUCLEDHardwareError.powerStateAppliedButJournalCleanupFailed(error.localizedDescription)
        }

    }

    private static func verify(zone: UInt8, expected: UInt8, using driver: NUCLEDDriverClient) throws {
        let actual = try driver.readIndicator(zone: zone)
        guard actual == expected else {
            throw NUCLEDHardwareError.readbackMismatch(
                zone: NUCLEDZone.name(for: zone), expected: expected, actual: actual
            )
        }
    }

    private static func readStates(inventory: NUCLEDInventory,
                                   using driver: NUCLEDDriverClient) throws -> [UInt8: UInt8] {
        var states: [UInt8: UInt8] = [:]
        for zone in zones(in: inventory.presentMask) {
            states[zone] = try driver.readIndicator(zone: zone)
        }
        return states
    }

    private static func zones(in mask: UInt8) -> [UInt8] {
        (0..<7).compactMap { bit in
            mask & (1 << bit) == 0 ? nil : UInt8(bit)
        }
    }

    private static func requireDisableSupport(_ inventory: NUCLEDInventory) throws {
        let unsupported = zones(in: inventory.presentMask & ~inventory.disableSupportedMask)
        guard !unsupported.isEmpty else { return }
        throw NUCLEDHardwareError.disableUnsupported(unsupported.map(NUCLEDZone.name(for:)))
    }

    private static func validate(_ snapshot: LEDStateSnapshot,
                                 against inventory: NUCLEDInventory) throws {
        guard (1...LEDStateSnapshot.currentVersion).contains(snapshot.version),
              snapshot.presentMask == inventory.presentMask,
        snapshot.indicators.count == snapshot.indicatorsByZone.count,
              Set(snapshot.indicatorsByZone.keys) == Set(zones(in: inventory.presentMask)),
              snapshot.indicatorsByZone.values.allSatisfy({ $0 <= NUCLEDIndicator.disabled }),
              snapshot.operation != .initializePowerState ||
                snapshot.powerStateSupportedMask == inventory.powerStateSupportedMask else {
            throw NUCLEDHardwareError.snapshotMismatch
        }
    }

    private static func validateInitialPowerStateProgress(_ snapshot: LEDStateSnapshot,
                                                           current: [UInt8: UInt8],
                                                           inventory: NUCLEDInventory) throws {
        guard snapshot.operation == .initializePowerState else {
            throw NUCLEDHardwareError.snapshotMismatch
        }
        let baseline = snapshot.indicatorsByZone
        for zone in zones(in: inventory.presentMask) {
            guard let original = baseline[zone], let actual = current[zone] else {
                throw NUCLEDHardwareError.snapshotMismatch
            }
            let isEligible = original == NUCLEDIndicator.disabled &&
                inventory.powerStateSupportedMask & (1 << zone) != 0
            guard actual == original || (isEligible && actual == NUCLEDIndicator.powerState) else {
                throw NUCLEDHardwareError.unexpectedCurrentState
            }
        }
    }

    private static func restore(_ values: [UInt8: UInt8],
                                zones: [UInt8],
                                using driver: NUCLEDDriverClient) -> [String] {
        var failures: [String] = []
        for zone in zones.reversed() {
            guard let expected = values[zone] else {
                failures.append("\(NUCLEDZone.name(for: zone))：快照缺少此灯区")
                continue
            }
            do {
                try driver.setIndicator(zone: zone, indicator: expected)
                try verify(zone: zone, expected: expected, using: driver)
            } catch {
                failures.append("\(NUCLEDZone.name(for: zone))：\(error.localizedDescription)")
            }
        }
        return failures
    }
}

private enum NUCLEDIndicator {
    static let powerState: UInt8 = 0
    static let disabled: UInt8 = 6
}

struct NUCLEDInventory: Sendable {
    let presentMask: UInt8
    let disableSupportedMask: UInt8
    let powerStateSupportedMask: UInt8
}

private enum NUCLEDZone {
    private static let names = ["电源灯", "硬盘灯", "骷髅灯", "眼睛灯", "前面板灯 1", "前面板灯 2", "前面板灯 3"]

    static func name(for zone: UInt8) -> String {
        Int(zone) < names.count ? names[Int(zone)] : "未知灯区 \(zone)"
    }
}

private struct LEDStateSnapshot: Codable {
    static let currentVersion = 2

    let version: Int
    let presentMask: UInt8
    let powerStateSupportedMask: UInt8
    let operation: LEDSnapshotOperation
    let indicators: [LEDZoneIndicator]

    var indicatorsByZone: [UInt8: UInt8] {
        indicators.reduce(into: [:]) { result, value in
            result[value.zone] = value.indicator
        }
    }

    init(inventory: NUCLEDInventory,
         indicatorsByZone: [UInt8: UInt8],
         operation: LEDSnapshotOperation = .restorePreviousMode) {
        version = Self.currentVersion
        presentMask = inventory.presentMask
        powerStateSupportedMask = inventory.powerStateSupportedMask
        self.operation = operation
        indicators = indicatorsByZone
            .map { LEDZoneIndicator(zone: $0.key, indicator: $0.value) }
            .sorted { $0.zone < $1.zone }
    }

    private enum CodingKeys: String, CodingKey {
        case version, presentMask, powerStateSupportedMask, operation, indicators
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        presentMask = try values.decode(UInt8.self, forKey: .presentMask)
        powerStateSupportedMask = try values.decodeIfPresent(UInt8.self, forKey: .powerStateSupportedMask) ?? 0
        operation = try values.decodeIfPresent(LEDSnapshotOperation.self, forKey: .operation) ?? .restorePreviousMode
        indicators = try values.decode([LEDZoneIndicator].self, forKey: .indicators)
    }
}

private enum LEDSnapshotOperation: String, Codable {
    case restorePreviousMode
    case initializePowerState
}

private struct LEDZoneIndicator: Codable {
    let zone: UInt8
    let indicator: UInt8
}

private struct LEDStateSnapshotStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load() throws -> LEDStateSnapshot? {
        let url = try snapshotURL(createDirectory: false)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            return try JSONDecoder().decode(LEDStateSnapshot.self, from: Data(contentsOf: url))
        } catch {
            throw NUCLEDHardwareError.snapshotUnreadable(error.localizedDescription)
        }
    }

    func save(_ snapshot: LEDStateSnapshot) throws {
        let url = try snapshotURL(createDirectory: true)
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw NUCLEDHardwareError.snapshotPersistence(error.localizedDescription)
        }
    }

    func remove() throws {
        let url = try snapshotURL(createDirectory: false)
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw NUCLEDHardwareError.snapshotPersistence(error.localizedDescription)
        }
    }

    private func snapshotURL(createDirectory: Bool) throws -> URL {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw NUCLEDHardwareError.snapshotPersistence("找不到用户级 Application Support 目录")
        }
        let directory = support.appendingPathComponent("NucLED", isDirectory: true)
        if createDirectory {
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            } catch {
                throw NUCLEDHardwareError.snapshotPersistence(error.localizedDescription)
            }
        }
        return directory.appendingPathComponent("led-state-snapshot.json", isDirectory: false)
    }
}

private enum NUCLEDHardwareError: LocalizedError {
    case driverUnavailable
    case driverCall(String)
    case driverProtocolMismatch
    case disableUnsupported([String])
    case powerStateUnsupported([String])
    case noRecoverableSnapshot
    case snapshotUnreadable(String)
    case snapshotPersistence(String)
    case snapshotMismatch
    case unexpectedCurrentState
    case readbackMismatch(zone: String, expected: UInt8, actual: UInt8)
    case operationFailed(String)
    case rollbackFailed(operation: String, rollback: [String])
    case rollbackSucceededButJournalCleanupFailed(operation: String, cleanup: String)
    case restoredButJournalCleanupFailed(String)
    case powerStateAppliedButJournalCleanupFailed(String)

    var errorDescription: String? {
        switch self {
        case .driverUnavailable:
            return "没有找到 NUC LED 内核驱动；尚未写入任何 LED 状态。"
        case .driverCall(let detail):
            return "NUC LED 驱动调用失败：\(detail)"
        case .driverProtocolMismatch:
            return "NUC LED 驱动协议版本或返回数据不匹配。"
        case .disableUnsupported(let zones):
            return "以下已检测灯区不支持 Disable，已拒绝部分关闭：\(zones.joined(separator: "、"))。"
        case .powerStateUnsupported(let zones):
            let affected = zones.isEmpty ? "当前所有已检测灯区" : zones.joined(separator: "、")
            return "\(affected)不支持 BIOS Power State 模式，未能首次启用 LED。"
        case .noRecoverableSnapshot:
            return "没有可恢复的灯区状态快照。若灯区在应用启动前已关闭，应用无法推测原先模式。"
        case .snapshotUnreadable(let detail):
            return "保存的 LED 恢复快照无法读取：\(detail)"
        case .snapshotPersistence(let detail):
            return "无法安全保存或清除 LED 恢复快照：\(detail)"
        case .snapshotMismatch:
            return "恢复快照与当前灯区清单不匹配；为避免错误改写，操作已停止。"
        case .unexpectedCurrentState:
            return "灯区状态已被外部改变；为避免覆盖其他设置，操作已停止。"
        case .readbackMismatch(let zone, let expected, let actual):
            return "\(zone)回读不符（期望模式 \(expected)，实际 \(actual)）。"
        case .operationFailed(let detail):
            return "LED 操作失败，已回滚到操作前状态：\(detail)"
        case .rollbackFailed(let operation, let rollback):
            return "LED 操作失败：\(operation)。回滚也未能完全确认：\(rollback.joined(separator: "；"))。恢复快照已保留。"
        case .rollbackSucceededButJournalCleanupFailed(let operation, let cleanup):
            return "LED 操作失败且已回滚：\(operation)。清除回滚日志失败：\(cleanup)"
        case .restoredButJournalCleanupFailed(let detail):
            return "灯区已恢复并回读确认，但清除恢复快照失败：\(detail)"
        case .powerStateAppliedButJournalCleanupFailed(let detail):
            return "支持 Power State 的灯区已选择此 BIOS 策略并回读确认，但清除初始化日志失败：\(detail)"
        }
    }
}

/// Fixed binary protocol implemented by `Driver/NUCLEDDriver`.
/// Selector 0: no input; output `{version, presentMask, disableMask, powerStateMask}`.
/// Selector 1: input `{zone, 0, 0, 0}`; output `{indicator, 0, 0, 0}`.
/// Selector 2: input `{zone, indicator, 0, 0}`; no output.
struct NUCLEDDriverClient: Sendable {
    private static let serviceName = "NUCLEDDriver"

    func readInventory() throws -> NUCLEDInventory {
        let output = try call(selector: 0, input: [], outputSize: 4)
        guard output[0] == 1 else {
            throw NUCLEDHardwareError.driverProtocolMismatch
        }
        return NUCLEDInventory(
            presentMask: output[1],
            disableSupportedMask: output[2],
            powerStateSupportedMask: output[3]
        )
    }

    func readIndicator(zone: UInt8) throws -> UInt8 {
        let output = try call(selector: 1, input: [zone, 0, 0, 0], outputSize: 4)
        guard output[0] <= NUCLEDIndicator.disabled,
              output[1] == 0, output[2] == 0, output[3] == 0 else {
            throw NUCLEDHardwareError.driverProtocolMismatch
        }
        return output[0]
    }

    func setIndicator(zone: UInt8, indicator: UInt8) throws {
        _ = try call(selector: 2, input: [zone, indicator, 0, 0], outputSize: 0)
    }

    private func call(selector: UInt32, input: [UInt8], outputSize: Int) throws -> [UInt8] {
        let matching = IOServiceMatching(Self.serviceName)
        guard let matching else { throw NUCLEDHardwareError.driverUnavailable }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { throw NUCLEDHardwareError.driverUnavailable }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = IO_OBJECT_NULL
        let openStatus = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard openStatus == KERN_SUCCESS else {
            throw NUCLEDHardwareError.driverCall("IOServiceOpen 返回 0x\(String(openStatus, radix: 16))")
        }
        defer { IOServiceClose(connection) }

        var output = [UInt8](repeating: 0, count: outputSize)
        var actualOutputSize = outputSize
        let status: kern_return_t = input.withUnsafeBytes { inputBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                IOConnectCallStructMethod(
                    connection,
                    selector,
                    input.isEmpty ? nil : inputBuffer.baseAddress,
                    inputBuffer.count,
                    outputSize == 0 ? nil : outputBuffer.baseAddress,
                    &actualOutputSize
                )
            }
        }
        guard status == KERN_SUCCESS else {
            throw NUCLEDHardwareError.driverCall("IOConnectCallStructMethod(selector \(selector)) 返回 0x\(String(status, radix: 16))")
        }
        guard actualOutputSize == outputSize else {
            throw NUCLEDHardwareError.driverProtocolMismatch
        }
        return output
    }
}
