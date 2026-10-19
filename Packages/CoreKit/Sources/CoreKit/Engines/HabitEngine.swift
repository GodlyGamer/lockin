import Foundation

/// Colour state shared by gauges, map nodes and system status (§4.6, §8.1).
public enum ProgressState: String, Equatable, Sendable {
    case onTrack, behind, neutral
}

/// §4.6 — one habit in one week.
public struct HabitWeekScore: Equatable, Sendable {
    public var habitID: UUID
    /// `daily` = 7, `weekdays(d)` = d.count, `perWeek(n)` = n.
    public var scheduled: Int
    /// D or B logs in the week (perWeek: capped at n).
    public var done: Int
    /// B logs.
    public var bad: Int
    public var setPoint: Int
    /// done ≥ setPoint
    public var hit: Bool
    /// done ≥ 2 and bad > done / 2
    public var badDayFlag: Bool

    public init(habitID: UUID, scheduled: Int, done: Int, bad: Int, setPoint: Int, hit: Bool, badDayFlag: Bool) {
        self.habitID = habitID; self.scheduled = scheduled; self.done = done; self.bad = bad
        self.setPoint = setPoint; self.hit = hit; self.badDayFlag = badDayFlag
    }
}

/// §4.6 — one goal in one week, over its non-archived habits.
public struct GoalWeekScore: Equatable, Sendable {
    public var goalID: UUID
    public var onTarget: Int
    public var total: Int
    public var doneOcc: Int
    public var schedOcc: Int
    public var setOcc: Int
    public var expectedSoFar: Int
    public var habits: [HabitWeekScore]

    public init(goalID: UUID, onTarget: Int, total: Int, doneOcc: Int, schedOcc: Int, setOcc: Int,
                expectedSoFar: Int, habits: [HabitWeekScore]) {
        self.goalID = goalID; self.onTarget = onTarget; self.total = total; self.doneOcc = doneOcc
        self.schedOcc = schedOcc; self.setOcc = setOcc; self.expectedSoFar = expectedSoFar; self.habits = habits
    }

    /// Dashboard gauge fill: doneOcc / schedOcc (0 when nothing is scheduled).
    public var fraction: Double { schedOcc == 0 ? 0 : Double(doneOcc) / Double(schedOcc) }
    /// Dashboard set-point tick: setOcc / schedOcc.
    public var setPointFraction: Double { schedOcc == 0 ? 0 : Double(setOcc) / Double(schedOcc) }
    /// Dashboard colour: cobalt when doneOcc ≥ expectedSoFar; neutral with no habits.
    public var dashboardState: ProgressState { total == 0 ? .neutral : (doneOcc >= expectedSoFar ? .onTrack : .behind) }
    /// Week tab colour (finished week): cobalt only when every habit hit.
    public var weekState: ProgressState { total == 0 ? .neutral : (onTarget == total ? .onTrack : .behind) }
    /// "9 of 12"
    public var dashboardLabel: String { "\(doneOcc) of \(schedOcc)" }
    /// "3 of 4 on target"
    public var weekLabel: String { "\(onTarget) of \(total) on target" }
}

/// Habit scheduling, marks and scores (§3.6–3.7, §4.6). Stateless.
public enum HabitEngine {
    /// Marks made before 04:00 belong to the previous day.
    public static let dayBoundaryMinutes = 240

    /// The day a mark made at `date` is saved to (04:00 rule).
    public static func logicalDay(for date: Date) -> LocalDay {
        let day = LocalDay(date)
        return TimeOfDay.minutes(of: date) < dayBoundaryMinutes ? day.adding(days: -1) : day
    }

    /// Scheduled occurrences per week.
    public static func scheduledPerWeek(_ habit: Habit) -> Int {
        Habit.scheduledPerWeek(habit.frequency)
    }

    /// Whether `habit` is scheduled on `day` by frequency alone. perWeek habits are eligible every day.
    public static func isScheduled(_ habit: Habit, on day: LocalDay) -> Bool {
        switch habit.frequency {
        case .daily: true
        case .weekdays(let days): days.contains(day.weekday)
        case .perWeek: true
        }
    }

