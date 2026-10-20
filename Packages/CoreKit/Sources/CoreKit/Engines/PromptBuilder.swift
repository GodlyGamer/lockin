import Foundation

/// The intake answers (§4.2). Codable so the draft can live in `@SceneStorage` as JSON.
public struct IntakeAnswers: Codable, Equatable, Sendable {
    /// Q11 chips.
    public enum TimeChip: String, Codable, CaseIterable, Sendable {
        case early, morning, afternoon, evening, late

        /// "Early 06–09"
        public var label: String {
            switch self {
            case .early: "Early 06–09"
            case .morning: "Morning 09–12"
            case .afternoon: "Afternoon 12–17"
            case .evening: "Evening 17–21"
            case .late: "Late 21–24"
            }
        }

        /// Minutes after midnight, half-open.
        public var range: Range<Int> {
            switch self {
            case .early: 360..<540
            case .morning: 540..<720
            case .afternoon: 720..<1020
            case .evening: 1020..<1260
            case .late: 1260..<1440
            }
        }
    }

    /// Q12 chips (the user can add more).
    public static let placeChips = ["Library", "Home desk", "Gym", "Uni building"]
    /// Q14 chips; "Other" is free text appended to `stoppers`.
    public static let stopperChips = ["Busy weeks", "Boredom", "No visible progress", "Bad days"]

    // Round 1
    public var goal: String
    public var resultName: String
    public var unit: String
    public var current: Double
    public var target: Double
    public var deadline: LocalDay
    // Round 2
    public var triedBefore: String
    public var resources: String
    public var hardLimits: String
    public var whyItMatters: String
    // Round 3
    public var hoursPerWeek: Int
    public var bestTimes: [TimeChip]
    public var bestPlaces: [String]
    public var saturdaysOff: Bool
    // Round 4
    public var stoppers: [String]
    public var badDayVersion: String

    public init(goal: String, resultName: String, unit: String, current: Double, target: Double, deadline: LocalDay,
                triedBefore: String = "", resources: String = "", hardLimits: String = "", whyItMatters: String = "",
                hoursPerWeek: Int = 5, bestTimes: [TimeChip] = [], bestPlaces: [String] = [], saturdaysOff: Bool = true,
                stoppers: [String] = [], badDayVersion: String = "") {
        self.goal = goal; self.resultName = resultName; self.unit = unit; self.current = current; self.target = target
        self.deadline = deadline; self.triedBefore = triedBefore; self.resources = resources; self.hardLimits = hardLimits
        self.whyItMatters = whyItMatters; self.hoursPerWeek = hoursPerWeek; self.bestTimes = bestTimes
        self.bestPlaces = bestPlaces; self.saturdaysOff = saturdaysOff; self.stoppers = stoppers
        self.badDayVersion = badDayVersion
    }

    /// Inferred by comparing Q4 with Q3.
    public var direction: ResultDirection { target < current ? .down : .up }

    /// Every field pre-filled so "Next" always works (F6.1): the §4.2 placeholders, deadline today + 90 days,
    /// 5 hours, time chips overlapping `settings.bestHours`, Saturdays off from settings.
    public static func defaults(today: LocalDay, settings: AppSettings) -> IntakeAnswers {
        let times = TimeChip.allCases.filter { chip in
            settings.bestHours.contains { $0.start < chip.range.upperBound && $0.end > chip.range.lowerBound }
        }
        return IntakeAnswers(goal: "10% body fat", resultName: "Weigh-in average", unit: "kg", current: 0, target: 0,
                             deadline: today.adding(days: 90), resources: "Uni gym, £30 a month, a friend who lifts",
                             hoursPerWeek: 5, bestTimes: times, saturdaysOff: settings.saturdayOff)
    }
}

/// Builds the text copied to Claude (Appendices A–C). Stateless.
public enum PromptBuilder {
    /// Appendix B. `busy == nil` → "Busy times: not available (calendar access off)". Busy times are merged, clipped to
    /// 06:00–24:00, one line per day for the next 14 days from `now`; never titles or locations.
    public static func intakePrompt(answers: IntakeAnswers, busy: [BusyInterval]?, settings: AppSettings, now: Date) -> String {
        func text(_ value: String) -> String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "—" : trimmed
        }
        func list(_ values: [String]) -> String { values.isEmpty ? "—" : values.joined(separator: ", ") }

