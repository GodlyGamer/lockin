import Foundation

/// The app's data store. Implementations are `@Observable`; views read `revision` to re-render.
@MainActor public protocol Store: AnyObject {
    /// Increments on every change.
    var revision: Int { get }
    /// Non-nil when the persistent store failed to load (§7.2 error state). BUILD_PLAN §2 addition.
    var loadError: String? { get }
    /// All entities (the data is small).
    func snapshot() -> StoreSnapshot
    func apply(_ changes: ChangeSet) throws
    /// Restore: replaces everything.
    func replaceAll(with snapshot: StoreSnapshot) throws
}

extension Store {
    public var loadError: String? { nil }

    /// Convenience: apply a single upsert.
    public func upsert(_ entity: AnyEntity) throws {
        try apply(ChangeSet(upserts: [entity]))
    }

    /// Convenience: delete a single entity (with §3 cascades).
    public func delete(_ ref: EntityRef) throws {
        try apply(ChangeSet(deletes: [ref]))
    }
}

public struct StoreSnapshot: Codable, Equatable, Sendable {
    public var settings: AppSettings
    public var goals: [Goal]
    public var firstPrinciples: [FirstPrinciple]
    public var systems: [GoalSystem]
    public var objectives: [Objective]
    public var steps: [Step]
    public var habits: [Habit]
    public var logs: [HabitLog]
    public var weekReviews: [WeekReview]
    public var blockRules: [BlockRule]
    public var blocks: [CalendarBlock]
    public var reminders: [PlanReminder]

    public init(settings: AppSettings = .defaults, goals: [Goal] = [], firstPrinciples: [FirstPrinciple] = [],
                systems: [GoalSystem] = [], objectives: [Objective] = [], steps: [Step] = [], habits: [Habit] = [],
                logs: [HabitLog] = [], weekReviews: [WeekReview] = [], blockRules: [BlockRule] = [],
                blocks: [CalendarBlock] = [], reminders: [PlanReminder] = []) {
        self.settings = settings; self.goals = goals; self.firstPrinciples = firstPrinciples; self.systems = systems
        self.objectives = objectives; self.steps = steps; self.habits = habits; self.logs = logs
        self.weekReviews = weekReviews; self.blockRules = blockRules; self.blocks = blocks; self.reminders = reminders
    }

    public static let empty = StoreSnapshot()
}

public struct ChangeSet: Sendable {
    public var upserts: [AnyEntity]
    public var deletes: [EntityRef]

    public init(upserts: [AnyEntity] = [], deletes: [EntityRef] = []) {
        self.upserts = upserts; self.deletes = deletes
    }

    public var isEmpty: Bool { upserts.isEmpty && deletes.isEmpty }

    public mutating func merge(_ other: ChangeSet) {
        upserts += other.upserts
        deletes += other.deletes
    }
}

public enum AnyEntity: Equatable, Sendable {
    case goal(Goal)
    case firstPrinciple(FirstPrinciple)
    case system(GoalSystem)
    case objective(Objective)
    case step(Step)
    case habit(Habit)
    case log(HabitLog)
    case weekReview(WeekReview)
    case blockRule(BlockRule)
    case block(CalendarBlock)
    case reminder(PlanReminder)
    case settings(AppSettings)

    /// nil for `.settings` (a single record with no id).
    public var ref: EntityRef? {
        switch self {
        case .goal(let e): EntityRef(.goal, e.id)
        case .firstPrinciple(let e): EntityRef(.firstPrinciple, e.id)
        case .system(let e): EntityRef(.system, e.id)
        case .objective(let e): EntityRef(.objective, e.id)
        case .step(let e): EntityRef(.step, e.id)
        case .habit(let e): EntityRef(.habit, e.id)
        case .log(let e): EntityRef(.log, e.id)
        case .weekReview(let e): EntityRef(.weekReview, e.id)
        case .blockRule(let e): EntityRef(.blockRule, e.id)
        case .block(let e): EntityRef(.block, e.id)
        case .reminder(let e): EntityRef(.reminder, e.id)
        case .settings: nil
        }
    }
}

public struct EntityRef: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case goal, firstPrinciple, system, objective, step, habit, log, weekReview, blockRule, block, reminder
    }

    public let kind: Kind
    public let id: UUID

    public init(kind: Kind, id: UUID) {
        self.kind = kind; self.id = id
    }

    public init(_ kind: Kind, _ id: UUID) {
        self.init(kind: kind, id: id)
    }
}

// MARK: - Applying changes with the §3 delete rules