    /// Whether `habit` appears in Today on `day` (F1.1–1.2): scheduled, not archived, and for perWeek habits
    /// still short of n D/B marks before `day` in that week (a habit marked on `day` itself still shows).
    public static func isDue(_ habit: Habit, on day: LocalDay, logs: [HabitLog]) -> Bool {
        guard !habit.isArchived, isScheduled(habit, on: day) else { return false }
        guard case .perWeek(let n) = habit.frequency else { return true }
        let weekStart = Week(containing: day).start
        let doneBefore = logs.filter {
            $0.habitID == habit.id && $0.day >= weekStart && $0.day < day && isDoneOrBad($0.mark)
        }.count
        return doneBefore < n
    }

    /// The mark derived from a count (§3.7): count ≥ target → D; ≥ badDayTarget → B; otherwise M.
    public static func derivedMark(count: Int, habit: Habit) -> Mark {
        if count >= habit.target { return .D }
        if count >= habit.badDayTarget { return .B }
        return .M
    }

    /// The mark shown for `habit` on `day`: the logged mark; `.M` for a scheduled, unlogged occurrence in a finished
    /// day (computed, never stored; not for perWeek habits); nil when not scheduled or still open.
    ///
    /// A day is finished once the 04:00 rule has moved on from it (`day < logicalDay(for: now)`), so at 01:30 on
    /// Tuesday Monday is still open for marking.
    public static func mark(for habit: Habit, on day: LocalDay, logs: [HabitLog], now: Date) -> Mark? {
        if let log = logs.first(where: { $0.habitID == habit.id && $0.day == day }) { return log.mark }
        if habit.isArchived { return nil }
        if case .perWeek = habit.frequency { return nil }
        guard isScheduled(habit, on: day) else { return nil }
        return day < logicalDay(for: now) ? .M : nil
    }

    public static func weekScore(habit: Habit, week: Week, logs: [HabitLog]) -> HabitWeekScore {
        let scheduled = scheduledPerWeek(habit)
        var doneOrBad = 0
        var bad = 0
        for log in logs where log.habitID == habit.id && week.contains(log.day) {
            if isDoneOrBad(log.mark) { doneOrBad += 1 }
            if log.mark == .B { bad += 1 }
        }
        // perWeek habits are capped at n (§4.6); the same cap keeps a weekdays habit marked on an off-day within its
        // scheduled count, so gauges never exceed 100 %.
        let done = min(doneOrBad, scheduled)
        let badCount = min(bad, done)
        return HabitWeekScore(habitID: habit.id, scheduled: scheduled, done: done, bad: badCount,
                              setPoint: habit.setPointPerWeek, hit: done >= habit.setPointPerWeek,
                              badDayFlag: done >= 2 && badCount > done / 2)
    }

    /// `habits` may include other goals' and archived habits; only this goal's non-archived ones count.
    public static func goalWeekScore(goal: Goal, habits: [Habit], week: Week, logs: [HabitLog], now: Date,
                                     settings: AppSettings) -> GoalWeekScore {
        let goalHabits = habits.filter { $0.goalID == goal.id && !$0.isArchived }
        let scores = goalHabits.map { weekScore(habit: $0, week: week, logs: logs) }
        let elapsed = elapsedDays(in: week, now: now, settings: settings)
        let expected = goalHabits.reduce(0.0) { $0 + expectedCount($1, elapsed: elapsed) }
        return GoalWeekScore(goalID: goal.id,
                             onTarget: scores.filter(\.hit).count,
                             total: scores.count,
                             doneOcc: scores.reduce(0) { $0 + $1.done },
                             schedOcc: scores.reduce(0) { $0 + $1.scheduled },
                             setOcc: scores.reduce(0) { $0 + $1.setPoint },
                             expectedSoFar: Int((expected + 1e-9).rounded(.down)),
                             habits: scores)
    }

    /// Consecutive finished weeks, ending with the week before `currentWeek`, where every habit hit its set point.
    /// A goal with no (non-archived) habits has no streak.
    public static func goalStreak(goal: Goal, habits: [Habit], logs: [HabitLog], currentWeek: Week) -> Int {
        let goalHabits = habits.filter { $0.goalID == goal.id && !$0.isArchived }
        return streak(habits: goalHabits, logs: logs, currentWeek: currentWeek)
    }

