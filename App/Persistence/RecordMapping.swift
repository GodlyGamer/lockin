import Foundation
import CoreKit

// Mapping between the `@Model` records and the CoreKit structs.
//
// `update(from:)` copies every field of a struct onto a record (foreign keys included; relationships are linked
// separately by `PersistenceChangeApplier`). `domain` rebuilds the struct. An unreadable stored value (which only
// corruption can produce) falls back to a sane default instead of failing the whole snapshot.

// MARK: - Stored-value helpers

/// JSON and `LocalDay` helpers for the `Data` / `String` attributes. Stateless, so safe from any isolation.
nonisolated enum PersistenceCoding {
    static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, fallback: T) -> T {
        (try? JSONDecoder().decode(type, from: data)) ?? fallback
    }

    /// A required day. Corrupt text falls back to today.
    static func day(_ text: String) -> LocalDay {
        LocalDay(text) ?? LocalDay.today
    }

    static func optionalDay(_ text: String?) -> LocalDay? {
        guard let text else { return nil }
        return LocalDay(text)
    }
}

// MARK: - Goal

extension GoalRecord {
    func update(from goal: Goal) {
        planKey = goal.planKey
        title = goal.title
        outcome = goal.outcome
        deadline = goal.deadline.string
        bufferDays = goal.bufferDays
        status = goal.status.rawValue
        resultName = goal.resultName
        resultUnit = goal.resultUnit
        resultStart = goal.resultStart
        resultTarget = goal.resultTarget
        resultDirection = goal.resultDirection.rawValue
        bottleneckHabitID = goal.bottleneckHabitID
        sortIndex = goal.sortIndex
        createdAt = goal.createdAt
        importedPlanJSON = goal.importedPlanJSON
    }

    var domain: Goal {
        Goal(id: id, planKey: planKey, title: title, outcome: outcome,
             deadline: PersistenceCoding.day(deadline), bufferDays: bufferDays,
             status: GoalStatus(rawValue: status) ?? .active,
             resultName: resultName, resultUnit: resultUnit, resultStart: resultStart, resultTarget: resultTarget,
             resultDirection: ResultDirection(rawValue: resultDirection) ?? .up,
             bottleneckHabitID: bottleneckHabitID, sortIndex: sortIndex, createdAt: createdAt,
             importedPlanJSON: importedPlanJSON)
    }
}

// MARK: - FirstPrinciple

extension FirstPrincipleRecord {
    func update(from principle: FirstPrinciple) {
        planKey = principle.planKey
        goalID = principle.goalID
        title = principle.title
        why = principle.why
        sortIndex = principle.sortIndex
    }

    var domain: FirstPrinciple {
        FirstPrinciple(id: id, planKey: planKey, goalID: goalID, title: title, why: why, sortIndex: sortIndex)
    }
}

// MARK: - GoalSystem

extension GoalSystemRecord {
    func update(from system: GoalSystem) {
        planKey = system.planKey
        goalID = system.goalID
        firstPrincipleID = system.firstPrincipleID
        kind = system.kind.rawValue
        title = system.title
        location = system.location
        sortIndex = system.sortIndex
    }

    var domain: GoalSystem {
        GoalSystem(id: id, planKey: planKey, goalID: goalID, firstPrincipleID: firstPrincipleID,
                   kind: SystemKind(rawValue: kind) ?? .principle, title: title, location: location, sortIndex: sortIndex)
    }
}

// MARK: - Objective

extension ObjectiveRecord {
    func update(from objective: Objective) {
        planKey = objective.planKey
        goalID = objective.goalID
        title = objective.title
        deadline = objective.deadline?.string
        deadlineOverridden = objective.deadlineOverridden
        estimatedDays = objective.estimatedDays
        status = objective.status.rawValue
        dependsOnIDsJSON = PersistenceCoding.encode(objective.dependsOnIDs)
        systemIDsJSON = PersistenceCoding.encode(objective.systemIDs)
        sortIndex = objective.sortIndex
    }

    var dependsOnIDs: [UUID] {
        PersistenceCoding.decode([UUID].self, from: dependsOnIDsJSON, fallback: [])
    }

    var systemIDs: [UUID] {
        PersistenceCoding.decode([UUID].self, from: systemIDsJSON, fallback: [])
    }

