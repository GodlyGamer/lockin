import Foundation
import CoreKit

nonisolated enum TodayItemKind {
    case habit
    case block
}

/// One line of today's timeline: a habit or a calendar block.
nonisolated struct TodayItem: Identifiable {
    let id: String
    let kind: TodayItemKind
    /// The habit id or block id.
    let refID: UUID
    let title: String
    let detail: String?
    /// Minutes after midnight, for display. nil = untimed.
    let minutes: Int?
    let start: Date?
    let end: Date?
    /// Habits: the logged mark, nil when still open.
    let mark: Mark?
    let blockStatus: BlockStatus?
}

nonisolated struct TodayPlanModel {
    var day: LocalDay
    /// Blocks and timed habits, in time order.
    var timed: [TodayItem]
    /// Habits with no reminder time.
    var untimed: [TodayItem]
    /// Habits due today with no mark yet.
    var habitsLeft: Int

    var all: [TodayItem] { timed + untimed }
    var isEmpty: Bool { timed.isEmpty && untimed.isEmpty }
}

/// Builds today's plan from a snapshot (DESIGN.md §7.3). Today is the logical day (04:00 rule).
enum TodayPlan {
    static func build(snapshot: StoreSnapshot, day: LocalDay, now: Date) -> TodayPlanModel {
        var timed: [TodayItem] = []
        var untimed: [TodayItem] = []

        let blocks = snapshot.blocks
            .filter { $0.day == day && $0.status != .cancelled }
            .sorted { $0.start < $1.start }
        for block in blocks {
            timed.append(TodayItem(id: "block-\(block.id.uuidString)", kind: .block, refID: block.id, title: block.title,
                                   detail: "\(LockInFormat.time(block.start))–\(LockInFormat.time(block.end))",
                                   minutes: TimeOfDay.minutes(of: block.start), start: block.start, end: block.end,
                                   mark: nil, blockStatus: block.status))
        }

        let due = snapshot.habits.filter { HabitEngine.isDue($0, on: day, logs: snapshot.logs) }
        var left = 0
        for habit in due {
            let log = snapshot.log(habitID: habit.id, day: day)
            if log == nil { left += 1 }
            var detail = "Bad day: \(habit.badDayTitle)"
            if habit.kind == .count, let count = log?.count {
                let unit = (habit.unit ?? "").isEmpty ? "" : " \(habit.unit ?? "")"
                detail = "\(count) of \(habit.target)\(unit) · \(detail)"
            }
            let minutes = habit.reminderTime
            let start = minutes.map { day.date(minutes: $0) }
            let item = TodayItem(id: "habit-\(habit.id.uuidString)", kind: .habit, refID: habit.id, title: habit.title,
                                 detail: detail, minutes: minutes, start: start, end: nil, mark: log?.mark, blockStatus: nil)
            if minutes == nil { untimed.append(item) } else { timed.append(item) }
        }

        let priority: [UUID: (Int, Int)] = Dictionary(uniqueKeysWithValues: due.map { ($0.id, ($0.priority, $0.sortIndex)) })
        timed.sort { lhs, rhs in
            let l = lhs.minutes ?? 0
            let r = rhs.minutes ?? 0
            if l != r { return l < r }
            if lhs.kind != rhs.kind { return lhs.kind == .block }
            let lp = priority[lhs.refID] ?? (3, 0)
            let rp = priority[rhs.refID] ?? (3, 0)
            if lp.0 != rp.0 { return lp.0 < rp.0 }
            return lp.1 < rp.1
        }
        untimed.sort { lhs, rhs in
            let lp = priority[lhs.refID] ?? (3, 0)
            let rp = priority[rhs.refID] ?? (3, 0)
            if lp.0 != rp.0 { return lp.0 < rp.0 }
            return lp.1 < rp.1
        }
        return TodayPlanModel(day: day, timed: timed, untimed: untimed, habitsLeft: left)
    }

    /// The next thing to do: the first open timed item that hasn't ended, else the first unmarked habit.
    static func next(in plan: TodayPlanModel, now: Date) -> TodayItem? {
        let open = plan.timed.filter { item in
            switch item.kind {
            case .habit: return item.mark == nil
            case .block: return item.blockStatus == .scheduled || item.blockStatus == .clash
            }
        }
        if let upcoming = open.first(where: { ($0.end ?? $0.start ?? .distantPast) >= now }) {
            return upcoming
        }
        return plan.all.first { $0.kind == .habit && $0.mark == nil }
    }

    /// Blocks with status `.clash` in the next 7 days (§5.4, §7.3).
    static func clashCount(snapshot: StoreSnapshot, now: Date) -> Int {
        let horizon = now.addingTimeInterval(7 * 24 * 3600)
        return snapshot.blocks.filter { $0.status == .clash && $0.end > now && $0.start < horizon }.count
    }
}