    /// Consecutive finished weeks, ending with the week before `currentWeek`, where the habit hit.
    public static func habitStreak(habit: Habit, logs: [HabitLog], currentWeek: Week) -> Int {
        streak(habits: [habit], logs: logs, currentWeek: currentWeek)
    }

    /// The habit with the lowest done / setPoint in `week`; ties → lower priority number, then earlier sortIndex.
    /// Archived habits are never suggested.
    public static func suggestedBottleneck(habits: [Habit], week: Week, logs: [HabitLog]) -> UUID? {
        var best: (habit: Habit, done: Int, setPoint: Int)?
        for habit in habits where !habit.isArchived {
            let score = weekScore(habit: habit, week: week, logs: logs)
            let setPoint = max(score.setPoint, 1)
            guard let current = best else {
                best = (habit, score.done, setPoint)
                continue
            }
            // Compare done/setPoint without floating point: a/b < c/d ⇔ a·d < c·b.
            let lhs = score.done * current.setPoint
            let rhs = current.done * setPoint
            if lhs < rhs || (lhs == rhs && (habit.priority, habit.sortIndex) < (current.habit.priority, current.habit.sortIndex)) {
                best = (habit, score.done, setPoint)
            }
        }
        return best?.habit.id
    }

    /// Map colour for a system: onTrack if every habit has done ≥ its pro-rata expected count this week; neutral with no habits.
    /// The expected count is ⌊setPoint × elapsed / scheduled⌋, with `elapsed` as in the goal's `expectedSoFar`.
    public static func systemStatus(systemID: UUID, habits: [Habit], week: Week, logs: [HabitLog], now: Date,
                                    settings: AppSettings) -> ProgressState {
        let systemHabits = habits.filter { $0.systemID == systemID && !$0.isArchived }
        guard !systemHabits.isEmpty else { return .neutral }
        let elapsed = elapsedDays(in: week, now: now, settings: settings)
        let onTrack = systemHabits.allSatisfy { habit in
            let expected = Int((expectedCount(habit, elapsed: elapsed) + 1e-9).rounded(.down))
            return weekScore(habit: habit, week: week, logs: logs).done >= expected
        }
        return onTrack ? .onTrack : .behind
    }

    // MARK: - Helpers

    private static func isDoneOrBad(_ mark: Mark) -> Bool { mark == .D || mark == .B }

    /// Days of `week` that count as elapsed for pro-rata maths: days before today, plus today once `eveningTime` has passed.
    private static func elapsedDays(in week: Week, now: Date, settings: AppSettings) -> [LocalDay] {
        let today = LocalDay(now)
        let pastEvening = TimeOfDay.minutes(of: now) >= settings.eveningTime
        return week.days.filter { $0 < today || ($0 == today && pastEvening) }
    }

    /// setPoint × elapsed / scheduled (§4.6), before flooring.
    private static func expectedCount(_ habit: Habit, elapsed: [LocalDay]) -> Double {
        let scheduled = scheduledPerWeek(habit)
        guard scheduled > 0 else { return 0 }
        let elapsedOccurrences: Double
        switch habit.frequency {
        case .daily:
            elapsedOccurrences = Double(elapsed.count)
        case .weekdays(let days):
            let set = Set(days)
            elapsedOccurrences = Double(elapsed.filter { set.contains($0.weekday) }.count)
        case .perWeek(let n):
            elapsedOccurrences = Double(n) * Double(elapsed.count) / 7
        }
        return Double(habit.setPointPerWeek) * elapsedOccurrences / Double(scheduled)
    }

    /// Consecutive weeks before `currentWeek` in which every habit hit. Stops at the first miss, and never looks
    /// further back than the earliest log (a week with no marks can't be on target).
    private static func streak(habits: [Habit], logs: [HabitLog], currentWeek: Week) -> Int {
        guard !habits.isEmpty else { return 0 }
        let ids = Set(habits.map(\.id))
        let relevant = logs.filter { ids.contains($0.habitID) }
        guard let earliest = relevant.map(\.day).min() else { return 0 }
        var count = 0
        var week = currentWeek.previous
        while week.end >= earliest {
            guard habits.allSatisfy({ weekScore(habit: $0, week: week, logs: relevant).hit }) else { break }
            count += 1
            week = week.previous
        }
        return count
    }
}
