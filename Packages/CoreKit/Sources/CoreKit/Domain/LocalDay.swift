import Foundation

extension Calendar {
    /// The one calendar every CoreKit date calculation uses: Gregorian, Europe/London, weeks start on Monday (A1).
    public static let lockIn: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_GB")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()
}

/// A calendar day in the device time zone, stored and encoded as `"YYYY-MM-DD"`.
public struct LocalDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Builds a day from its parts. Out-of-range parts are normalised (e.g. 31 Feb → 3 Mar).
    public init(year: Int, month: Int, day: Int) {
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        let date = Calendar.lockIn.date(from: components)!
        let parts = Calendar.lockIn.dateComponents([.year, .month, .day], from: date)
        self.year = parts.year!
        self.month = parts.month!
        self.day = parts.day!
    }

    /// Parses `"YYYY-MM-DD"`. Returns nil for any other shape or an impossible date.
    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        let normalised = LocalDay(year: y, month: m, day: d)
        guard normalised.year == y, normalised.month == m, normalised.day == d else { return nil }
        self = normalised
    }

    /// The calendar day that contains `date` (no 04:00 rule; see `HabitEngine.logicalDay`).
    public init(_ date: Date) {
        let parts = Calendar.lockIn.dateComponents([.year, .month, .day], from: date)
        self.year = parts.year!
        self.month = parts.month!
        self.day = parts.day!
    }

    public static var today: LocalDay { LocalDay(Date()) }

    public var string: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var description: String { string }

    /// The instant at `minutes` after local midnight on this day.
    public func date(minutes: Int = 0) -> Date {
        // Wall-clock arithmetic: adding minutes to midnight would be off by an hour on the two clock-change days.
        // Minutes outside 0..<1440 roll into neighbouring days (1440 = the next midnight).
        var hours = minutes / 60
        var remainder = minutes % 60
        if remainder < 0 { remainder += 60; hours -= 1 }
        let components = DateComponents(year: year, month: month, day: day, hour: hours, minute: remainder)
        return Calendar.lockIn.date(from: components)!
    }

    public func adding(days: Int) -> LocalDay {
        LocalDay(year: year, month: month, day: day + days)
    }

    /// Whole days from `self` to `other` (positive when `other` is later).
    public func days(to other: LocalDay) -> Int {
        Calendar.lockIn.dateComponents([.day], from: date(minutes: 720), to: other.date(minutes: 720)).day!
    }

    /// ISO weekday: 1 = Monday … 7 = Sunday.
    public var weekday: Int {
        let gregorian = Calendar.lockIn.component(.weekday, from: date(minutes: 720)) // 1 = Sunday
        return gregorian == 1 ? 7 : gregorian - 1
    }

    /// The Monday of this day's week.
    public var weekStart: LocalDay { adding(days: 1 - weekday) }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = LocalDay(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "\(raw) is not YYYY-MM-DD")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}

/// A Monday-to-Sunday week.
public struct Week: Hashable, Codable, Sendable {
    /// Always a Monday.
    public let start: LocalDay

    public init(start: LocalDay) { self.start = start.weekStart }
    public init(containing day: LocalDay) { self.start = day.weekStart }

    public var end: LocalDay { start.adding(days: 6) }
    public var days: [LocalDay] { (0..<7).map { start.adding(days: $0) } }
    public var previous: Week { Week(start: start.adding(days: -7)) }
    public var next: Week { Week(start: start.adding(days: 7)) }
    public func contains(_ day: LocalDay) -> Bool { day >= start && day <= end }
    /// Monday 00:00 to the following Monday 00:00.
    public var interval: DateInterval { DateInterval(start: start.date(), end: start.adding(days: 7).date()) }
}

/// Helpers for `Int` minutes after midnight.
public enum TimeOfDay {
    /// `450` → `"07:30"`.
    public static func format(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// `"07:30"` → `450`. Nil unless the text is exactly `HH:mm` with 00–23 and 00–59.
    public static func parse(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    /// Minutes after local midnight for `date`.
    public static func minutes(of date: Date) -> Int {
        let parts = Calendar.lockIn.dateComponents([.hour, .minute], from: date)
        return parts.hour! * 60 + parts.minute!
    }
}
