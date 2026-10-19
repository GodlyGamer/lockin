import Foundation
import SwiftData

/// All records of one type, fetched once and then kept current by `findOrCreate` / `remove`, keyed by CoreKit id.
///
/// The index lives for one `apply` / `replaceAll` call. It never relies on `fetch` seeing unsaved inserts, and the
/// records it hands out must not be touched after the context saves or rolls back.
@MainActor
final class PersistenceTable<Record: PersistentModel> {
    private let context: ModelContext
    private let idOf: (Record) -> UUID
    private var cache: [UUID: Record]?

    init(context: ModelContext, idOf: @escaping (Record) -> UUID) {
        self.context = context
        self.idOf = idOf
    }

    /// Every record, by id.
    func all() throws -> [UUID: Record] {
        if let cache { return cache }
        let fetched = try context.fetch(FetchDescriptor<Record>())
        var map: [UUID: Record] = [:]
        map.reserveCapacity(fetched.count)
        for record in fetched {
            map[idOf(record)] = record
        }
        cache = map
        return map
    }

    func record(_ id: UUID) throws -> Record? {
        try all()[id]
    }

    /// For optional foreign keys: nil in, nil out.
    func record(ifPresent id: UUID?) throws -> Record? {
        guard let id else { return nil }
        return try all()[id]
    }

    /// The record with this id, or a new one (inserted into the context) built by `make`.
    func findOrCreate(_ id: UUID, make: () -> Record) throws -> (record: Record, created: Bool) {
        if let existing = try all()[id] {
            return (existing, false)
        }
        let created = make()
        context.insert(created)
        cache?[id] = created
        return (created, true)
    }

    /// Deletes the record (if there is one) and forgets it.
    func remove(_ id: UUID) throws {
        guard let existing = try all()[id] else { return }
        context.delete(existing)
        cache?.removeValue(forKey: id)
    }
}

/// One `PersistenceTable` per record type, over the same context.
@MainActor
final class PersistenceRecordIndex {
    let goals: PersistenceTable<GoalRecord>
    let firstPrinciples: PersistenceTable<FirstPrincipleRecord>
    let systems: PersistenceTable<GoalSystemRecord>
    let objectives: PersistenceTable<ObjectiveRecord>
    let steps: PersistenceTable<StepRecord>
    let habits: PersistenceTable<HabitRecord>
    let logs: PersistenceTable<HabitLogRecord>
    let weekReviews: PersistenceTable<WeekReviewRecord>
    let blockRules: PersistenceTable<BlockRuleRecord>
    let blocks: PersistenceTable<CalendarBlockRecord>
    let reminders: PersistenceTable<PlanReminderRecord>
    let settings: PersistenceTable<SettingsRecord>

    init(context: ModelContext) {
        goals = PersistenceTable<GoalRecord>(context: context) { $0.id }
        firstPrinciples = PersistenceTable<FirstPrincipleRecord>(context: context) { $0.id }
        systems = PersistenceTable<GoalSystemRecord>(context: context) { $0.id }
        objectives = PersistenceTable<ObjectiveRecord>(context: context) { $0.id }
        steps = PersistenceTable<StepRecord>(context: context) { $0.id }
        habits = PersistenceTable<HabitRecord>(context: context) { $0.id }
        logs = PersistenceTable<HabitLogRecord>(context: context) { $0.id }
        weekReviews = PersistenceTable<WeekReviewRecord>(context: context) { $0.id }
        blockRules = PersistenceTable<BlockRuleRecord>(context: context) { $0.id }
        blocks = PersistenceTable<CalendarBlockRecord>(context: context) { $0.id }
        reminders = PersistenceTable<PlanReminderRecord>(context: context) { $0.id }
        settings = PersistenceTable<SettingsRecord>(context: context) { $0.id }
    }
}
