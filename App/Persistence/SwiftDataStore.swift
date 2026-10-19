import Foundation
import Observation
import SwiftData
import CoreKit

/// The live `Store`: SwiftData at `Application Support/LockIn.store` (DESIGN.md §3, §9.3).
///
/// - Everything runs on the main actor with the container's `mainContext`; autosave is off, so a change either saves
///   completely or is rolled back.
/// - `revision` goes up after every successful save. `snapshot()` is cached until then, so views can call it freely.
/// - If the persistent store cannot be opened, an in-memory store takes over and `loadError` says why (§7.2).
@Observable
@MainActor
final class SwiftDataStore: Store {
    private(set) var revision: Int = 0
    private(set) var loadError: String?

    private let container: ModelContainer
    private let context: ModelContext
    /// Not observed: it is refilled from inside `snapshot()`, which views call while rendering.
    @ObservationIgnored private var cachedSnapshot: StoreSnapshot?

    init(inMemory: Bool = false) {
        let schema = Schema([
            GoalRecord.self,
            FirstPrincipleRecord.self,
            GoalSystemRecord.self,
            ObjectiveRecord.self,
            StepRecord.self,
            HabitRecord.self,
            HabitLogRecord.self,
            WeekReviewRecord.self,
            BlockRuleRecord.self,
            CalendarBlockRecord.self,
            PlanReminderRecord.self,
            SettingsRecord.self,
        ])

        var failure: String?
        let container: ModelContainer
        if inMemory {
            container = SwiftDataStore.makeInMemoryContainer(schema)
        } else {
            do {
                container = try SwiftDataStore.makePersistentContainer(schema)
            } catch {
                failure = "Your data couldn't load. \(error.localizedDescription)"
                container = SwiftDataStore.makeInMemoryContainer(schema)
            }
        }

        self.container = container
        self.context = container.mainContext
        self.loadError = failure
        self.context.autosaveEnabled = false
        ensureSettingsRecord()
    }

    // MARK: - Container

    private static func makePersistentContainer(_ schema: Schema) throws -> ModelContainer {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("LockIn.store"),
                                               cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func makeInMemoryContainer(_ schema: Schema) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Lock in: the in-memory store couldn't be created: \(error)")
        }
    }

    /// The store always holds one settings record (created with `AppSettings.defaults` on first run).
    private func ensureSettingsRecord() {
        do {
            let existing = try context.fetch(FetchDescriptor<SettingsRecord>())
            guard existing.isEmpty else { return }
            let record = SettingsRecord(id: UUID())
            context.insert(record)
            record.update(from: AppSettings.defaults)
            try context.save()
        } catch {
            context.rollback()
        }
    }

    // MARK: - Store

    func snapshot() -> StoreSnapshot {
        // Reading `revision` makes a view that only calls snapshot() re-render when the store changes.
        _ = revision
        if let cachedSnapshot { return cachedSnapshot }
        guard let built = try? buildSnapshot() else { return StoreSnapshot.empty }
        cachedSnapshot = built
        return built
    }

    func apply(_ changes: ChangeSet) throws {
        do {
            let applier = PersistenceChangeApplier(context: context)
            try applier.apply(changes, now: Date())
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        didChange()
    }

    func replaceAll(with snapshot: StoreSnapshot) throws {
        do {
            let applier = PersistenceChangeApplier(context: context)
            try applier.replaceAll(with: snapshot)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        didChange()
    }

    private func didChange() {
        cachedSnapshot = nil
        revision += 1
    }

    // MARK: - Reading

    private func buildSnapshot() throws -> StoreSnapshot {
        let settingsRecords = try context.fetch(FetchDescriptor<SettingsRecord>())
        let settings = settingsRecords.sorted { $0.id.uuidString < $1.id.uuidString }.first?.domain
            ?? AppSettings.defaults

        let goals = try context.fetch(FetchDescriptor<GoalRecord>()).map { $0.domain }
            .sorted { ($0.sortIndex, $0.createdAt, $0.id.uuidString) < ($1.sortIndex, $1.createdAt, $1.id.uuidString) }
        let firstPrinciples = try context.fetch(FetchDescriptor<FirstPrincipleRecord>()).map { $0.domain }
            .sorted { ($0.sortIndex, $0.id.uuidString) < ($1.sortIndex, $1.id.uuidString) }
        let systems = try context.fetch(FetchDescriptor<GoalSystemRecord>()).map { $0.domain }
            .sorted { ($0.sortIndex, $0.id.uuidString) < ($1.sortIndex, $1.id.uuidString) }
        let objectives = try context.fetch(FetchDescriptor<ObjectiveRecord>()).map { $0.domain }
            .sorted { ($0.sortIndex, $0.id.uuidString) < ($1.sortIndex, $1.id.uuidString) }
        let steps = try context.fetch(FetchDescriptor<StepRecord>()).map { $0.domain }
            .sorted { ($0.sortIndex, $0.id.uuidString) < ($1.sortIndex, $1.id.uuidString) }
        let habits = try context.fetch(FetchDescriptor<HabitRecord>()).map { $0.domain }
            .sorted { ($0.sortIndex, $0.createdAt, $0.id.uuidString) < ($1.sortIndex, $1.createdAt, $1.id.uuidString) }
        let logs = try context.fetch(FetchDescriptor<HabitLogRecord>()).map { $0.domain }
            .sorted { ($0.day, $0.loggedAt, $0.id.uuidString) < ($1.day, $1.loggedAt, $1.id.uuidString) }
        let weekReviews = try context.fetch(FetchDescriptor<WeekReviewRecord>()).map { $0.domain }
            .sorted { ($0.weekStart, $0.id.uuidString) < ($1.weekStart, $1.id.uuidString) }
        let blockRules = try context.fetch(FetchDescriptor<BlockRuleRecord>()).map { $0.domain }
            .sorted { ($0.title, $0.id.uuidString) < ($1.title, $1.id.uuidString) }
        let blocks = try context.fetch(FetchDescriptor<CalendarBlockRecord>()).map { $0.domain }
            .sorted { ($0.start, $0.id.uuidString) < ($1.start, $1.id.uuidString) }
        let reminders = try context.fetch(FetchDescriptor<PlanReminderRecord>()).map { $0.domain }
            .sorted { ($0.time, $0.id.uuidString) < ($1.time, $1.id.uuidString) }

        return StoreSnapshot(settings: settings, goals: goals, firstPrinciples: firstPrinciples, systems: systems,
                             objectives: objectives, steps: steps, habits: habits, logs: logs,
                             weekReviews: weekReviews, blockRules: blockRules, blocks: blocks, reminders: reminders)
    }
}
