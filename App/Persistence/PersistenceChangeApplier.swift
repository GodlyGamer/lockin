import Foundation
import SwiftData
import CoreKit

/// Applies a `ChangeSet` (or a whole snapshot) to a `ModelContext` with exactly the semantics of
/// `StoreSnapshot.applying` in CoreKit: upserts first, then deletes, with the §3 delete rules.
///
/// It only changes the context. `SwiftDataStore` saves afterwards, or rolls back if anything here throws.
///
/// Relationships are linked from the foreign-key UUIDs once every upsert is in, so a change set may list a child before
/// its parent. The delete rules are applied by hand from the same foreign keys (and SwiftData's own rules agree with
/// them), so a record whose relationship was never linked is still cascaded correctly.
@MainActor
final class PersistenceChangeApplier {
    private let index: PersistenceRecordIndex
    /// Records upserted so far whose relationships still need linking.
    private var touched: [EntityRef] = []
    /// "habitID|day" -> ids of logs seen for that key. Built on first use; entries can go stale, so every use re-checks.
    private var logIDsByKey: [String: [UUID]]?

    init(context: ModelContext) {
        index = PersistenceRecordIndex(context: context)
    }

    // MARK: - Entry points

    /// Upserts by id, then deletes by reference. `now` splits a deleted rule's blocks into future (deleted) and past (kept).
    func apply(_ changes: ChangeSet, now: Date) throws {
        for entity in changes.upserts {
            try upsert(entity)
        }
        try linkTouched()
        for ref in changes.deletes {
            try delete(ref, now: now)
        }
    }

    /// Makes the store equal to `snapshot`: upserts everything in it, then drops what it does not contain.
    /// (Updating in place rather than deleting and re-inserting keeps the unique ids from clashing inside one save.)
    func replaceAll(with snapshot: StoreSnapshot) throws {
        try upsert(.settings(snapshot.settings))
        for entity in snapshot.goals { try upsert(.goal(entity)) }
        for entity in snapshot.firstPrinciples { try upsert(.firstPrinciple(entity)) }
        for entity in snapshot.systems { try upsert(.system(entity)) }
        for entity in snapshot.objectives { try upsert(.objective(entity)) }
        for entity in snapshot.steps { try upsert(.step(entity)) }
        for entity in snapshot.habits { try upsert(.habit(entity)) }
        for entity in snapshot.logs { try upsert(.log(entity)) }
        for entity in snapshot.weekReviews { try upsert(.weekReview(entity)) }
        for entity in snapshot.blockRules { try upsert(.blockRule(entity)) }
        for entity in snapshot.blocks { try upsert(.block(entity)) }
        for entity in snapshot.reminders { try upsert(.reminder(entity)) }
        try linkTouched()

        // Relationships now mirror the snapshot, so removing the leftovers cannot cascade into anything that stays.
        try removeAbsent(index.goals, keeping: Set(snapshot.goals.map { $0.id }))
        try removeAbsent(index.firstPrinciples, keeping: Set(snapshot.firstPrinciples.map { $0.id }))
        try removeAbsent(index.systems, keeping: Set(snapshot.systems.map { $0.id }))
        try removeAbsent(index.objectives, keeping: Set(snapshot.objectives.map { $0.id }))
        try removeAbsent(index.steps, keeping: Set(snapshot.steps.map { $0.id }))
        try removeAbsent(index.habits, keeping: Set(snapshot.habits.map { $0.id }))
        try removeAbsent(index.logs, keeping: Set(snapshot.logs.map { $0.id }))
        try removeAbsent(index.weekReviews, keeping: Set(snapshot.weekReviews.map { $0.id }))
        try removeAbsent(index.blockRules, keeping: Set(snapshot.blockRules.map { $0.id }))
        try removeAbsent(index.blocks, keeping: Set(snapshot.blocks.map { $0.id }))
        try removeAbsent(index.reminders, keeping: Set(snapshot.reminders.map { $0.id }))
    }

