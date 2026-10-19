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
        // M1: implement (Appendix B, §4.3).
        "New goal for my goal system.\n\nGoal: \(answers.goal)"
    }

    /// Appendix C for one goal and one finished week, including the goal rebuilt as plan JSON.
    public static func checkInPrompt(goalID: UUID, snapshot: StoreSnapshot, week: Week) -> String {
        // M1: implement (Appendix C).
        "Weekly check-in"
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
