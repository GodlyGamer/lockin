import Foundation

/// Locale-independent text helpers shared by the engines (internal). Day and month names are fixed tables so output
/// is identical on Linux and iOS and never depends on ICU data ("Sep", not "Sept").
enum CoreFormat {
    static let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "Mon"
    static func weekdayName(_ day: LocalDay) -> String { weekdayNames[day.weekday - 1] }

    /// "19 Oct"
    static func shortDayMonth(_ day: LocalDay) -> String { "\(day.day) \(monthNames[day.month - 1])" }

    /// "Mon 19 Oct"
    static func dayMonth(_ day: LocalDay) -> String { "\(weekdayName(day)) \(shortDayMonth(day))" }

    /// "Mon 19 Oct 2026"
    static func dayMonthYear(_ day: LocalDay) -> String { "\(dayMonth(day)) \(day.year)" }

    /// "07:30" for the wall-clock time of `date`.
    static func time(_ date: Date) -> String { TimeOfDay.format(TimeOfDay.minutes(of: date)) }

    /// 86 → "86", 78.5 → "78.5", 0.1 → "0.1" (no locale, no trailing ".0").
    static func number(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
        return String(value)
    }

    /// "Lift" → "Lift."; leaves titles that already end in . ? or !.
    static func withFullStop(_ title: String) -> String {
        guard let last = title.last, !".?!".contains(last) else { return title }
        return title + "."
    }

    /// Sorted, de-duplicated values.
    static func sortedUnique(_ values: [Int]) -> [Int] { Array(Set(values)).sorted() }

    /// Minutes between two dates, rounded to the nearest minute.
    static func minutes(from start: Date, to end: Date) -> Int {
        Int((end.timeIntervalSince(start) / 60).rounded())
    }

    /// Whether two half-open intervals overlap (touching edges do not).
    static func overlaps(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> Bool {
        aStart < bEnd && aEnd > bStart
    }

    /// Merges overlapping or touching intervals; the result is sorted.
    static func merged(_ intervals: [(start: Date, end: Date)]) -> [(start: Date, end: Date)] {
        var result: [(start: Date, end: Date)] = []
        for interval in intervals.filter({ $0.start < $0.end }).sorted(by: { $0.start < $1.start }) {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1].end = max(last.end, interval.end)
            } else {
                result.append(interval)
            }
        }
        return result
    }
}