    private func removeAbsent<R: PersistentModel>(_ table: PersistenceTable<R>, keeping ids: Set<UUID>) throws {
        for id in try table.all().keys where !ids.contains(id) {
            try table.remove(id)
        }
    }

    // MARK: - Upserts

    private func upsert(_ entity: AnyEntity) throws {
        switch entity {
        case .goal(let e):
            let (record, created) = try index.goals.findOrCreate(e.id) { GoalRecord(id: e.id) }
            if created || record.domain != e { record.update(from: e) }

        case .firstPrinciple(let e):
            let (record, created) = try index.firstPrinciples.findOrCreate(e.id) { FirstPrincipleRecord(id: e.id) }
            if created || record.domain != e { record.update(from: e) }
            touched.append(EntityRef(.firstPrinciple, e.id))

        case .system(let e):
            let (record, created) = try index.systems.findOrCreate(e.id) { GoalSystemRecord(id: e.id) }
            if created || record.domain != e { record.update(from: e) }
            touched.append(EntityRef(.system, e.id))

        case .objective(let e):
            let (record, created) = try index.objectives.findOrCreate(e.id) { ObjectiveRecord(id: e.id) }
            if created || record.domain != e { record.update(from: e) }
            touched.append(EntityRef(.objective, e.id))

        case .step(let e):
            let (record, created) = try index.steps.findOrCreate(e.id) { StepRecord(id: e.id) }
            if created || record.domain != e { record.update(from: e) }
            touched.append(EntityRef(.step, e.id))

        case .habit(let e):
            let (record, created) = try index.habits.findOrCreate(e.id) { HabitRecord(id: e.id) }
            if created || record.domain != e { record.update(from: e) }
            touched.append(EntityRef(.habit, e.id))

        case .log(let e):
            // (habitID, day) is unique: a log for a day that already has one replaces it.
            try removeOtherLogs(habitID: e.habitID, day: e.day, keeping: e.id)
            let (record, created) = try index.logs.findOrCreate(e.id) { HabitLogRecord(id: e.id) }
            if created || record.domain != e { record.update(from: e) }
            noteLog(record)
            touched.append(EntityRef(.log, e.id))

        case .weekReview(let e):
            // (goalID, weekStart) is unique: a review for a week that already has one replaces it.
            let weekText = e.weekStart.string
            let others = try index.weekReviews.all().values.filter {
                $0.goalID == e.goalID && $0.weekStart == weekText && $0.id != e.id
            }
            for other in others {
                try index.weekReviews.remove(other.id)
            }
            let (record, created) = try index.weekReviews.findOrCreate(e.id) { WeekReviewRecord(id: e.id) }
            if created || record.domain != e { record.update(from: e) }
            touched.append(EntityRef(.weekReview, e.id))

        case .blockRule(let e):
            let (record, created) = try index.blockRules.findOrCreate(e.id) { BlockRuleRecord(id: e.id) }
            if created || record.domain != e { record.update(from: e) }
            touched.append(EntityRef(.blockRule, e.id))

        case .block(let e):
            let (record, created) = try index.blocks.findOrCreate(e.id) { CalendarBlockRecord(id: e.id) }
            if created || record.domain != e { record.update(from: e) }

        case .reminder(let e):
            let (record, created) = try index.reminders.findOrCreate(e.id) { PlanReminderRecord(id: e.id) }
            if created || record.domain != e { record.update(from: e) }
            touched.append(EntityRef(.reminder, e.id))

        case .settings(let e):
            // There is one settings record. Should a second ever exist, the first by id wins and the rest go.
            let records = try index.settings.all().values.sorted { $0.id.uuidString < $1.id.uuidString }
            if let first = records.first {
                if first.domain != e { first.update(from: e) }
                for extra in records.dropFirst() {
                    try index.settings.remove(extra.id)
                }
            } else {
                let newID = UUID()
                let (record, _) = try index.settings.findOrCreate(newID) { SettingsRecord(id: newID) }
                record.update(from: e)
            }
        }
    }

