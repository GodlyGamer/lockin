import Foundation
import CoreKit

// Shared pieces of the Calendar tab: modes, metrics, item model, lane packing and formats.
// Everything here is prefixed `Cal` (one-module rule, BUILD_PLAN §0).

/// Day or Week, switched by the segmented control in the navigation bar (DESIGN.md §5.1).
enum CalMode: Hashable {
    case day, week
}

enum CalMetrics {
    /// The grid shows 06:00 to 24:00.
    static let firstHour = 6
    static let lastHour = 24
    static let hourCount = lastHour - firstHour
    /// Week view: 48 pt per hour. Day view: 64 pt per hour.
    static let weekHourHeight: CGFloat = 48
    static let dayHourHeight: CGFloat = 64
    static let gutterWidth: CGFloat = 40
    /// Timed habit chips are 20 pt tall.
    static let chipHeight: CGFloat = 20
    static let minBlockHeight: CGFloat = 18
}

enum CalFormat {
    /// "06:00"
    static func hourLabel(_ hour: Int) -> String {
        hour < 10 ? "0\(hour):00" : "\(hour):00"
    }

    /// "17:00–18:30"
    static func timeRange(_ start: Date, _ end: Date) -> String {
        "\(LockInFormat.time(start))–\(LockInFormat.time(end))"
    }

    /// "1 h 30 min"
    static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        if rest == 0 { return "\(hours) h" }
        return "\(hours) h \(rest) min"
    }

    /// The same instant with the seconds dropped.
    static func wholeMinute(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }
}

/// One thing drawn in a day column.
struct CalItem: Identifiable {
    enum Kind {
        case event(ExternalEvent)
        case block(CalendarBlock)
        case habit(Habit, LocalDay)
    }

    let id: String
    let kind: Kind
    /// Clipped to the visible 06:00 to 24:00 window of its day.
    let start: Date
    let end: Date

    var minHeight: CGFloat {
        switch kind {
        case .habit: CalMetrics.chipHeight
        case .event, .block: CalMetrics.minBlockHeight
        }
    }
}

/// An item with its position inside a day column.
struct CalPlacedItem: Identifiable {
    let item: CalItem
    let lane: Int
    let laneCount: Int
    let top: CGFloat
    let height: CGFloat

    var id: String { item.id }
}

enum CalLayout {
    /// Timed items for one day: external events, goal blocks (not cancelled) and timed habit chips.
    static func items(for day: LocalDay, snapshot: StoreSnapshot, events: [ExternalEvent]) -> [CalItem] {
        let windowStart = day.date(minutes: CalMetrics.firstHour * 60)
        let windowEnd = day.adding(days: 1).date()
        var result: [CalItem] = []

        for event in events where !event.isAllDay {
            let end = max(event.end, event.start.addingTimeInterval(15 * 60))
            guard event.start < windowEnd, end > windowStart else { continue }
            result.append(CalItem(id: "e|\(event.id)|\(day.string)", kind: .event(event),
                                  start: max(event.start, windowStart), end: min(end, windowEnd)))
        }

        for block in snapshot.blocks where block.status != .cancelled {
            let end = max(block.end, block.start.addingTimeInterval(15 * 60))
            guard block.start < windowEnd, end > windowStart else { continue }
            result.append(CalItem(id: "b|\(block.id.uuidString)|\(day.string)", kind: .block(block),
                                  start: max(block.start, windowStart), end: min(end, windowEnd)))
        }

        for habit in snapshot.habits where !habit.isArchived {
            guard let minutes = habit.reminderTime else { continue }
            guard HabitEngine.isDue(habit, on: day, logs: snapshot.logs) else { continue }
            if case .perWeek = habit.frequency, !habit.preferredWeekdays.contains(day.weekday) { continue }
            let clamped = min(max(minutes, CalMetrics.firstHour * 60), CalMetrics.lastHour * 60 - 25)
            let start = day.date(minutes: clamped)
            result.append(CalItem(id: "h|\(habit.id.uuidString)|\(day.string)", kind: .habit(habit, day),
                                  start: start, end: start.addingTimeInterval(25 * 60)))
        }
        return result
    }

