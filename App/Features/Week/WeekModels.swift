import Foundation
import Observation
import CoreKit

// MARK: - Display models

nonisolated struct WeekDotModel: Identifiable {
    let id: Int
    let day: LocalDay
    let mark: Mark?
    let scheduled: Bool
}

nonisolated struct WeekHabitRow: Identifiable {
    let id: UUID
    let name: String
    let dots: [WeekDotModel]
    let done: Int
    let setPoint: Int
    let isArchived: Bool
    /// done < setPoint in a finished week (ember in the "set" column).
    let belowSetPoint: Bool
    let accessibilitySummary: String
}

nonisolated struct WeekGoalModel: Identifiable {
    let id: UUID
    let goal: Goal
    let rows: [WeekHabitRow]
    /// Habits of this goal that can be picked as the bottleneck.
    let bottleneckChoices: [Habit]
    let flags: [String]
    let onTarget: Int
    let total: Int
    let state: ProgressState
    let streak: Int
    let suggestedBottleneckID: UUID?
    let review: WeekReview?
    let reviewBottleneckTitle: String?
    /// The last recorded result before this week (or the goal's start value).
    let previousResult: Double

    var scoreLabel: String { "\(onTarget) of \(total) on target" }
    var streakText: String { streak > 0 ? "\(streak)-week streak" : "no streak" }
}

nonisolated enum WeekTileMode {
    /// Last week: result, bottleneck and note can be edited, then Finish.
    case reviewable
    /// Older weeks: read-only history.
    case past
    /// The current week: live, not reviewable.
    case live
}

// MARK: - Rules

enum WeekRules {
    /// Mondays from 00:00: last week while any goal's review is unfinished; otherwise the current week (§7.10).
    static func defaultWeek(snapshot: StoreSnapshot, goals: [Goal], today: LocalDay, currentWeek: Week) -> Week {
        guard today.weekday == 1 else { return currentWeek }
        let last = currentWeek.previous
        let pending = goals.contains { goal in
            !snapshot.activeHabits(goalID: goal.id).isEmpty
                && snapshot.weekReview(goalID: goal.id, week: last)?.finishedAt == nil
        }
        return pending ? last : currentWeek
    }

    /// The oldest week with any data, so the back chevron stops there.
    static func earliestWeek(snapshot: StoreSnapshot, currentWeek: Week) -> Week {
        var earliest = currentWeek.start
        for log in snapshot.logs where log.day < earliest { earliest = log.day }
        for goal in snapshot.goals {
            let created = LocalDay(goal.createdAt)
            if created < earliest { earliest = created }
        }
        return Week(containing: earliest)
    }

    static func mode(for week: Week, currentWeek: Week) -> WeekTileMode {
        if week == currentWeek.previous { return .reviewable }
        if week.start < currentWeek.start { return .past }
        return .live
    }

    /// "12 to 18 Oct", or "29 Sep to 5 Oct" across a month boundary.
    static func rangeText(_ week: Week) -> String {
        let start = week.start
        let end = week.end
        if start.month == end.month && start.year == end.year {
            return "\(start.day) to \(LockInFormat.shortDayMonth(end))"
        }
        return "\(LockInFormat.shortDayMonth(start)) to \(LockInFormat.shortDayMonth(end))"
    }
}

enum WeekNumber {
    static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    /// One decimal at most: 84.6, 84.
    static func format(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded(), abs(rounded) < 1_000_000 { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }

    static func delta(from previous: Double, to value: Double, unit: String) -> String {
        let difference = value - previous
        if abs(difference) < 0.05 { return "No change since last check-in" }
        let sign = difference > 0 ? "+" : "\u{2212}"
        let suffix = unit.isEmpty ? "" : " \(unit)"
        return "\(sign)\(format(abs(difference)))\(suffix) since last check-in"
    }
}

// MARK: - Builder

enum WeekModelBuilder {
    private static let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    static func build(goal: Goal, snapshot: StoreSnapshot, week: Week, currentWeek: Week, now: Date) -> WeekGoalModel {
        let activeHabits = snapshot.activeHabits(goalID: goal.id)
        let score = HabitEngine.goalWeekScore(goal: goal, habits: activeHabits, week: week, logs: snapshot.logs,
                                              now: now, settings: snapshot.settings)
        // Archived habits keep their history in the week they were used (F1.3).
        let archived = snapshot.habits
            .filter { habit in
                habit.goalID == goal.id && habit.isArchived
                    && snapshot.logs.contains { $0.habitID == habit.id && week.contains($0.day) }
            }
            .sorted { $0.sortIndex < $1.sortIndex }
        let isFinishedWeek = week.start < currentWeek.start

        var flags: [String] = []
        var rows: [WeekHabitRow] = []
        for habit in activeHabits + archived {
            let weekScore = HabitEngine.weekScore(habit: habit, week: week, logs: snapshot.logs)
            let dots = week.days.enumerated().map { index, day in
                dot(habit: habit, day: day, index: index, snapshot: snapshot, now: now)
            }
            let below = isFinishedWeek && !habit.isArchived && weekScore.done < weekScore.setPoint
            rows.append(WeekHabitRow(id: habit.id, name: habit.title, dots: dots, done: weekScore.done,
                                     setPoint: weekScore.setPoint, isArchived: habit.isArchived, belowSetPoint: below,
                                     accessibilitySummary: summary(habit: habit, dots: dots, done: weekScore.done,
                                                                   setPoint: weekScore.setPoint)))
            if !habit.isArchived && weekScore.badDayFlag {
                flags.append("\(habit.title): \(weekScore.bad) of \(weekScore.done) were B. The slot may be in the wrong place.")
            }
        }

        let anchor = week.start < currentWeek.start ? week.next : currentWeek
        let streak = HabitEngine.goalStreak(goal: goal, habits: activeHabits, logs: snapshot.logs, currentWeek: anchor)
        let suggested = HabitEngine.suggestedBottleneck(habits: activeHabits, week: week, logs: snapshot.logs)
        let review = snapshot.weekReview(goalID: goal.id, week: week)
        let bottleneckTitle = review?.bottleneckHabitID.flatMap { id in snapshot.habit(id)?.title }

        let earlier = snapshot.weekReviews
            .filter { $0.goalID == goal.id && $0.weekStart < week.start && $0.resultValue != nil }
            .max { $0.weekStart < $1.weekStart }
        let previous = earlier?.resultValue ?? goal.resultStart

        return WeekGoalModel(id: goal.id, goal: goal, rows: rows, bottleneckChoices: activeHabits, flags: flags,
                             onTarget: score.onTarget, total: score.total, state: score.weekState, streak: streak,
                             suggestedBottleneckID: suggested, review: review, reviewBottleneckTitle: bottleneckTitle,
                             previousResult: previous)
    }