    private func logKey(_ habitID: UUID, _ day: String) -> String {
        habitID.uuidString + "|" + day
    }

    private func removeOtherLogs(habitID: UUID, day: LocalDay, keeping id: UUID) throws {
        let dayText = day.string
        if logIDsByKey == nil {
            var keys: [String: [UUID]] = [:]
            for record in try index.logs.all().values {
                keys[logKey(record.habitID, record.day), default: []].append(record.id)
            }
            logIDsByKey = keys
        }
        let candidates = logIDsByKey?[logKey(habitID, dayText)] ?? []
        for candidate in candidates where candidate != id {
            if let record = try index.logs.record(candidate), record.habitID == habitID, record.day == dayText {
                try index.logs.remove(candidate)
            }
        }
    }

    private func noteLog(_ record: HabitLogRecord) {
        guard logIDsByKey != nil else { return }
        logIDsByKey?[logKey(record.habitID, record.day), default: []].append(record.id)
    }

    // MARK: - Relationships

    private func linkTouched() throws {
        let refs = touched
        touched.removeAll()
        for ref in refs {
            try link(ref)
        }
    }

    /// Points a record's relationships at the records its foreign keys name (or at nothing when there is no such record).
    private func link(_ ref: EntityRef) throws {
        switch ref.kind {
        case .firstPrinciple:
            guard let record = try index.firstPrinciples.record(ref.id) else { return }
            let goal = try index.goals.record(record.goalID)
            if record.goal !== goal { record.goal = goal }

        case .system:
            guard let record = try index.systems.record(ref.id) else { return }
            let goal = try index.goals.record(record.goalID)
            if record.goal !== goal { record.goal = goal }
            let principle = try index.firstPrinciples.record(ifPresent: record.firstPrincipleID)
            if record.firstPrinciple !== principle { record.firstPrinciple = principle }

        case .objective:
            guard let record = try index.objectives.record(ref.id) else { return }
            let goal = try index.goals.record(record.goalID)
            if record.goal !== goal { record.goal = goal }

        case .step:
            guard let record = try index.steps.record(ref.id) else { return }
            let objective = try index.objectives.record(record.objectiveID)
            if record.objective !== objective { record.objective = objective }

        case .habit:
            guard let record = try index.habits.record(ref.id) else { return }
            let system = try index.systems.record(ifPresent: record.systemID)
            if record.system !== system { record.system = system }

        case .log:
            guard let record = try index.logs.record(ref.id) else { return }
            let habit = try index.habits.record(record.habitID)
            if record.habit !== habit { record.habit = habit }

        case .weekReview:
            guard let record = try index.weekReviews.record(ref.id) else { return }
            let goal = try index.goals.record(record.goalID)
            if record.goal !== goal { record.goal = goal }

        case .blockRule:
            guard let record = try index.blockRules.record(ref.id) else { return }
            let system = try index.systems.record(record.systemID)
            if record.system !== system { record.system = system }

        case .reminder:
            guard let record = try index.reminders.record(ref.id) else { return }
            let system = try index.systems.record(ifPresent: record.systemID)
            if record.system !== system { record.system = system }

        case .goal, .block:
            break
        }
    }

    // MARK: - Deletes (same rules as StoreSnapshot.applying)

    private func delete(_ ref: EntityRef, now: Date) throws {
        switch ref.kind {
        case .goal: try deleteGoal(ref.id, now: now)
        case .firstPrinciple: try deleteFirstPrinciple(ref.id)
        case .system: try deleteSystem(ref.id, now: now)
        case .objective: try deleteObjective(ref.id)
        case .step: try index.steps.remove(ref.id)
        case .habit: try deleteHabit(ref.id)
        case .log: try index.logs.remove(ref.id)
        case .weekReview: try index.weekReviews.remove(ref.id)
        case .blockRule: try deleteBlockRule(ref.id, now: now)
        case .block: try index.blocks.remove(ref.id)
        case .reminder: try index.reminders.remove(ref.id)
        }
    }