    /// All-day events touching `day`.
    static func allDayEvents(on day: LocalDay, in events: [ExternalEvent]) -> [ExternalEvent] {
        let dayStart = day.date()
        let dayEnd = day.adding(days: 1).date()
        return events.filter { $0.isAllDay && $0.start < dayEnd && $0.end > dayStart }
    }

    /// Side-by-side lanes for overlapping items (like Apple Calendar).
    static func place(_ items: [CalItem], day: LocalDay, hourHeight: CGFloat) -> [CalPlacedItem] {
        struct Raw {
            var item: CalItem
            var top: CGFloat
            var bottom: CGFloat
        }

        let origin = day.date(minutes: CalMetrics.firstHour * 60)
        let gridHeight = CGFloat(CalMetrics.hourCount) * hourHeight

        var raws: [Raw] = items.map { item in
            let rawTop = CGFloat(item.start.timeIntervalSince(origin) / 3600) * hourHeight
            let rawHeight = CGFloat(item.end.timeIntervalSince(item.start) / 3600) * hourHeight
            let height = max(rawHeight, item.minHeight)
            let top = min(max(0, rawTop), max(0, gridHeight - item.minHeight))
            return Raw(item: item, top: top, bottom: min(top + height, gridHeight))
        }
        raws.sort { lhs, rhs in
            lhs.top == rhs.top ? lhs.bottom > rhs.bottom : lhs.top < rhs.top
        }

        var result: [CalPlacedItem] = []
        var cluster: [(raw: Raw, lane: Int)] = []
        var laneEnds: [CGFloat] = []
        var clusterEnd: CGFloat = -.infinity

        func flush() {
            let laneCount = max(1, laneEnds.count)
            for entry in cluster {
                result.append(CalPlacedItem(item: entry.raw.item, lane: entry.lane, laneCount: laneCount,
                                            top: entry.raw.top, height: entry.raw.bottom - entry.raw.top))
            }
            cluster.removeAll()
            laneEnds.removeAll()
            clusterEnd = -.infinity
        }

        for raw in raws {
            if raw.top >= clusterEnd { flush() }
            if let lane = laneEnds.firstIndex(where: { $0 <= raw.top }) {
                laneEnds[lane] = raw.bottom
                cluster.append((raw, lane))
            } else {
                laneEnds.append(raw.bottom)
                cluster.append((raw, laneEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, raw.bottom)
        }
        flush()
        return result
    }
}

// MARK: - Preview data

/// Preview services with a few blocks on the timetable: scheduled, clash (with a suggestion) and done.
func calPreviewServices() -> AppServices {
    let today = LocalDay.today
    var snapshot = SampleData.bodyFatGoal()
    snapshot.blocks = [
        CalendarBlock(ruleID: nil, systemID: SampleData.liftingSystemID, goalID: SampleData.goalID, title: "Lift",
                      start: today.date(minutes: 17 * 60), end: today.date(minutes: 18 * 60), status: .scheduled),
        CalendarBlock(ruleID: nil, systemID: SampleData.mealsSystemID, goalID: SampleData.goalID, title: "Meal prep",
                      start: today.adding(days: 1).date(minutes: 13 * 60 + 30),
                      end: today.adding(days: 1).date(minutes: 15 * 60), status: .clash,
                      suggestedStart: today.adding(days: 1).date(minutes: 16 * 60)),
        CalendarBlock(ruleID: nil, systemID: SampleData.walkSystemID, goalID: SampleData.goalID, title: "Incline walk",
                      start: today.adding(days: -1).date(minutes: 8 * 60), end: today.adding(days: -1).date(minutes: 8 * 60 + 40),
                      status: .done),
    ]
    return AppServices.preview(snapshot: snapshot)
}
