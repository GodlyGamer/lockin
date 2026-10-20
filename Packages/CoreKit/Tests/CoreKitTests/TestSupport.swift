import XCTest
@testable import CoreKit

/// Shared helpers. Every date in the tests is explicit: nothing reads the clock.
/// Reference week: Monday 2026-10-19 … Sunday 2026-10-25 (UK clocks go back on the 25th).

func day(_ text: String) -> LocalDay { LocalDay(text)! }

/// "2026-10-19", "07:30" → that wall-clock instant in Europe/London.
func at(_ dayText: String, _ time: String = "00:00") -> Date {
    day(dayText).date(minutes: TimeOfDay.parse(time)!)
}

func uuid(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
}

func makeLog(_ habit: Habit, _ dayText: String, _ mark: Mark, count: Int? = nil) -> HabitLog {
    HabitLog(habitID: habit.id, day: day(dayText), mark: mark, count: count, loggedAt: at(dayText, "20:00"))
}

func makeHabit(_ n: Int, title: String = "Habit", goal: UUID? = nil, system: UUID? = nil,
               frequency: Frequency = .daily, setPoint: Int? = nil, reminder: String? = nil, priority: Int = 3,
               preferred: [Int] = [], sortIndex: Int = 0, archived: Bool = false) -> Habit {
    Habit(id: uuid(1000 + n), systemID: system, goalID: goal, title: title, badDayTitle: "Small \(title)",
          frequency: frequency, preferredWeekdays: preferred, setPointPerWeek: setPoint,
          reminderTime: reminder.flatMap { TimeOfDay.parse($0) }, priority: priority, isArchived: archived,
          createdAt: at("2026-01-01"), sortIndex: sortIndex)
}

func makeGoal(_ n: Int = 1, deadline: String = "2026-12-31", buffer: Int = 7) -> Goal {
    Goal(id: uuid(n), planKey: "g", title: "Goal \(n)", deadline: day(deadline), bufferDays: buffer,
         resultName: "Weight", resultUnit: "kg", resultStart: 86, resultTarget: 78, resultDirection: .down,
         createdAt: at("2026-01-01"))
}
