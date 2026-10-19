import Foundation
import CoreKit

/// Display formats used across features (en-GB, Europe/London). Titles get their full stop here, never in data (§8.2).
enum LockInFormat {
    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = .lockIn
        formatter.timeZone = Calendar.lockIn.timeZone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = format
        return formatter
    }

    private static let dayMonthFormatter = formatter("EEE d MMM")
    private static let shortDayMonthFormatter = formatter("d MMM")
    private static let timeFormatter = formatter("HH:mm")
    private static let dayMonthTimeFormatter = formatter("EEE d MMM HH:mm")

    /// "Mon 19 Oct"
    static func dayMonth(_ day: LocalDay) -> String { dayMonthFormatter.string(from: day.date(minutes: 720)) }
    /// "19 Oct"
    static func shortDayMonth(_ day: LocalDay) -> String { shortDayMonthFormatter.string(from: day.date(minutes: 720)) }
    /// "07:30" from minutes after midnight.
    static func time(_ minutes: Int) -> String { TimeOfDay.format(minutes) }
    /// "07:30" from a date.
    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }
    /// "Mon 19 Oct 07:30"
    static func dayMonthTime(_ date: Date) -> String { dayMonthTimeFormatter.string(from: date) }

    /// "Today", "Yesterday" or "Mon 19 Oct" relative to `today`.
    static func relativeDay(_ day: LocalDay, today: LocalDay) -> String {
        if day == today { return "Today" }
        if day == today.adding(days: -1) { return "Yesterday" }
        return dayMonth(day)
    }

    /// Adds the title-voice full stop: "Goals" → "Goals.", "10% body fat" → "10% body fat.". Leaves "?" / "!" / "." endings.
    static func titled(_ text: String) -> String {
        guard let last = text.last, !".?!".contains(last) else { return text }
        return text + "."
    }

    /// Habit frequency badge: "daily", "M W F", "5/wk".
    static func frequency(_ frequency: Frequency) -> String {
        switch frequency {
        case .daily: return "daily"
        case .perWeek(let n): return "\(n)/wk"
        case .weekdays(let days):
            let letters = ["M", "T", "W", "T", "F", "S", "S"]
            return days.sorted().filter { (1...7).contains($0) }.map { letters[$0 - 1] }.joined(separator: " ")
        }
    }

    /// "M" … "S" for ISO weekdays 1…7.
    static let weekdayLetters = ["M", "T", "W", "T", "F", "S", "S"]
    /// "Mon" … "Sun" for ISO weekdays 1…7.
    static let weekdayShortNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
}