        let today = LocalDay(now)
        var lines = [
            "New goal for my goal system. Use my method: work backwards to first principles, one system per principle, one sustaining system, and a DAG of milestones with deadlines. Grill me on anything you still need first, then give the plan and finish with the Lock in plan JSON (schema v1).",
            "",
            "Goal: \(text(answers.goal))",
            "Measured by: \(answers.resultName) (\(answers.unit)). Now: \(CoreFormat.number(answers.current)). Target: \(CoreFormat.number(answers.target)). Deadline: \(answers.deadline.string).",
            "Tried before: \(text(answers.triedBefore))",
            "Resources: \(text(answers.resources))",
            "Hard limits: \(text(answers.hardLimits))",
            "Why it matters: \(text(answers.whyItMatters))",
            "Hours a week: \(answers.hoursPerWeek)",
            "Best times: \(list(answers.bestTimes.map(\.label)))",
            "Best places: \(list(answers.bestPlaces))",
            "Saturdays off for goal work: \(answers.saturdaysOff ? "yes" : "no") (physical activity still fine)",
            "What usually makes me stop: \(list(answers.stoppers))",
            "Smallest bad-day version: \(text(answers.badDayVersion))",
            "Today: \(CoreFormat.dayMonthYear(today))",
        ]
        if let busy {
            lines.append("Busy times, next 14 days (06:00–24:00, titles hidden):")
            for offset in 0..<14 {
                let day = today.adding(days: offset)
                lines.append("\(CoreFormat.dayMonth(day)): \(busyText(on: day, busy: busy))")
            }
        } else {
            lines.append("Busy times: not available (calendar access off)")
        }
        return lines.joined(separator: "\n")
    }

    /// "09:00–11:00, 13:00–15:00" or "free": the day's busy time clipped to 06:00–24:00 and merged.
    private static func busyText(on day: LocalDay, busy: [BusyInterval]) -> String {
        let dayStart = day.date(minutes: 360)
        let dayEnd = day.date(minutes: 1440)
        let clipped = busy.compactMap { interval -> (start: Date, end: Date)? in
            let start = max(interval.start, dayStart)
            let end = min(interval.end, dayEnd)
            return start < end ? (start: start, end: end) : nil
        }
        func clock(_ date: Date) -> String { date == dayEnd ? "24:00" : CoreFormat.time(date) }
        let parts = CoreFormat.merged(clipped).map { "\(clock($0.start))–\(clock($0.end))" }
        return parts.isEmpty ? "free" : parts.joined(separator: ", ")
    }

    /// Appendix C for one goal and one finished week, including the goal rebuilt as plan JSON.
    ///
    /// The result is the week's own review value ("—" if none was entered). "Bottleneck I picked" is the week's
    /// review pick, else the goal's, else the suggestion. The plan JSON carries one-off blocks from the end of `week` on.
    public static func checkInPrompt(goalID: UUID, snapshot: StoreSnapshot, week: Week) -> String {
        guard let goal = snapshot.goal(goalID) else { return "Weekly check-in: goal not found." }
        let settings = snapshot.settings
        let review = snapshot.weekReview(goalID: goalID, week: week)
        // A moment after the week, so every day in it counts as finished.
        let afterWeek = week.next.start.date(minutes: 720)
        let habits = snapshot.activeHabits(goalID: goalID)
        let score = HabitEngine.goalWeekScore(goal: goal, habits: snapshot.habits, week: week, logs: snapshot.logs,
                                              now: afterWeek, settings: settings)
        let streak = HabitEngine.goalStreak(goal: goal, habits: snapshot.habits, logs: snapshot.logs, currentWeek: week.next)
        let unit = goal.resultUnit

        let value = review?.resultValue.map { CoreFormat.number($0) + unit } ?? "—"
        var lines = [
            "Weekly check-in for goal \"\(goal.title)\" (goalId: \(goal.id.uuidString)). Week \(CoreFormat.shortDayMonth(week.start))–\(CoreFormat.shortDayMonth(week.end)).",
            "Result: \(goal.resultName) \(value) (target \(CoreFormat.number(goal.resultTarget))\(unit), start \(CoreFormat.number(goal.resultStart))\(unit)).",
            "Scorecard (D = done, B = bad-day version, M = missed, - = not scheduled):",
        ]
        for habit in habits {
            let marks = week.days.map { day in
                HabitEngine.mark(for: habit, on: day, logs: snapshot.logs, now: afterWeek)?.rawValue ?? "-"
            }.joined()
            let habitScore = HabitEngine.weekScore(habit: habit, week: week, logs: snapshot.logs)
            var line = "\(habit.title): \(marks) — \(habitScore.done)/\(habitScore.setPoint)"
            if habitScore.badDayFlag { line += " — FLAG: \(habitScore.bad) of \(habitScore.done) were B" }
            lines.append(line)
        }

        let pickedID = review?.bottleneckHabitID ?? goal.bottleneckHabitID
            ?? HabitEngine.suggestedBottleneck(habits: habits, week: week, logs: snapshot.logs)
        let picked = pickedID.flatMap { id in habits.first { $0.id == id }?.title ?? snapshot.habit(id)?.title } ?? "—"
        let note = review?.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let planJSON = PlanV1.rebuilt(goalID: goalID, snapshot: snapshot, oneOffsFrom: week.next.start)?.jsonString() ?? "{}"
        lines += [
            "On target: \(score.onTarget) of \(score.total). Streak: \(streak) weeks. Bottleneck I picked: \(picked).",
            "Note: \(note.isEmpty ? "—" : note)",
            "Current plan JSON (keep keys the same):",
            planJSON,
            "Redesign anything flagged or below set point, then finish with the full updated plan JSON (schema v1, same goalId and keys).",
        ]
        return lines.joined(separator: "\n")
    }

    /// Appendix A text, verbatim (Settings → Claude → "Copy prompt add-on").
    public static let promptAddOn: String = """
    When the plan is final, end your reply with exactly one ```json code block that follows "Lock in plan schema v1" below, with nothing after it. Use the times and busy blocks I gave you. Never put goal work on Saturday unless it's physical. Every habit needs a bad-day version. If my message includes "goalId", copy it into goal.id and keep every existing key the same so the app updates the goal rather than creating a new one.

    Lock in plan schema v1:
    {
      "schemaVersion": 1,
      "goal": { "id": "UUID or null", "key": "g", "title": "", "outcome": "", "deadline": "YYYY-MM-DD", "bufferDays": 7,
                "result": { "name": "", "unit": "", "start": 0, "target": 0 } },
      "firstPrinciples": [ { "key": "fp1", "title": "", "why": "" } ],
      "systems": [ { "key": "s1", "firstPrinciple": "fp1 or null", "kind": "principle | sustaining", "title": "", "location": "or null" } ],
      "objectives": [ { "key": "o1", "title": "", "estimatedDays": 14, "dependsOn": ["o0"], "systems": ["s1"], "deadline": "YYYY-MM-DD or null" } ],
      "steps": [ { "key": "st1", "objective": "o1", "title": "", "estimatedMinutes": 30, "deadline": "YYYY-MM-DD or null" } ],
      "habits": [ { "key": "h1", "system": "s1", "title": "", "badDayTitle": "", "kind": "check | count", "target": 1, "badDayTarget": 1, "unit": "or null",
                    "frequency": { "type": "daily | weekdays | perWeek", "weekdays": [1,3,5], "timesPerWeek": 5, "preferredWeekdays": [1,2,4] },
                    "setPointPerWeek": 3, "reminderTime": "HH:mm or null", "durationMinutes": 30, "isPhysical": false, "priority": 3 } ],
      "blocks": [ { "key": "b1", "system": "s1", "title": "", "durationMinutes": 60, "weekdays": [7], "date": "YYYY-MM-DD or null", "startTime": "HH:mm",
                    "windowStart": "HH:mm", "windowEnd": "HH:mm", "isPhysical": false, "nudge": false } ],
      "reminders": [ { "key": "r1", "system": "s1 or null", "title": "", "body": "", "date": "YYYY-MM-DD or null", "weekdays": [], "time": "HH:mm", "priority": 3 } ]
    }
    Rules: weekdays are 1=Mon … 7=Sun. Exactly one system has kind "sustaining" (firstPrinciple null). Keys are unique per list. dependsOn must not form a loop. For a "count" habit, badDayTarget < target. A block uses either weekdays (repeating) or date (one-off).
    """
}
