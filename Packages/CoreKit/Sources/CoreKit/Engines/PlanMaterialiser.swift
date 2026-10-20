import Foundation

/// The work behind `PlanImporter.materialise` (§4.4 steps 2–3, internal).
///
/// Matching in update mode is by key within the goal. An entity's key is its `planKey`, or the generated key
/// (`PlanKeys`) when it has none. Only entities that carry a `planKey` are ever archived or deleted for being
/// missing from the plan; entities made by hand in the app are left alone.
struct PlanMaterialiser {
    let plan: PlanV1
    let snapshot: StoreSnapshot
    let today: LocalDay
    let settings: AppSettings

    private var upserts: [AnyEntity] = []
    private var deletes: [EntityRef] = []
    private var inserted = 0
    private var changed = 0
    private var removed = 0
    private var moved: [String] = []
    private var startsLate: [String] = []
    private var isUpdate = false

    init(plan: PlanV1, snapshot: StoreSnapshot, today: LocalDay, settings: AppSettings) {
        self.plan = plan; self.snapshot = snapshot; self.today = today; self.settings = settings
    }

    /// Adds the entity to the upserts and, in update mode, counts it as new or changed.
    private mutating func record<T: Equatable>(_ entity: T, old: T?, _ wrap: (T) -> AnyEntity) {
        upserts.append(wrap(entity))
        guard isUpdate else { return }
        if let old {
            if old != entity { changed += 1 }
        } else {
            inserted += 1
        }
    }

