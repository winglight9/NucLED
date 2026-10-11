import Foundation

/// A wall-clock time with minute precision.
public struct LocalTime: Codable, Equatable, Comparable, Sendable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) throws {
        guard (0..<24).contains(hour) else {
            throw ScheduleValidationError.invalidHour(hour)
        }
        guard (0..<60).contains(minute) else {
            throw ScheduleValidationError.invalidMinute(minute)
        }

        self.hour = hour
        self.minute = minute
    }

    public static func < (lhs: LocalTime, rhs: LocalTime) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    var minutesSinceMidnight: Int { hour * 60 + minute }

    private enum CodingKeys: String, CodingKey {
        case hour
        case minute
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hour = try container.decode(Int.self, forKey: .hour)
        let minute = try container.decode(Int.self, forKey: .minute)
        do {
            try self.init(hour: hour, minute: minute)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .hour,
                in: container,
                debugDescription: "Invalid local time: \(hour):\(minute)."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hour, forKey: .hour)
        try container.encode(minute, forKey: .minute)
    }
}