    // Each helper handles the children first and removes its own record last, so nothing is read after it was
    // marked deleted, and SwiftData's cascade (which agrees with these rules) finds nothing left to do.

    /// Goal -> cascades first principles, systems, objectives and week reviews (and what hangs off them).
    private func deleteGoal(_ id: UUID, now: Date) throws {
        for principleID in try index.firstPrinciples.all().filter({ $0.value.goalID == id }).map({ $0.key }) {
            try deleteFirstPrinciple(principleID)
        }
        for systemID in try index.systems.all().filter({ $0.value.goalID == id }).map({ $0.key }) {
            try deleteSystem(systemID, now: now)
        }
        for objectiveID in try index.objectives.all().filter({ $0.value.goalID == id }).map({ $0.key }) {
            try deleteObjective(objectiveID)
        }
        for reviewID in try index.weekReviews.all().filter({ $0.value.goalID == id }).map({ $0.key }) {
            try index.weekReviews.remove(reviewID)
        }
        try index.goals.remove(id)
    }

    /// First principle -> its systems stay, with `firstPrincipleID` cleared.
    private func deleteFirstPrinciple(_ id: UUID) throws {
        for system in try index.systems.all().values where system.firstPrincipleID == id {
            system.firstPrincipleID = nil
        }
        try index.firstPrinciples.remove(id)
    }

    /// System -> its habits become standalone (`systemID` and `goalID` cleared); its block rules and reminders go;
    /// objectives stop listing it.
    private func deleteSystem(_ id: UUID, now: Date) throws {
        for habit in try index.habits.all().values where habit.systemID == id {
            habit.systemID = nil
            habit.goalID = nil
        }
        for ruleID in try index.blockRules.all().filter({ $0.value.systemID == id }).map({ $0.key }) {
            try deleteBlockRule(ruleID, now: now)
        }
        for reminderID in try index.reminders.all().filter({ $0.value.systemID == id }).map({ $0.key }) {
            try index.reminders.remove(reminderID)
        }
        for objective in try index.objectives.all().values {
            let systemIDs = objective.systemIDs
            if systemIDs.contains(id) {
                objective.systemIDsJSON = PersistenceCoding.encode(systemIDs.filter { $0 != id })
            }
        }
        try index.systems.remove(id)
    }

    /// Objective -> its steps go; other objectives stop depending on it.
    private func deleteObjective(_ id: UUID) throws {
        for stepID in try index.steps.all().filter({ $0.value.objectiveID == id }).map({ $0.key }) {
            try index.steps.remove(stepID)
        }
        for objective in try index.objectives.all().values where objective.id != id {
            let dependsOnIDs = objective.dependsOnIDs
            if dependsOnIDs.contains(id) {
                objective.dependsOnIDsJSON = PersistenceCoding.encode(dependsOnIDs.filter { $0 != id })
            }
        }
        try index.objectives.remove(id)
    }

    /// Habit -> its logs go.
    private func deleteHabit(_ id: UUID) throws {
        for logID in try index.logs.all().filter({ $0.value.habitID == id }).map({ $0.key }) {
            try index.logs.remove(logID)
        }
        try index.habits.remove(id)
    }

    /// Block rule -> its blocks starting at or after `now` go; earlier ones stay as one-off blocks (§4.4).
    private func deleteBlockRule(_ id: UUID, now: Date) throws {
        let blocks = try index.blocks.all().values.filter { $0.ruleID == id }
        for block in blocks {
            if block.start >= now {
                try index.blocks.remove(block.id)
            } else {
                block.ruleID = nil
            }
        }
        try index.blockRules.remove(id)
    }
}