    private func clean(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    mutating func run() -> ImportResult {
        let existingGoal = PlanKeys.goalUUID(plan.goal.id).uuid.flatMap { snapshot.goal($0) }
        isUpdate = existingGoal != nil
        let goalID = existingGoal?.id ?? UUID()

        // Existing entities of this goal, for matching (empty when creating).
        let oldPrinciples = isUpdate ? snapshot.firstPrinciples.filter { $0.goalID == goalID } : []
        let oldSystems = isUpdate ? snapshot.systems.filter { $0.goalID == goalID } : []
        let oldObjectives = isUpdate ? snapshot.objectives.filter { $0.goalID == goalID } : []
        let oldObjectiveIDs = Set(oldObjectives.map(\.id))
        let oldSteps = isUpdate ? snapshot.steps.filter { oldObjectiveIDs.contains($0.objectiveID) } : []
        let oldHabits = isUpdate ? snapshot.habits.filter { $0.goalID == goalID } : []
        let oldSystemIDs = Set(oldSystems.map(\.id))
        let oldRules = isUpdate ? snapshot.blockRules.filter { oldSystemIDs.contains($0.systemID) } : []
        let oldReminders = isUpdate ? snapshot.reminders.filter { $0.systemID.map(oldSystemIDs.contains) ?? false } : []
        let oldBlocks = isUpdate ? snapshot.blocks.filter { $0.ruleID == nil && $0.goalID == goalID } : []

        // Goal
        let result = plan.goal.result
        let goal = Goal(
            id: goalID, planKey: plan.goal.key, title: plan.goal.title, outcome: plan.goal.outcome ?? "",
            deadline: LocalDay(plan.goal.deadline) ?? today.adding(days: 90), bufferDays: plan.goal.bufferDays ?? 7,
            status: existingGoal?.status ?? .active, resultName: result.name, resultUnit: result.unit,
            resultStart: result.start, resultTarget: result.target,
            resultDirection: result.target < result.start ? .down : .up,
            bottleneckHabitID: existingGoal?.bottleneckHabitID,
            sortIndex: existingGoal?.sortIndex ?? ((snapshot.goals.map(\.sortIndex).max() ?? -1) + 1),
            createdAt: existingGoal?.createdAt ?? today.date(), importedPlanJSON: plan.jsonString())
        upserts.append(.goal(goal))

        // First principles
        var principleIDs: [String: UUID] = [:]
        for (index, spec) in plan.firstPrinciples.enumerated() {
            let old = oldPrinciples.first { PlanKeys.principle($0) == spec.key }
            let entity = FirstPrinciple(id: old?.id ?? UUID(), planKey: spec.key, goalID: goalID, title: spec.title,
                                        why: spec.why ?? "", sortIndex: index)
            principleIDs[spec.key] = entity.id
            record(entity, old: old, AnyEntity.firstPrinciple)
        }

        // Systems
        var systemIDs: [String: UUID] = [:]
        var sustainingID: UUID?
        for (index, spec) in plan.systems.enumerated() {
            let old = oldSystems.first { PlanKeys.system($0) == spec.key }
            let kind: SystemKind = spec.kind.lowercased() == "sustaining" ? .sustaining : .principle
            let entity = GoalSystem(id: old?.id ?? UUID(), planKey: spec.key, goalID: goalID,
                                    firstPrincipleID: kind == .sustaining ? nil : spec.firstPrinciple.flatMap { principleIDs[$0] },
                                    kind: kind, title: spec.title, location: clean(spec.location), sortIndex: index)
            systemIDs[spec.key] = entity.id
            if kind == .sustaining && sustainingID == nil { sustainingID = entity.id }
            record(entity, old: old, AnyEntity.system)
        }
        /// A habit, block or reminder with no `system` hangs off the goal's sustaining system, so it stays inside the goal.
        func resolveSystem(_ key: String?) -> UUID? {
            if let key, !key.isEmpty { return systemIDs[key] }
            return sustainingID
        }

        // Objectives: ids first so dependsOn can point forward.
        var objectiveIDs: [String: UUID] = [:]
        var oldObjectiveByKey: [String: Objective] = [:]
        for spec in plan.objectives {
            let old = oldObjectives.first { PlanKeys.objective($0) == spec.key }
            oldObjectiveByKey[spec.key] = old
            objectiveIDs[spec.key] = old?.id ?? UUID()
        }
        var objectives: [Objective] = []
        for (index, spec) in plan.objectives.enumerated() {
            guard let id = objectiveIDs[spec.key] else { continue }
            let fixed = spec.deadline.flatMap { LocalDay($0) }
            var dependsOn: [UUID] = []
            for key in spec.dependsOn ?? [] {
                if let dependency = objectiveIDs[key], dependency != id, !dependsOn.contains(dependency) { dependsOn.append(dependency) }
            }
            var driving: [UUID] = []
            for key in spec.systems ?? [] {
                if let system = systemIDs[key], !driving.contains(system) { driving.append(system) }
            }
            objectives.append(Objective(id: id, planKey: spec.key, goalID: goalID, title: spec.title, deadline: fixed,
                                        deadlineOverridden: fixed != nil, estimatedDays: max(1, spec.estimatedDays),
                                        status: oldObjectiveByKey[spec.key]?.status ?? .notStarted,
                                        dependsOnIDs: dependsOn, systemIDs: driving, sortIndex: index))
        }
        // Back-scheduling (§4.5): fill every non-overridden deadline and collect the "starts late" warnings.
        let schedule = ScheduleEngine.backSchedule(objectives: objectives, goal: goal, today: today)
        for index in objectives.indices where !objectives[index].deadlineOverridden {
            objectives[index].deadline = schedule.deadlines[objectives[index].id]
        }
        for objective in objectives {
            if let days = schedule.startsLateByDays[objective.id] {
                startsLate.append("\(objective.title): Starts \(days) days too late")
            }
            record(objective, old: oldObjectiveByKey[objective.planKey ?? ""], AnyEntity.objective)
        }

        // Steps
        var stepCounters: [UUID: Int] = [:]
        for spec in plan.steps {
            guard let objectiveID = objectiveIDs[spec.objective] else { continue }
            let old = oldSteps.first { PlanKeys.step($0) == spec.key }
            let index = stepCounters[objectiveID, default: 0]
            stepCounters[objectiveID] = index + 1
            let entity = Step(id: old?.id ?? UUID(), planKey: spec.key, objectiveID: objectiveID, title: spec.title,
                              deadline: spec.deadline.flatMap { LocalDay($0) }, estimatedMinutes: spec.estimatedMinutes ?? 30,
                              done: old?.done ?? false, sortIndex: index)
            record(entity, old: old, AnyEntity.step)
        }

        // Habits
        for (index, spec) in plan.habits.enumerated() {
            let old = oldHabits.first { PlanKeys.habit($0) == spec.key }
            let (frequency, preferred) = Self.frequency(spec.frequency)
            let scheduled = Habit.scheduledPerWeek(frequency)
            let isCount = spec.kind.lowercased() == "count"
            let target = isCount ? max(1, spec.target ?? 1) : 1
            let badDayTarget = isCount ? max(1, spec.badDayTarget ?? max(1, target - 1)) : 1
            let entity = Habit(
                id: old?.id ?? UUID(), planKey: spec.key, systemID: resolveSystem(spec.system), goalID: goalID,
                title: spec.title, badDayTitle: spec.badDayTitle, kind: isCount ? .count : .check, target: target,
                badDayTarget: badDayTarget, unit: clean(spec.unit), frequency: frequency, preferredWeekdays: preferred,
                setPointPerWeek: min(max(spec.setPointPerWeek ?? scheduled, 1), max(scheduled, 1)),
                reminderTime: spec.reminderTime.flatMap { TimeOfDay.parse($0) },
                durationMinutes: spec.durationMinutes ?? 15, isPhysical: spec.isPhysical ?? false,
                priority: min(max(spec.priority ?? 3, 1), 5), isArchived: false,
                createdAt: old?.createdAt ?? today.date(), sortIndex: index)
            record(entity, old: old, AnyEntity.habit)
        }

        // Blocks: repeating → BlockRule, with a date → CalendarBlock
        var ruleKeys = Set<String>()
        for spec in plan.blocks {
            guard let systemID = resolveSystem(spec.system) else { continue }
            let isPhysical = spec.isPhysical ?? false
            let duration = spec.durationMinutes ?? 15
            let start = TimeOfDay.parse(spec.startTime) ?? 0
            let moveOffSaturday = settings.saturdayOff && !isPhysical

            if let dateText = spec.date, var day = LocalDay(dateText) {
                if moveOffSaturday && day.weekday == 6 {
                    day = day.adding(days: 1)
                    moved.append("Moved off Saturday: \(spec.title) → Sun \(TimeOfDay.format(start))")
                }
                let startDate = day.date(minutes: start)
                let old = oldBlocks.first { PlanKeys.block($0) == spec.key }
                    ?? oldBlocks.first { $0.systemID == systemID && $0.title == spec.title && $0.start == startDate }
                var block = old ?? CalendarBlock(title: spec.title, start: startDate, end: startDate)
                block.systemID = systemID
                block.goalID = goalID
                block.title = spec.title
                if block.start != startDate {
                    block.suggestedStart = nil
                    if block.status == .clash { block.status = .scheduled }
                }
                block.start = startDate
                block.end = startDate.addingTimeInterval(TimeInterval(duration) * 60)
                block.isPhysical = isPhysical
                block.nudge = spec.nudge ?? false
                record(block, old: old, AnyEntity.block)
                continue
            }

            var weekdays = CoreFormat.sortedUnique((spec.weekdays ?? []).filter { (1...7).contains($0) })
            guard !weekdays.isEmpty else { continue }
            if moveOffSaturday && weekdays.contains(6) {
                weekdays = CoreFormat.sortedUnique(weekdays.map { $0 == 6 ? 7 : $0 })
                moved.append("Moved off Saturday: \(spec.title) → Sun \(TimeOfDay.format(start))")
            }
            let old = oldRules.first { PlanKeys.rule($0) == spec.key }
            let rule = BlockRule(
                id: old?.id ?? UUID(), planKey: spec.key, systemID: systemID, title: spec.title, durationMinutes: duration,
                weekdays: weekdays, startTime: start, windowStart: spec.windowStart.flatMap { TimeOfDay.parse($0) } ?? start,
                windowEnd: spec.windowEnd.flatMap { TimeOfDay.parse($0) } ?? start + duration, isPhysical: isPhysical,
                nudge: spec.nudge ?? false, active: old?.active ?? true)
            ruleKeys.insert(spec.key)
            record(rule, old: old, AnyEntity.blockRule)
        }

        // Reminders
        var reminderKeys = Set<String>()
        for spec in plan.reminders {
            let old = oldReminders.first { PlanKeys.reminder($0) == spec.key }
            let entity = PlanReminder(
                id: old?.id ?? UUID(), planKey: spec.key, systemID: resolveSystem(spec.system), title: spec.title,
                body: spec.body ?? "", date: spec.date.flatMap { LocalDay($0) },
                weekdays: CoreFormat.sortedUnique((spec.weekdays ?? []).filter { (1...7).contains($0) }),
                time: TimeOfDay.parse(spec.time) ?? 0, priority: min(max(spec.priority ?? 3, 1), 5), active: old?.active ?? true)
            reminderKeys.insert(spec.key)
            record(entity, old: old, AnyEntity.reminder)
        }

        if isUpdate {
            removeMissing(oldHabits: oldHabits, oldRules: oldRules, oldReminders: oldReminders,
                          oldObjectives: oldObjectives, oldSteps: oldSteps, ruleKeys: ruleKeys, reminderKeys: reminderKeys)
        }

        let summary = ImportSummary(
            goalTitle: plan.goal.title, isUpdate: isUpdate, principles: plan.firstPrinciples.count,
            systems: plan.systems.count, habits: plan.habits.count, blocks: plan.blocks.count,
            reminders: plan.reminders.count, inserted: inserted, changed: changed, removed: removed,
            movedOffSaturday: moved, startsLate: startsLate)
        return ImportResult(goalID: goalID, changes: ChangeSet(upserts: upserts, deletes: deletes), summary: summary)
    }

    /// §4.4 step 3: keys missing from the plan. Habits are archived (logs kept); rules, reminders, objectives and
    /// steps are deleted (deleting a rule also removes its future blocks). Logs and reviews are never touched.
    private mutating func removeMissing(oldHabits: [Habit], oldRules: [BlockRule], oldReminders: [PlanReminder],
                                        oldObjectives: [Objective], oldSteps: [Step],
                                        ruleKeys: Set<String>, reminderKeys: Set<String>) {
        let habitKeys = Set(plan.habits.map(\.key))
        for habit in oldHabits {
            guard let key = habit.planKey, !habitKeys.contains(key), !habit.isArchived else { continue }
            var archived = habit
            archived.isArchived = true
            upserts.append(.habit(archived))
            removed += 1
        }
        for rule in oldRules {
            guard let key = rule.planKey, !ruleKeys.contains(key) else { continue }
            deletes.append(EntityRef(.blockRule, rule.id))
            removed += 1
        }
        for reminder in oldReminders {
            guard let key = reminder.planKey, !reminderKeys.contains(key) else { continue }
            deletes.append(EntityRef(.reminder, reminder.id))
            removed += 1
        }
        let objectiveKeys = Set(plan.objectives.map(\.key))
        var deletedObjectives = Set<UUID>()
        for objective in oldObjectives {
            guard let key = objective.planKey, !objectiveKeys.contains(key) else { continue }
            deletes.append(EntityRef(.objective, objective.id))
            deletedObjectives.insert(objective.id)
            removed += 1
        }
        let stepKeys = Set(plan.steps.map(\.key))
        let keptStepIDs = Set(upserts.compactMap { entity -> UUID? in
            if case .step(let step) = entity { return step.id }
            return nil
        })
        for step in oldSteps {
            if deletedObjectives.contains(step.objectiveID) {
                // The objective's delete cascades to its steps, unless the plan moved this step to another objective.
                if !keptStepIDs.contains(step.id) { removed += 1 }
            } else if let key = step.planKey, !stepKeys.contains(key) {
                deletes.append(EntityRef(.step, step.id))
                removed += 1
            }
        }
    }

    private static func frequency(_ spec: PlanV1.FrequencySpec) -> (Frequency, [Int]) {
        func valid(_ days: [Int]?) -> [Int] { CoreFormat.sortedUnique((days ?? []).filter { (1...7).contains($0) }) }
        switch spec.type.lowercased() {
        case "weekdays":
            return (.weekdays(valid(spec.weekdays)), [])
        case "perweek":
            return (.perWeek(min(max(spec.timesPerWeek ?? 1, 1), 7)), valid(spec.preferredWeekdays))
        default:
            return (.daily, [])
        }
    }
}
