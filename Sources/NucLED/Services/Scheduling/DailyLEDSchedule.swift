import Foundation

public enum ScheduleValidationError: Error, Equatable {
    case invalidHour(Int)
    case invalidMinute(Int)
    case equalTimes
}

public enum ScheduleTransitionKind: String, Codable, Equatable, Sendable {
    case turnOn
    case turnOff
}

public struct ScheduleTransition: Equatable, Sendable {
    public let date: Date
    public let kind: ScheduleTransitionKind

    public init(date: Date, kind: ScheduleTransitionKind) {
        self.date = date
        self.kind = kind
    }
}

/// A repeating daily LED schedule based on the computer's local wall clock.
public struct DailyLEDSchedule: Codable, Equatable, Sendable {
    public static let storageKey = "com.nucled.daily-led-schedule"

    public let on: LocalTime
    public let off: LocalTime

    public init(on: LocalTime, off: LocalTime) throws {
        guard on != off else {
            throw ScheduleValidationError.equalTimes
        }
        self.on = on
        self.off = off
    }

    /// Returns whether the LED should be on at `date` in the supplied calendar.
    /// The on time is inclusive and the off time is exclusive.
    public func targetState(
        at date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else {
            return false
        }
        let minuteOfDay = hour * 60 + minute

        if on < off {
            return on.minutesSinceMidnight <= minuteOfDay && minuteOfDay < off.minutesSinceMidnight
        }

        // An on time later than the off time means the active interval crosses midnight.
        return minuteOfDay >= on.minutesSinceMidnight || minuteOfDay < off.minutesSinceMidnight
    }

    /// Returns the next instant at which the desired LED state changes.
    ///
    /// This walks real calendar-minute boundaries, so repeated local times at the
    /// autumn DST fold are handled as they occur. A short bounded search is enough
    /// because a valid daily schedule changes state at least once every day.
    public func nextTransition(
        after date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> ScheduleTransition? {
        var cursor = date
        var state = targetState(at: cursor, calendar: calendar)

        // A daily schedule must transition within a few days. The extra days cover
        // a spring-forward day on which a configured wall time does not exist.
        for _ in 0..<(4 * 24 * 60) {
            guard let minute = calendar.dateInterval(of: .minute, for: cursor) else {
                return nil
            }
            let boundary = minute.end
            guard boundary > cursor else {
                return nil
            }

            let nextState = targetState(at: boundary, calendar: calendar)
            if nextState != state {
                return ScheduleTransition(
                    date: boundary,
                    kind: nextState ? .turnOn : .turnOff
                )
            }

            state = nextState
            cursor = boundary
        }

        return nil
    }

    /// Persists this schedule as encoded data in UserDefaults.
    public func save(
        to defaults: UserDefaults = .standard,
        key: String = DailyLEDSchedule.storageKey
    ) throws {
        defaults.set(try JSONEncoder().encode(self), forKey: key)
    }

    /// Loads a previously saved schedule, or returns `nil` if none has been saved.
    public static func load(
        from defaults: UserDefaults = .standard,
        key: String = DailyLEDSchedule.storageKey
    ) throws -> DailyLEDSchedule? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try JSONDecoder().decode(DailyLEDSchedule.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case on
        case off
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let on = try container.decode(LocalTime.self, forKey: .on)
        let off = try container.decode(LocalTime.self, forKey: .off)
        do {
            try self.init(on: on, off: off)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .off,
                in: container,
                debugDescription: "The daily LED on and off times must differ."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(on, forKey: .on)
        try container.encode(off, forKey: .off)
    }
}