extension StoreSnapshot {
    /// Returns a copy with `changes` applied: upserts replace by id (or append), then deletes run with §3 rules:
    /// - Goal → cascades FirstPrinciple, GoalSystem, Objective, WeekReview (and through them below).
    /// - FirstPrinciple → nullifies `GoalSystem.firstPrincipleID`.
    /// - GoalSystem → nullifies `Habit.systemID` and `Habit.goalID` (habits become standalone); cascades BlockRule and PlanReminder.
    /// - Objective → cascades Step; removes its id from other objectives' `dependsOnIDs`.
    /// - Habit → cascades HabitLog.
    /// - BlockRule → deletes its blocks that start at or after `now`; past blocks stay as one-offs (`ruleID = nil`) (§4.4).
    public func applying(_ changes: ChangeSet, now: Date = Date()) -> StoreSnapshot {
        var s = self
        for entity in changes.upserts {
            switch entity {
            case .goal(let e): Self.upsert(e, into: &s.goals)
            case .firstPrinciple(let e): Self.upsert(e, into: &s.firstPrinciples)
            case .system(let e): Self.upsert(e, into: &s.systems)
            case .objective(let e): Self.upsert(e, into: &s.objectives)
            case .step(let e): Self.upsert(e, into: &s.steps)
            case .habit(let e): Self.upsert(e, into: &s.habits)
            case .log(let e):
                // (habitID, day) is unique: a new log for the same day replaces the old one.
                s.logs.removeAll { $0.habitID == e.habitID && $0.day == e.day && $0.id != e.id }
                Self.upsert(e, into: &s.logs)
            case .weekReview(let e):
                s.weekReviews.removeAll { $0.goalID == e.goalID && $0.weekStart == e.weekStart && $0.id != e.id }
                Self.upsert(e, into: &s.weekReviews)
            case .blockRule(let e): Self.upsert(e, into: &s.blockRules)
            case .block(let e): Self.upsert(e, into: &s.blocks)
            case .reminder(let e): Self.upsert(e, into: &s.reminders)
            case .settings(let e): s.settings = e
            }
        }
        for ref in changes.deletes {
            s.delete(ref, now: now)
        }
        return s
    }

    private static func upsert<T: Identifiable>(_ entity: T, into array: inout [T]) where T.ID == UUID {
        if let index = array.firstIndex(where: { $0.id == entity.id }) {
            array[index] = entity
        } else {
            array.append(entity)
        }
    }

    private mutating func delete(_ ref: EntityRef, now: Date) {
        switch ref.kind {
        case .goal:
            goals.removeAll { $0.id == ref.id }
            for p in firstPrinciples where p.goalID == ref.id { delete(EntityRef(.firstPrinciple, p.id), now: now) }
            for sys in systems where sys.goalID == ref.id { delete(EntityRef(.system, sys.id), now: now) }
            for o in objectives where o.goalID == ref.id { delete(EntityRef(.objective, o.id), now: now) }
            weekReviews.removeAll { $0.goalID == ref.id }
        case .firstPrinciple:
            firstPrinciples.removeAll { $0.id == ref.id }
            for i in systems.indices where systems[i].firstPrincipleID == ref.id { systems[i].firstPrincipleID = nil }
        case .system:
            systems.removeAll { $0.id == ref.id }
            for i in habits.indices where habits[i].systemID == ref.id {
                habits[i].systemID = nil
                habits[i].goalID = nil
            }
            for r in blockRules where r.systemID == ref.id { delete(EntityRef(.blockRule, r.id), now: now) }
            reminders.removeAll { $0.systemID == ref.id }
            for i in objectives.indices { objectives[i].systemIDs.removeAll { $0 == ref.id } }
        case .objective:
            objectives.removeAll { $0.id == ref.id }
            steps.removeAll { $0.objectiveID == ref.id }
            for i in objectives.indices { objectives[i].dependsOnIDs.removeAll { $0 == ref.id } }
        case .step:
            steps.removeAll { $0.id == ref.id }
        case .habit:
            habits.removeAll { $0.id == ref.id }
            logs.removeAll { $0.habitID == ref.id }
        case .log:
            logs.removeAll { $0.id == ref.id }
        case .weekReview:
            weekReviews.removeAll { $0.id == ref.id }
        case .blockRule:
            blockRules.removeAll { $0.id == ref.id }
            blocks.removeAll { $0.ruleID == ref.id && $0.start >= now }
            for i in blocks.indices where blocks[i].ruleID == ref.id { blocks[i].ruleID = nil }
        case .block:
            blocks.removeAll { $0.id == ref.id }
        case .reminder:
            reminders.removeAll { $0.id == ref.id }
        }
    }
}

// MARK: - Lookups used by every feature

extension StoreSnapshot {
    public func goal(_ id: UUID) -> Goal? { goals.first { $0.id == id } }
    public func habit(_ id: UUID) -> Habit? { habits.first { $0.id == id } }
    public func system(_ id: UUID) -> GoalSystem? { systems.first { $0.id == id } }
    public func objective(_ id: UUID) -> Objective? { objectives.first { $0.id == id } }
    public func block(_ id: UUID) -> CalendarBlock? { blocks.first { $0.id == id } }
    public func blockRule(_ id: UUID) -> BlockRule? { blockRules.first { $0.id == id } }

    /// Goals sorted by `sortIndex`.
    public var sortedGoals: [Goal] { goals.sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) } }

    /// Non-archived habits of a goal, by `sortIndex`.
    public func activeHabits(goalID: UUID) -> [Habit] {
        habits.filter { $0.goalID == goalID && !$0.isArchived }.sorted { $0.sortIndex < $1.sortIndex }
    }

    public func logs(habitID: UUID) -> [HabitLog] { logs.filter { $0.habitID == habitID } }

    public func log(habitID: UUID, day: LocalDay) -> HabitLog? {
        logs.first { $0.habitID == habitID && $0.day == day }
    }

    public func weekReview(goalID: UUID, week: Week) -> WeekReview? {
        weekReviews.first { $0.goalID == goalID && $0.weekStart == week.start }
    }

    public func systems(goalID: UUID) -> [GoalSystem] {
        systems.filter { $0.goalID == goalID }.sorted { $0.sortIndex < $1.sortIndex }
    }

    public func firstPrinciples(goalID: UUID) -> [FirstPrinciple] {
        firstPrinciples.filter { $0.goalID == goalID }.sorted { $0.sortIndex < $1.sortIndex }
    }

    public func objectives(goalID: UUID) -> [Objective] {
        objectives.filter { $0.goalID == goalID }.sorted { $0.sortIndex < $1.sortIndex }
    }
}
