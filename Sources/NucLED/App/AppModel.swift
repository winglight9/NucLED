import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var isLEDEnabled: Bool?
    @Published private(set) var isScheduleEnabled: Bool
    @Published private(set) var onTime: Date
    @Published private(set) var offTime: Date
    @Published private(set) var statusText: String
    @Published private(set) var nextActionText: String
    @Published private(set) var isHardwareBusy = false
    @Published private(set) var canControlLED = false
    @Published private(set) var isLoginItemEnabled: Bool
    @Published private(set) var loginItemStatusText: String?

    private let hardware: any LEDHardwareControlling
    private let defaults: UserDefaults
    private let loginItemRegistrar = LoginItemRegistrar()
    private var subscriptions = Set<AnyCancellable>()
    private var pendingScheduleTarget: Bool?

    private lazy var scheduleCoordinator = ScheduleCoordinator(defaults: defaults) { [weak self] target in
        Task { @MainActor [weak self] in
            await self?.applyScheduledTarget(target)
        }
    }

    private enum PreferenceKey {
        static let onHour = "com.nucled.on-time-hour"
        static let onMinute = "com.nucled.on-time-minute"
        static let offHour = "com.nucled.off-time-hour"
        static let offMinute = "com.nucled.off-time-minute"
        static let loginItemEnabled = "com.nucled.login-item-enabled"
    }

    private static let defaultOnTime = try! LocalTime(hour: 9, minute: 0)
    private static let defaultOffTime = try! LocalTime(hour: 23, minute: 30)

    init(
        hardware: any LEDHardwareControlling = NucLEDHardwareController(),
        defaults: UserDefaults = .standard
    ) {
        self.hardware = hardware
        self.defaults = defaults
        self.isLEDEnabled = nil
        self.isScheduleEnabled = false
        self.isLoginItemEnabled = false
        self.statusText = "正在检查 LED 控制接口…"
        self.nextActionText = "定时已关闭"

        let savedSchedule = try? DailyLEDSchedule.load(from: defaults)
        let savedPlanIsEnabled = defaults.bool(forKey: ScheduleCoordinator.enabledStorageKey)
        let activeSchedule = savedPlanIsEnabled ? savedSchedule : nil
        let initialOnTime = Self.loadTime(
            defaults,
            hourKey: PreferenceKey.onHour,
            minuteKey: PreferenceKey.onMinute,
            fallback: activeSchedule?.on ?? savedSchedule?.on ?? Self.defaultOnTime
        )
        let initialOffTime = Self.loadTime(
            defaults,
            hourKey: PreferenceKey.offHour,
            minuteKey: PreferenceKey.offMinute,
            fallback: activeSchedule?.off ?? savedSchedule?.off ?? Self.defaultOffTime
        )
        let selectedOnTime = activeSchedule?.on ?? initialOnTime
        let selectedOffTime = activeSchedule?.off ?? initialOffTime
        self.onTime = Self.date(for: selectedOnTime)
        self.offTime = Self.date(for: selectedOffTime)

        Self.save(selectedOnTime, defaults: defaults, hourKey: PreferenceKey.onHour, minuteKey: PreferenceKey.onMinute)
        Self.save(selectedOffTime, defaults: defaults, hourKey: PreferenceKey.offHour, minuteKey: PreferenceKey.offMinute)

        // Older versions enabled login launch implicitly when a daily plan was
        // turned on. Preserve an existing system registration as the initial
        // explicit preference, then let the new toggle own future changes.
        let savedLoginPreference = defaults.object(forKey: PreferenceKey.loginItemEnabled) as? Bool
        let initialLoginPreference = savedLoginPreference ?? loginItemRegistrar.isEnabledOrPendingApproval
        isLoginItemEnabled = initialLoginPreference
        defaults.set(initialLoginPreference, forKey: PreferenceKey.loginItemEnabled)
        let loginUpdate = loginItemRegistrar.setEnabled(initialLoginPreference)
        isLoginItemEnabled = loginUpdate.isEnabled
        loginItemStatusText = loginUpdate.statusText
        defaults.set(loginUpdate.isEnabled, forKey: PreferenceKey.loginItemEnabled)

        isScheduleEnabled = scheduleCoordinator.isEnabled
        subscribeToScheduleChanges()
        scheduleCoordinator.start()
        updateNextActionText()
        // An enabled saved plan performs the startup state check through the
        // coordinator callback. Otherwise read status for the manual switch.
        if !scheduleCoordinator.isEnabled {
            Task { @MainActor [weak self] in
                await self?.refreshHardwareState()
            }
        }
    }

    func toggleLED() {
        guard isLEDEnabled != nil, canControlLED, !isHardwareBusy else { return }
        Task { @MainActor [weak self] in
            await self?.performManualToggle()
        }
    }

    func setScheduleEnabled(_ enabled: Bool) {
        guard enabled != scheduleCoordinator.isEnabled else { return }

        if enabled {
            guard let on = localTime(from: onTime), let off = localTime(from: offTime), on != off else {
                nextActionText = "开启和关闭时间不能相同"
                isScheduleEnabled = false
                return
            }

            do {
                try scheduleCoordinator.setSchedule(on: on, off: off)
                try scheduleCoordinator.setEnabled(true)
                isScheduleEnabled = scheduleCoordinator.isEnabled
                updateNextActionText()
            } catch {
                isScheduleEnabled = scheduleCoordinator.isEnabled
                nextActionText = "无法启用计划：\(error.localizedDescription)"
            }
        } else {
            do {
                try scheduleCoordinator.setEnabled(false)
            } catch {
                nextActionText = "无法关闭计划：\(error.localizedDescription)"
            }
            isScheduleEnabled = scheduleCoordinator.isEnabled
            updateNextActionText()
        }
    }

    func setOnTime(_ date: Date) {
        onTime = date
        updateScheduleTimes()
    }

    func setOffTime(_ date: Date) {
        offTime = date
        updateScheduleTimes()
    }

    func setLoginItemEnabled(_ enabled: Bool) {
        guard enabled != isLoginItemEnabled else { return }

        let result = loginItemRegistrar.setEnabled(enabled)
        isLoginItemEnabled = result.isEnabled
        loginItemStatusText = result.statusText
        defaults.set(result.isEnabled, forKey: PreferenceKey.loginItemEnabled)
    }

    func quit() {
        statusText = "应用已退出，定时计划暂停；重新打开后继续"
        scheduleCoordinator.stop()
        NSApplication.shared.terminate(nil)
    }

    private func subscribeToScheduleChanges() {
        scheduleCoordinator.$nextTransition
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateNextActionText()
                }
            }
            .store(in: &subscriptions)

        scheduleCoordinator.$isEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                Task { @MainActor [weak self] in
                    self?.isScheduleEnabled = isEnabled
                    self?.updateNextActionText()
                }
            }
            .store(in: &subscriptions)
    }

    private func updateScheduleTimes() {
        guard let on = localTime(from: onTime), let off = localTime(from: offTime) else { return }

        do {
            try scheduleCoordinator.setSchedule(on: on, off: off)
            persistDisplayedTimes(on: on, off: off)
            isScheduleEnabled = scheduleCoordinator.isEnabled
            updateNextActionText()
        } catch ScheduleValidationError.equalTimes {
            let wasEnabled = scheduleCoordinator.isEnabled
            if scheduleCoordinator.isEnabled {
                try? scheduleCoordinator.setEnabled(false)
                isScheduleEnabled = scheduleCoordinator.isEnabled
            }
            persistDisplayedTimes(on: on, off: off)
            if wasEnabled {
                nextActionText = "开关时间不能相同，计划已暂停"
            } else {
                updateNextActionText()
            }
        } catch {
            nextActionText = "无法保存计划：\(error.localizedDescription)"
        }
    }

    private func updateNextActionText() {
        guard scheduleCoordinator.isEnabled else {
            nextActionText = "定时已关闭"
            return
        }
        guard let transition = scheduleCoordinator.nextTransition else {
            nextActionText = "无法计算下一次动作"
            return
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.calendar = Calendar.autoupdatingCurrent
        formatter.timeZone = TimeZone.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"

        let calendar = Calendar.autoupdatingCurrent
        let dateLabel: String
        if calendar.isDateInToday(transition.date) {
            dateLabel = "今天 \(formatter.string(from: transition.date))"
        } else if calendar.isDateInTomorrow(transition.date) {
            dateLabel = "明天 \(formatter.string(from: transition.date))"
        } else {
            formatter.dateFormat = "M月d日 HH:mm"
            dateLabel = formatter.string(from: transition.date)
        }

        let action = transition.kind == .turnOn ? "将开启" : "将关闭"
        nextActionText = "\(dateLabel) \(action) LED"
    }

    private func refreshHardwareState() async {
        guard !isHardwareBusy else { return }
        isHardwareBusy = true
        defer { finishHardwareOperation() }

        do {
            let enabled = try await hardware.readLEDEnabled()
            isLEDEnabled = enabled
            canControlLED = true
            statusText = "控制就绪 · LED 模式已\(enabled ? "启用" : "停用")"
        } catch {
            isLEDEnabled = nil
            canControlLED = false
            statusText = "LED 控制不可用：\(error.localizedDescription)"
        }
    }

    private func performManualToggle() async {
        guard !isHardwareBusy else { return }
        isHardwareBusy = true
        defer { finishHardwareOperation() }

        do {
            // Re-read immediately before toggling so external state changes do
            // not make the switch issue the opposite of the user's intent.
            let current = try await hardware.readLEDEnabled()
            isLEDEnabled = current
            canControlLED = true
            let requested = !current
            try await hardware.setLEDEnabled(requested)
            let actual = try await hardware.readLEDEnabled()
            isLEDEnabled = actual
            if actual == requested {
                statusText = "控制就绪 · LED 模式已\(actual ? "启用" : "停用")"
            } else {
                canControlLED = false
                statusText = "控制未生效 · 回读状态仍为 LED 模式已\(actual ? "启用" : "停用")"
            }
        } catch {
            let actual = try? await hardware.readLEDEnabled()
            isLEDEnabled = actual
            canControlLED = actual != nil
            statusText = "LED 控制失败：\(error.localizedDescription)"
        }
    }

    private func applyScheduledTarget(_ target: Bool) async {
        guard scheduleCoordinator.isEnabled else { return }
        guard !isHardwareBusy else {
            pendingScheduleTarget = target
            return
        }

        isHardwareBusy = true
        defer { finishHardwareOperation() }

        do {
            let actual = try await hardware.readLEDEnabled()
            isLEDEnabled = actual
            canControlLED = true
            statusText = "控制就绪 · LED 模式已\(actual ? "启用" : "停用")"

            guard scheduleCoordinator.isEnabled, actual != target else { return }
            try await hardware.setLEDEnabled(target)
            let verified = try await hardware.readLEDEnabled()
            isLEDEnabled = verified
            if verified == target {
                statusText = "计划已执行 · LED 模式已\(verified ? "启用" : "停用")"
            } else {
                canControlLED = false
                statusText = "计划控制未生效 · 回读状态为 LED 模式已\(verified ? "启用" : "停用")"
            }
        } catch {
            let actual = try? await hardware.readLEDEnabled()
            isLEDEnabled = actual
            canControlLED = actual != nil
            statusText = "计划执行失败：\(error.localizedDescription)"
        }
    }

    private func finishHardwareOperation() {
        isHardwareBusy = false
        guard let target = pendingScheduleTarget else { return }
        pendingScheduleTarget = nil
        Task { @MainActor [weak self] in
            await self?.applyScheduledTarget(target)
        }
    }

    private func localTime(from date: Date) -> LocalTime? {
        let parts = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
        guard let hour = parts.hour, let minute = parts.minute else { return nil }
        return try? LocalTime(hour: hour, minute: minute)
    }

    private func persistDisplayedTimes(on: LocalTime, off: LocalTime) {
        Self.save(on, defaults: defaults, hourKey: PreferenceKey.onHour, minuteKey: PreferenceKey.onMinute)
        Self.save(off, defaults: defaults, hourKey: PreferenceKey.offHour, minuteKey: PreferenceKey.offMinute)
    }

    private static func loadTime(
        _ defaults: UserDefaults,
        hourKey: String,
        minuteKey: String,
        fallback: LocalTime
    ) -> LocalTime {
        let hour = defaults.object(forKey: hourKey) as? Int ?? fallback.hour
        let minute = defaults.object(forKey: minuteKey) as? Int ?? fallback.minute
        return (try? LocalTime(hour: hour, minute: minute)) ?? fallback
    }

    private static func save(
        _ time: LocalTime,
        defaults: UserDefaults,
        hourKey: String,
        minuteKey: String
    ) {
        defaults.set(time.hour, forKey: hourKey)
        defaults.set(time.minute, forKey: minuteKey)
    }

    private static func date(for time: LocalTime) -> Date {
        var components = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: Date())
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        return Calendar.autoupdatingCurrent.date(from: components) ?? Date()
    }
}