    private static func dot(habit: Habit, day: LocalDay, index: Int, snapshot: StoreSnapshot, now: Date) -> WeekDotModel {
        let logged = snapshot.log(habitID: habit.id, day: day)?.mark
        if case .perWeek = habit.frequency {
            // Marks can land on any day; a day with no mark is not an obligation.
            return WeekDotModel(id: index, day: day, mark: logged, scheduled: logged != nil)
        }
        let beforeStart = day < LocalDay(habit.createdAt)
        let scheduled = HabitEngine.isScheduled(habit, on: day) && !(beforeStart && logged == nil)
        if scheduled {
            return WeekDotModel(id: index, day: day, mark: HabitEngine.mark(for: habit, on: day, logs: snapshot.logs, now: now),
                                scheduled: true)
        }
        return WeekDotModel(id: index, day: day, mark: logged, scheduled: logged != nil)
    }

    private static func summary(habit: Habit, dots: [WeekDotModel], done: Int, setPoint: Int) -> String {
        let days = dots.map { dot -> String in
            let name = dayNames[dot.id]
            guard dot.scheduled else { return "\(name) not scheduled" }
            switch dot.mark {
            case .some(.D): return "\(name) done"
            case .some(.B): return "\(name) bad-day version"
            case .some(.M): return "\(name) missed"
            case .none: return "\(name) open"
            }
        }
        return "\(habit.title). \(days.joined(separator: ", ")). \(done) of \(setPoint)."
    }

    /// Result, bottleneck and note as they stand in the store (bottleneck falls back to the suggestion).
    static func defaultValues(goal: Goal, snapshot: StoreSnapshot, week: Week) -> WeekDraftValues {
        let review = snapshot.weekReview(goalID: goal.id, week: week)
        let suggested = HabitEngine.suggestedBottleneck(habits: snapshot.activeHabits(goalID: goal.id), week: week,
                                                        logs: snapshot.logs)
        return WeekDraftValues(resultText: review?.resultValue.map { WeekNumber.format($0) } ?? "",
                               bottleneckID: review?.bottleneckHabitID ?? suggested,
                               note: review?.note ?? "")
    }

    static func review(goalID: UUID, week: Week, existing: WeekReview?, values: WeekDraftValues,
                       finishedAt: Date?) -> WeekReview {
        var review = existing ?? WeekReview(goalID: goalID, weekStart: week.start)
        review.resultValue = WeekNumber.parse(values.resultText)
        review.bottleneckHabitID = values.bottleneckID
        let note = values.note.trimmingCharacters(in: .whitespacesAndNewlines)
        review.note = note.isEmpty ? nil : note
        if let finishedAt { review.finishedAt = finishedAt }
        return review
    }
}

// MARK: - Drafts

nonisolated struct WeekDraftValues: Equatable {
    var resultText: String
    var bottleneckID: UUID?
    var note: String
}

/// What the user is typing into one goal's tile.
@Observable
final class WeekDraft {
    var resultText: String
    var bottleneckID: UUID?
    var note: String
    @ObservationIgnored private var baseline: WeekDraftValues

    init(values: WeekDraftValues) {
        resultText = values.resultText
        bottleneckID = values.bottleneckID
        note = values.note
        baseline = values
    }

    var values: WeekDraftValues {
        WeekDraftValues(resultText: resultText, bottleneckID: bottleneckID, note: note)
    }

    /// True once the user changed something.
    var isEdited: Bool { values != baseline }

    func commit() { baseline = values }
}

/// Holds the drafts of the week on screen. Not observed: tiles observe their own `WeekDraft`.
final class WeekDraftStore {
    private(set) var weekStart: LocalDay?
    private var items: [UUID: WeekDraft] = [:]

    var week: Week? { weekStart.map { Week(start: $0) } }

    func draft(for goalID: UUID, week: Week, make: () -> WeekDraftValues) -> WeekDraft {
        if weekStart != week.start {
            items.removeAll()
            weekStart = week.start
        }
        if let existing = items[goalID] { return existing }
        let created = WeekDraft(values: make())
        items[goalID] = created
        return created
    }

    var edited: [(goalID: UUID, draft: WeekDraft)] {
        items.filter { $0.value.isEdited }.map { (goalID: $0.key, draft: $0.value) }
    }

    func reset() {
        items.removeAll()
        weekStart = nil
    }
}
