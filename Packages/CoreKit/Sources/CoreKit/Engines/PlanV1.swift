import Foundation

/// "Lock in plan schema v1" (Appendix A), exactly as Claude writes it. Optional fields are nil when missing;
/// `PlanImporter` applies the Appendix A defaults. Unknown fields are ignored.
public struct PlanV1: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var goal: GoalSpec
    public var firstPrinciples: [PrincipleSpec]
    public var systems: [SystemSpec]
    public var objectives: [ObjectiveSpec]
    public var steps: [StepSpec]
    public var habits: [HabitSpec]
    public var blocks: [BlockSpec]
    public var reminders: [ReminderSpec]

    public init(schemaVersion: Int = 1, goal: GoalSpec, firstPrinciples: [PrincipleSpec] = [], systems: [SystemSpec] = [],
                objectives: [ObjectiveSpec] = [], steps: [StepSpec] = [], habits: [HabitSpec] = [],
                blocks: [BlockSpec] = [], reminders: [ReminderSpec] = []) {
        self.schemaVersion = schemaVersion; self.goal = goal; self.firstPrinciples = firstPrinciples
        self.systems = systems; self.objectives = objectives; self.steps = steps; self.habits = habits
        self.blocks = blocks; self.reminders = reminders
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, goal, firstPrinciples, systems, objectives, steps, habits, blocks, reminders
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        goal = try c.decode(GoalSpec.self, forKey: .goal)
        firstPrinciples = try c.decodeIfPresent([PrincipleSpec].self, forKey: .firstPrinciples) ?? []
        systems = try c.decodeIfPresent([SystemSpec].self, forKey: .systems) ?? []
        objectives = try c.decodeIfPresent([ObjectiveSpec].self, forKey: .objectives) ?? []
        steps = try c.decodeIfPresent([StepSpec].self, forKey: .steps) ?? []
        habits = try c.decodeIfPresent([HabitSpec].self, forKey: .habits) ?? []
        blocks = try c.decodeIfPresent([BlockSpec].self, forKey: .blocks) ?? []
        reminders = try c.decodeIfPresent([ReminderSpec].self, forKey: .reminders) ?? []
    }

    public struct ResultSpec: Codable, Equatable, Sendable {
        public var name: String
        public var unit: String
        public var start: Double
        public var target: Double

        public init(name: String, unit: String, start: Double, target: Double) {
            self.name = name; self.unit = unit; self.start = start; self.target = target
        }
    }

    public struct GoalSpec: Codable, Equatable, Sendable {
        /// Existing goal UUID string for update mode, or nil.
        public var id: String?
        public var key: String
        public var title: String
        public var outcome: String?
        /// "YYYY-MM-DD"
        public var deadline: String
        public var bufferDays: Int?
        public var result: ResultSpec

        public init(id: String? = nil, key: String = "g", title: String, outcome: String? = nil, deadline: String,
                    bufferDays: Int? = nil, result: ResultSpec) {
            self.id = id; self.key = key; self.title = title; self.outcome = outcome; self.deadline = deadline
            self.bufferDays = bufferDays; self.result = result
        }
    }

    public struct PrincipleSpec: Codable, Equatable, Sendable {
        public var key: String
        public var title: String
        public var why: String?

        public init(key: String, title: String, why: String? = nil) {
            self.key = key; self.title = title; self.why = why
        }
    }

    public struct SystemSpec: Codable, Equatable, Sendable {
        public var key: String
        /// Principle key, nil for the sustaining system.
        public var firstPrinciple: String?
        /// "principle" | "sustaining"
        public var kind: String
        public var title: String
        public var location: String?

        public init(key: String, firstPrinciple: String?, kind: String, title: String, location: String? = nil) {
            self.key = key; self.firstPrinciple = firstPrinciple; self.kind = kind; self.title = title; self.location = location
        }
    }

    public struct ObjectiveSpec: Codable, Equatable, Sendable {
        public var key: String
        public var title: String
        public var estimatedDays: Int
        public var dependsOn: [String]?
        public var systems: [String]?
        /// "YYYY-MM-DD" when Claude fixed it (becomes an override), else nil.
        public var deadline: String?

        public init(key: String, title: String, estimatedDays: Int, dependsOn: [String]? = nil, systems: [String]? = nil,
                    deadline: String? = nil) {
            self.key = key; self.title = title; self.estimatedDays = estimatedDays; self.dependsOn = dependsOn
            self.systems = systems; self.deadline = deadline
        }
    }

    public struct StepSpec: Codable, Equatable, Sendable {
        public var key: String
        public var objective: String
        public var title: String
        public var estimatedMinutes: Int?
        public var deadline: String?

        public init(key: String, objective: String, title: String, estimatedMinutes: Int? = nil, deadline: String? = nil) {
            self.key = key; self.objective = objective; self.title = title; self.estimatedMinutes = estimatedMinutes
            self.deadline = deadline
        }
    }

    public struct FrequencySpec: Codable, Equatable, Sendable {
        /// "daily" | "weekdays" | "perWeek"
        public var type: String
        public var weekdays: [Int]?
        public var timesPerWeek: Int?
        public var preferredWeekdays: [Int]?

        public init(type: String, weekdays: [Int]? = nil, timesPerWeek: Int? = nil, preferredWeekdays: [Int]? = nil) {
            self.type = type; self.weekdays = weekdays; self.timesPerWeek = timesPerWeek; self.preferredWeekdays = preferredWeekdays
        }
    }

    public struct HabitSpec: Codable, Equatable, Sendable {
        public var key: String
        public var system: String?
        public var title: String
        public var badDayTitle: String
        /// "check" | "count"
        public var kind: String
        public var target: Int?
        public var badDayTarget: Int?
        public var unit: String?
        public var frequency: FrequencySpec
        public var setPointPerWeek: Int?
        /// "HH:mm" or nil
        public var reminderTime: String?
        public var durationMinutes: Int?
        public var isPhysical: Bool?
        public var priority: Int?

        public init(key: String, system: String?, title: String, badDayTitle: String, kind: String = "check",
                    target: Int? = nil, badDayTarget: Int? = nil, unit: String? = nil, frequency: FrequencySpec,
                    setPointPerWeek: Int? = nil, reminderTime: String? = nil, durationMinutes: Int? = nil,
                    isPhysical: Bool? = nil, priority: Int? = nil) {
            self.key = key; self.system = system; self.title = title; self.badDayTitle = badDayTitle; self.kind = kind
            self.target = target; self.badDayTarget = badDayTarget; self.unit = unit; self.frequency = frequency
            self.setPointPerWeek = setPointPerWeek; self.reminderTime = reminderTime; self.durationMinutes = durationMinutes
            self.isPhysical = isPhysical; self.priority = priority
        }
    }

    public struct BlockSpec: Codable, Equatable, Sendable {
        public var key: String
        public var system: String
        public var title: String
        public var durationMinutes: Int?
        /// Repeating when non-empty.
        public var weekdays: [Int]?
        /// One-off when set ("YYYY-MM-DD").
        public var date: String?
        /// "HH:mm"
        public var startTime: String
        public var windowStart: String?
        public var windowEnd: String?
        public var isPhysical: Bool?
        public var nudge: Bool?

        public init(key: String, system: String, title: String, durationMinutes: Int? = nil, weekdays: [Int]? = nil,
                    date: String? = nil, startTime: String, windowStart: String? = nil, windowEnd: String? = nil,
                    isPhysical: Bool? = nil, nudge: Bool? = nil) {
            self.key = key; self.system = system; self.title = title; self.durationMinutes = durationMinutes
            self.weekdays = weekdays; self.date = date; self.startTime = startTime; self.windowStart = windowStart
            self.windowEnd = windowEnd; self.isPhysical = isPhysical; self.nudge = nudge
        }
    }

    public struct ReminderSpec: Codable, Equatable, Sendable {
        public var key: String
        public var system: String?
        public var title: String
        public var body: String?
        public var date: String?
        public var weekdays: [Int]?
        /// "HH:mm"
        public var time: String
        public var priority: Int?

        public init(key: String, system: String? = nil, title: String, body: String? = nil, date: String? = nil,
                    weekdays: [Int]? = nil, time: String, priority: Int? = nil) {
            self.key = key; self.system = system; self.title = title; self.body = body; self.date = date
            self.weekdays = weekdays; self.time = time; self.priority = priority
        }
    }
}

extension PlanV1 {
    /// Rebuilds a stored goal as schema v1 (for the check-in prompt, Appendix C). Keys are the entities' `planKey`s;
    /// entities without one get a generated key. Archived habits are left out. nil if the goal doesn't exist.
    public init?(goalID: UUID, snapshot: StoreSnapshot) {
        // M1: implement.
        guard let goal = snapshot.goal(goalID) else { return nil }
        self.init(goal: GoalSpec(id: goal.id.uuidString, key: goal.planKey ?? "g", title: goal.title, outcome: goal.outcome,
                                 deadline: goal.deadline.string, bufferDays: goal.bufferDays,
                                 result: ResultSpec(name: goal.resultName, unit: goal.resultUnit,
                                                    start: goal.resultStart, target: goal.resultTarget)))
    }

    /// Pretty-printed, sorted-keys JSON.
    public func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
