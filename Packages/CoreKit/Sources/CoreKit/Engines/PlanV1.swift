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
    ///
    /// Everything of the goal comes back: principles, systems, objectives (a deadline only when overridden), steps,
    /// habits, every block rule (active or not, so a re-import never deletes one), reminders, and one-off blocks that
    /// are scheduled or clashing and start today or later.
    public init?(goalID: UUID, snapshot: StoreSnapshot) {
        guard let plan = PlanV1.rebuilt(goalID: goalID, snapshot: snapshot, oneOffsFrom: .today) else { return nil }
        self = plan
    }

    /// `oneOffsFrom` is the first day whose one-off blocks are included.
    static func rebuilt(goalID: UUID, snapshot: StoreSnapshot, oneOffsFrom: LocalDay) -> PlanV1? {
        guard let goal = snapshot.goal(goalID) else { return nil }
        let principles = snapshot.firstPrinciples(goalID: goalID)
        let systems = snapshot.systems(goalID: goalID)
        let objectives = snapshot.objectives(goalID: goalID)
        let objectiveOrder = Dictionary(objectives.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        let steps = snapshot.steps.filter { objectiveOrder[$0.objectiveID] != nil }
            .sorted { (objectiveOrder[$0.objectiveID]!, $0.sortIndex) < (objectiveOrder[$1.objectiveID]!, $1.sortIndex) }
        let habits = snapshot.activeHabits(goalID: goalID)
        let systemIDs = Set(systems.map(\.id))
        let rules = snapshot.blockRules.filter { systemIDs.contains($0.systemID) }
        let oneOffs = snapshot.blocks
            .filter { block in
                block.ruleID == nil && block.goalID == goalID && (block.status == .scheduled || block.status == .clash)
                    && block.day >= oneOffsFrom && block.systemID.map(systemIDs.contains) == true
            }
            .sorted { $0.start < $1.start }
        let reminders = snapshot.reminders.filter { $0.systemID.map(systemIDs.contains) == true }

        let principleKey = PlanKeys.uniqueKeys(principles, id: \.id, key: PlanKeys.principle)
        let systemKey = PlanKeys.uniqueKeys(systems, id: \.id, key: PlanKeys.system)
        let objectiveKey = PlanKeys.uniqueKeys(objectives, id: \.id, key: PlanKeys.objective)
        let stepKey = PlanKeys.uniqueKeys(steps, id: \.id, key: PlanKeys.step)
        let habitKey = PlanKeys.uniqueKeys(habits, id: \.id, key: PlanKeys.habit)
        let reminderKey = PlanKeys.uniqueKeys(reminders, id: \.id, key: PlanKeys.reminder)
        // Rules and one-off blocks share the `blocks` list, so their keys must be unique together.
        var blockKey = PlanKeys.uniqueKeys(rules, id: \.id, key: PlanKeys.rule)
        let usedBlockKeys = Set(blockKey.values)
        for (id, key) in PlanKeys.uniqueKeys(oneOffs, id: \.id, key: PlanKeys.block) {
            blockKey[id] = usedBlockKeys.contains(key) ? key + "-1" : key
        }

        func clock(_ minutes: Int) -> String { TimeOfDay.format(min(max(minutes, 0), 1439)) }

        let goalSpec = GoalSpec(id: goal.id.uuidString, key: goal.planKey ?? "g", title: goal.title, outcome: goal.outcome,
                                deadline: goal.deadline.string, bufferDays: goal.bufferDays,
                                result: ResultSpec(name: goal.resultName, unit: goal.resultUnit,
                                                   start: goal.resultStart, target: goal.resultTarget))

        let principleSpecs = principles.map { PrincipleSpec(key: principleKey[$0.id]!, title: $0.title, why: $0.why) }
        let systemSpecs = systems.map { system in
            SystemSpec(key: systemKey[system.id]!,
                       firstPrinciple: system.kind == .sustaining ? nil : system.firstPrincipleID.flatMap { principleKey[$0] },
                       kind: system.kind.rawValue, title: system.title, location: system.location)
        }
        let objectiveSpecs = objectives.map { objective in
            ObjectiveSpec(key: objectiveKey[objective.id]!, title: objective.title, estimatedDays: objective.estimatedDays,
                          dependsOn: objective.dependsOnIDs.compactMap { objectiveKey[$0] },
                          systems: objective.systemIDs.compactMap { systemKey[$0] },
                          deadline: objective.deadlineOverridden ? objective.deadline?.string : nil)
        }
        let stepSpecs = steps.map { step in
            StepSpec(key: stepKey[step.id]!, objective: objectiveKey[step.objectiveID]!, title: step.title,
                     estimatedMinutes: step.estimatedMinutes, deadline: step.deadline?.string)
        }
        let habitSpecs = habits.map { habit -> HabitSpec in
            let frequency: FrequencySpec
            switch habit.frequency {
            case .daily:
                frequency = FrequencySpec(type: "daily")
            case .weekdays(let days):
                frequency = FrequencySpec(type: "weekdays", weekdays: CoreFormat.sortedUnique(days))
            case .perWeek(let n):
                frequency = FrequencySpec(type: "perWeek", timesPerWeek: n, preferredWeekdays: habit.preferredWeekdays)
            }
            return HabitSpec(key: habitKey[habit.id]!, system: habit.systemID.flatMap { systemKey[$0] }, title: habit.title,
                             badDayTitle: habit.badDayTitle, kind: habit.kind.rawValue, target: habit.target,
                             badDayTarget: habit.badDayTarget, unit: habit.unit, frequency: frequency,
                             setPointPerWeek: habit.setPointPerWeek, reminderTime: habit.reminderTime.map(clock),
                             durationMinutes: habit.durationMinutes, isPhysical: habit.isPhysical, priority: habit.priority)
        }
        var blockSpecs = rules.map { rule in
            BlockSpec(key: blockKey[rule.id]!, system: systemKey[rule.systemID]!, title: rule.title,
                      durationMinutes: rule.durationMinutes, weekdays: rule.weekdays, startTime: clock(rule.startTime),
                      windowStart: clock(rule.windowStart), windowEnd: clock(rule.windowEnd),
                      isPhysical: rule.isPhysical, nudge: rule.nudge)
        }
        blockSpecs += oneOffs.map { block in
            let start = TimeOfDay.minutes(of: block.start)
            return BlockSpec(key: blockKey[block.id]!, system: systemKey[block.systemID!]!, title: block.title,
                             durationMinutes: block.durationMinutes, weekdays: [], date: block.day.string,
                             startTime: clock(start), windowStart: clock(start), windowEnd: clock(start + block.durationMinutes),
                             isPhysical: block.isPhysical, nudge: block.nudge)
        }
        let reminderSpecs = reminders.map { reminder in
            ReminderSpec(key: reminderKey[reminder.id]!, system: reminder.systemID.flatMap { systemKey[$0] },
                         title: reminder.title, body: reminder.body, date: reminder.date?.string,
                         weekdays: reminder.weekdays, time: clock(reminder.time), priority: reminder.priority)
        }
        return PlanV1(goal: goalSpec, firstPrinciples: principleSpecs, systems: systemSpecs, objectives: objectiveSpecs,
                      steps: stepSpecs, habits: habitSpecs, blocks: blockSpecs, reminders: reminderSpecs)
    }

    /// Pretty-printed, sorted-keys JSON.
    public func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
