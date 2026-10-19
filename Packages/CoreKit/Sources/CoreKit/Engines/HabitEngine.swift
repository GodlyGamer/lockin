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
        // M1: implement (§4.6, F1.2).
        !habit.isArchived && isScheduled(habit, on: day)
    }

    /// The mark derived from a count (§3.7): count ≥ target → D; ≥ badDayTarget → B; otherwise M.
    public static func derivedMark(count: Int, habit: Habit) -> Mark {
        if count >= habit.target { return .D }
        if count >= habit.badDayTarget { return .B }
        return .M
    }

    /// The mark shown for `habit` on `day`: the logged mark; `.M` for a scheduled, unlogged occurrence in a finished
    /// day (computed, never stored; not for perWeek habits); nil when not scheduled or still open.
    public static func mark(for habit: Habit, on day: LocalDay, logs: [HabitLog], now: Date) -> Mark? {
        // M1: implement (§3.7).
        logs.first { $0.habitID == habit.id && $0.day == day }?.mark
    }

    public static func weekScore(habit: Habit, week: Week, logs: [HabitLog]) -> HabitWeekScore {
        // M1: implement (§4.6).
        HabitWeekScore(habitID: habit.id, scheduled: scheduledPerWeek(habit), done: 0, bad: 0,
                       setPoint: habit.setPointPerWeek, hit: false, badDayFlag: false)
    }

    /// `habits` may include other goals' and archived habits; only this goal's non-archived ones count.
    public static func goalWeekScore(goal: Goal, habits: [Habit], week: Week, logs: [HabitLog], now: Date,
                                     settings: AppSettings) -> GoalWeekScore {
        // M1: implement (§4.6, expectedSoFar).
        GoalWeekScore(goalID: goal.id, onTarget: 0, total: 0, doneOcc: 0, schedOcc: 0, setOcc: 0, expectedSoFar: 0, habits: [])
    }

    /// Consecutive finished weeks, ending with the week before `currentWeek`, where every habit hit its set point.
    public static func goalStreak(goal: Goal, habits: [Habit], logs: [HabitLog], currentWeek: Week) -> Int {
        // M1: implement (§4.6).
        0
    }

    /// Consecutive finished weeks, ending with the week before `currentWeek`, where the habit hit.
    public static func habitStreak(habit: Habit, logs: [HabitLog], currentWeek: Week) -> Int {
        // M1: implement (§4.6).
        0
    }

    /// The habit with the lowest done / setPoint in `week`; ties → lower priority number, then earlier sortIndex.
    public static func suggestedBottleneck(habits: [Habit], week: Week, logs: [HabitLog]) -> UUID? {
        // M1: implement (§4.6).
        nil
    }

    /// Map colour for a system: onTrack if every habit has done ≥ its pro-rata expected count this week; neutral with no habits.
    public static func systemStatus(systemID: UUID, habits: [Habit], week: Week, logs: [HabitLog], now: Date,
                                    settings: AppSettings) -> ProgressState {
        // M1: implement (§4.6).
        .neutral
    }
}