    var domain: Objective {
        Objective(id: id, planKey: planKey, goalID: goalID, title: title,
                  deadline: PersistenceCoding.optionalDay(deadline), deadlineOverridden: deadlineOverridden,
                  estimatedDays: estimatedDays, status: ObjectiveStatus(rawValue: status) ?? .notStarted,
                  dependsOnIDs: dependsOnIDs, systemIDs: systemIDs, sortIndex: sortIndex)
    }
}

// MARK: - Step

extension StepRecord {
    func update(from step: Step) {
        planKey = step.planKey
        objectiveID = step.objectiveID
        title = step.title
        deadline = step.deadline?.string
        estimatedMinutes = step.estimatedMinutes
        done = step.done
        sortIndex = step.sortIndex
    }

    var domain: Step {
        Step(id: id, planKey: planKey, objectiveID: objectiveID, title: title,
             deadline: PersistenceCoding.optionalDay(deadline), estimatedMinutes: estimatedMinutes, done: done,
             sortIndex: sortIndex)
    }
}

// MARK: - Habit

extension HabitRecord {
    func update(from habit: Habit) {
        planKey = habit.planKey
        systemID = habit.systemID
        goalID = habit.goalID
        title = habit.title
        badDayTitle = habit.badDayTitle
        kind = habit.kind.rawValue
        target = habit.target
        badDayTarget = habit.badDayTarget
        unit = habit.unit
        frequencyJSON = PersistenceCoding.encode(habit.frequency)
        preferredWeekdaysJSON = PersistenceCoding.encode(habit.preferredWeekdays)
        setPointPerWeek = habit.setPointPerWeek
        reminderTime = habit.reminderTime
        durationMinutes = habit.durationMinutes
        isPhysical = habit.isPhysical
        priority = habit.priority
        isArchived = habit.isArchived
        createdAt = habit.createdAt
        sortIndex = habit.sortIndex
    }

    var domain: Habit {
        Habit(id: id, planKey: planKey, systemID: systemID, goalID: goalID, title: title, badDayTitle: badDayTitle,
              kind: HabitKind(rawValue: kind) ?? .check, target: target, badDayTarget: badDayTarget, unit: unit,
              frequency: PersistenceCoding.decode(Frequency.self, from: frequencyJSON, fallback: .daily),
              preferredWeekdays: PersistenceCoding.decode([Int].self, from: preferredWeekdaysJSON, fallback: []),
              setPointPerWeek: setPointPerWeek, reminderTime: reminderTime, durationMinutes: durationMinutes,
              isPhysical: isPhysical, priority: priority, isArchived: isArchived, createdAt: createdAt,
              sortIndex: sortIndex)
    }
}

// MARK: - HabitLog

extension HabitLogRecord {
    func update(from log: HabitLog) {
        habitID = log.habitID
        day = log.day.string
        mark = log.mark.rawValue
        count = log.count
        loggedAt = log.loggedAt
    }

    var domain: HabitLog {
        HabitLog(id: id, habitID: habitID, day: PersistenceCoding.day(day), mark: Mark(rawValue: mark) ?? .M,
                 count: count, loggedAt: loggedAt)
    }
}

// MARK: - WeekReview

extension WeekReviewRecord {
    func update(from review: WeekReview) {
        goalID = review.goalID
        weekStart = review.weekStart.string
        resultValue = review.resultValue
        bottleneckHabitID = review.bottleneckHabitID
        note = review.note
        finishedAt = review.finishedAt
    }

    var domain: WeekReview {
        WeekReview(id: id, goalID: goalID, weekStart: PersistenceCoding.day(weekStart), resultValue: resultValue,
                   bottleneckHabitID: bottleneckHabitID, note: note, finishedAt: finishedAt)
    }
}

// MARK: - BlockRule

extension BlockRuleRecord {
    func update(from rule: BlockRule) {
        planKey = rule.planKey
        systemID = rule.systemID
        title = rule.title
        durationMinutes = rule.durationMinutes
        weekdaysJSON = PersistenceCoding.encode(rule.weekdays)
        startTime = rule.startTime
        windowStart = rule.windowStart
        windowEnd = rule.windowEnd
        isPhysical = rule.isPhysical
        nudge = rule.nudge
        active = rule.active
    }

