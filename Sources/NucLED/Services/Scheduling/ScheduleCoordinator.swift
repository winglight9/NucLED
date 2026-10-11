import AppKit
import Combine
import Foundation

public enum ScheduleCoordinatorError: Error, Equatable {
    case missingSchedule
}

/// Runs a daily schedule and reports the desired LED state through an injected action.
/// The coordinator owns timing and lifecycle only; hardware access stays with its caller.
@MainActor
public final class ScheduleCoordinator: NSObject, ObservableObject {
    public static let enabledStorageKey = "com.nucled.daily-led-schedule-enabled"

    @Published public private(set) var schedule: DailyLEDSchedule?
    @Published public private(set) var isEnabled: Bool
    @Published public private(set) var nextTransition: ScheduleTransition?

    private let defaults: UserDefaults
    private let applyTargetState: @MainActor (Bool) -> Void
    private var timer: Timer?
    private var isStarted = false

    public init(
        defaults: UserDefaults = .standard,
        applyTargetState: @escaping @MainActor (Bool) -> Void
    ) {
        self.defaults = defaults
        self.applyTargetState = applyTargetState
        self.schedule = try? DailyLEDSchedule.load(from: defaults)
        self.isEnabled = defaults.bool(forKey: Self.enabledStorageKey)
        self.nextTransition = nil
        super.init()
    }

    /// Starts lifecycle observation. An enabled schedule is reconciled immediately.
    public func start() {
        guard !isStarted else {
            reconcileNow()
            return
        }

        isStarted = true
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClockOrCalendarChange(_:)),
            name: .NSSystemClockDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClockOrCalendarChange(_:)),
            name: .NSSystemTimeZoneDidChange,
            object: nil
        )

        if isEnabled, schedule == nil {
            // A persisted enabled bit without a valid schedule cannot be executed.
            isEnabled = false
            defaults.set(false, forKey: Self.enabledStorageKey)
        }
        reconcileNow()
    }

    /// Stops the timer and lifecycle observers without changing the persisted setting.
    public func stop() {
        timer?.invalidate()
        timer = nil
        nextTransition = nil
        guard isStarted else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        isStarted = false
    }

    /// Enables or disables automatic actions. Enabling requires a configured schedule.
    public func setEnabled(_ enabled: Bool) throws {
        if enabled, schedule == nil {
            throw ScheduleCoordinatorError.missingSchedule
        }

        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledStorageKey)

        if enabled {
            if !isStarted {
                start()
            } else {
                reconcileNow()
            }
        } else {
            timer?.invalidate()
            timer = nil
            nextTransition = nil
        }
    }

    /// Replaces and persists the daily on/off times. Equal times are rejected.
    public func setSchedule(on: LocalTime, off: LocalTime) throws {
        let newSchedule = try DailyLEDSchedule(on: on, off: off)
        try newSchedule.save(to: defaults)
        schedule = newSchedule

        if isEnabled {
            if !isStarted {
                start()
            } else {
                reconcileNow()
            }
        }
    }

    /// Applies today's current target state and schedules the next transition.
    /// Called at startup, after wake, and whenever the clock or time zone changes.
    public func reconcileNow() {
        timer?.invalidate()
        timer = nil
        nextTransition = nil

        guard isEnabled, let schedule else { return }

        let now = Date()
        applyTargetState(schedule.targetState(at: now))
        guard let transition = schedule.nextTransition(after: now) else { return }

        nextTransition = transition
        let interval = max(0.05, transition.date.timeIntervalSinceNow)
        let nextTimer = Timer(
            timeInterval: interval,
            target: self,
            selector: #selector(handleScheduledTransition),
            userInfo: nil,
            repeats: false
        )
        timer = nextTimer
        RunLoop.main.add(nextTimer, forMode: .common)
    }

    @objc private func handleScheduledTransition() {
        timer = nil
        reconcileNow()
    }

    @objc private func handleWake(_ notification: Notification) {
        reconcileNow()
    }

    @objc private func handleClockOrCalendarChange(_ notification: Notification) {
        reconcileNow()
    }
}