    var domain: BlockRule {
        BlockRule(id: id, planKey: planKey, systemID: systemID, title: title, durationMinutes: durationMinutes,
                  weekdays: PersistenceCoding.decode([Int].self, from: weekdaysJSON, fallback: []),
                  startTime: startTime, windowStart: windowStart, windowEnd: windowEnd,
                  isPhysical: isPhysical, nudge: nudge, active: active)
    }
}

// MARK: - CalendarBlock

extension CalendarBlockRecord {
    func update(from block: CalendarBlock) {
        ruleID = block.ruleID
        systemID = block.systemID
        goalID = block.goalID
        title = block.title
        start = block.start
        end = block.end
        status = block.status.rawValue
        ignoredClashEventIDsJSON = PersistenceCoding.encode(block.ignoredClashEventIDs)
        suggestedStart = block.suggestedStart
        ekEventIdentifier = block.ekEventIdentifier
        ekExternalIdentifier = block.ekExternalIdentifier
        lastSyncedAt = block.lastSyncedAt
        isPhysical = block.isPhysical
        nudge = block.nudge
    }

    var domain: CalendarBlock {
        CalendarBlock(id: id, ruleID: ruleID, systemID: systemID, goalID: goalID, title: title, start: start, end: end,
                      status: BlockStatus(rawValue: status) ?? .scheduled,
                      ignoredClashEventIDs: PersistenceCoding.decode([String].self, from: ignoredClashEventIDsJSON, fallback: []),
                      suggestedStart: suggestedStart, ekEventIdentifier: ekEventIdentifier,
                      ekExternalIdentifier: ekExternalIdentifier, lastSyncedAt: lastSyncedAt,
                      isPhysical: isPhysical, nudge: nudge)
    }
}

// MARK: - PlanReminder

extension PlanReminderRecord {
    func update(from reminder: PlanReminder) {
        planKey = reminder.planKey
        systemID = reminder.systemID
        title = reminder.title
        body = reminder.body
        date = reminder.date?.string
        weekdaysJSON = PersistenceCoding.encode(reminder.weekdays)
        time = reminder.time
        priority = reminder.priority
        active = reminder.active
    }

    var domain: PlanReminder {
        PlanReminder(id: id, planKey: planKey, systemID: systemID, title: title, body: body,
                     date: PersistenceCoding.optionalDay(date),
                     weekdays: PersistenceCoding.decode([Int].self, from: weekdaysJSON, fallback: []),
                     time: time, priority: priority, active: active)
    }
}

// MARK: - AppSettings

extension SettingsRecord {
    func update(from settings: AppSettings) {
        morningTimeWeekday = settings.morningTimeWeekday
        morningTimeWeekend = settings.morningTimeWeekend
        eveningTime = settings.eveningTime
        checkInWeekday = settings.checkInWeekday
        checkInTime = settings.checkInTime
        maxNotificationsPerDay = settings.maxNotificationsPerDay
        maxTimedNudgesPerDay = settings.maxTimedNudgesPerDay
        bestHoursJSON = PersistenceCoding.encode(settings.bestHours)
        saturdayOff = settings.saturdayOff
        travelBufferMinutes = settings.travelBufferMinutes
        goalsCalendarIdentifier = settings.goalsCalendarIdentifier
        backupFolderBookmark = settings.backupFolderBookmark
        lastBackupAt = settings.lastBackupAt
        onboardingDone = settings.onboardingDone
    }

    var domain: AppSettings {
        AppSettings(morningTimeWeekday: morningTimeWeekday, morningTimeWeekend: morningTimeWeekend,
                    eveningTime: eveningTime, checkInWeekday: checkInWeekday, checkInTime: checkInTime,
                    maxNotificationsPerDay: maxNotificationsPerDay, maxTimedNudgesPerDay: maxTimedNudgesPerDay,
                    bestHours: PersistenceCoding.decode([TimeWindow].self, from: bestHoursJSON,
                                                        fallback: AppSettings.defaultBestHours),
                    saturdayOff: saturdayOff, travelBufferMinutes: travelBufferMinutes,
                    goalsCalendarIdentifier: goalsCalendarIdentifier, backupFolderBookmark: backupFolderBookmark,
                    lastBackupAt: lastBackupAt, onboardingDone: onboardingDone)
    }
}
