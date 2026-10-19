import Foundation

// MARK: - Enums

public enum Mark: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case D, B, M
}

public enum GoalStatus: String, Codable, Equatable, Sendable, CaseIterable {
    case active, paused, achieved, dropped
}

public enum ResultDirection: String, Codable, Equatable, Sendable {
    case down, up
}

public enum SystemKind: String, Codable, Equatable, Sendable {
    case principle, sustaining
}

public enum ObjectiveStatus: String, Codable, Equatable, Sendable, CaseIterable {
    case notStarted, inProgress, done
}

public enum HabitKind: String, Codable, Equatable, Sendable {
    case check, count
}

public enum BlockStatus: String, Codable, Equatable, Sendable {
    case scheduled, clash, done, cancelled
}

/// How often a habit is scheduled. Encoded as `{"type": "daily" | "weekdays" | "perWeek", "weekdays": [...], "timesPerWeek": n}`.
public enum Frequency: Codable, Equatable, Hashable, Sendable {
    case daily
    /// ISO weekdays, 1 = Monday … 7 = Sunday.
    case weekdays([Int])
    /// 1…7 times a week, on any days.
    case perWeek(Int)

    private enum CodingKeys: String, CodingKey { case type, weekdays, timesPerWeek }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "daily": self = .daily
        case "weekdays": self = .weekdays(try c.decode([Int].self, forKey: .weekdays))
        case "perWeek": self = .perWeek(try c.decode(Int.self, forKey: .timesPerWeek))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown frequency \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .daily:
            try c.encode("daily", forKey: .type)
        case .weekdays(let days):
            try c.encode("weekdays", forKey: .type)
            try c.encode(days, forKey: .weekdays)
        case .perWeek(let n):
            try c.encode("perWeek", forKey: .type)
            try c.encode(n, forKey: .timesPerWeek)
        }
    }
}

// MARK: - Entities (DESIGN.md §3)

/// §3.1
public struct Goal: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var planKey: String?
    public var title: String
    public var outcome: String
    public var deadline: LocalDay
    public var bufferDays: Int
    public var status: GoalStatus
    public var resultName: String
    public var resultUnit: String
    public var resultStart: Double
    public var resultTarget: Double
    public var resultDirection: ResultDirection
    public var bottleneckHabitID: UUID?
    public var sortIndex: Int
    public var createdAt: Date
    public var importedPlanJSON: String?

    public init(id: UUID = UUID(), planKey: String? = nil, title: String, outcome: String = "", deadline: LocalDay,
                bufferDays: Int = 7, status: GoalStatus = .active, resultName: String = "", resultUnit: String = "",
                resultStart: Double = 0, resultTarget: Double = 0, resultDirection: ResultDirection = .up,
                bottleneckHabitID: UUID? = nil, sortIndex: Int = 0, createdAt: Date = Date(), importedPlanJSON: String? = nil) {
        self.id = id; self.planKey = planKey; self.title = title; self.outcome = outcome; self.deadline = deadline
        self.bufferDays = bufferDays; self.status = status; self.resultName = resultName; self.resultUnit = resultUnit
        self.resultStart = resultStart; self.resultTarget = resultTarget; self.resultDirection = resultDirection
        self.bottleneckHabitID = bottleneckHabitID; self.sortIndex = sortIndex; self.createdAt = createdAt
        self.importedPlanJSON = importedPlanJSON
    }
}

/// §3.2
public struct FirstPrinciple: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var planKey: String?
    public var goalID: UUID
    public var title: String
    public var why: String
    public var sortIndex: Int

    public init(id: UUID = UUID(), planKey: String? = nil, goalID: UUID, title: String, why: String = "", sortIndex: Int = 0) {
        self.id = id; self.planKey = planKey; self.goalID = goalID; self.title = title; self.why = why; self.sortIndex = sortIndex
    }
}

/// §3.3
public struct GoalSystem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var planKey: String?
    public var goalID: UUID
    /// nil when `kind == .sustaining`.
    public var firstPrincipleID: UUID?
    public var kind: SystemKind
    public var title: String
    public var location: String?
    public var sortIndex: Int

    public init(id: UUID = UUID(), planKey: String? = nil, goalID: UUID, firstPrincipleID: UUID? = nil,
                kind: SystemKind = .principle, title: String, location: String? = nil, sortIndex: Int = 0) {
        self.id = id; self.planKey = planKey; self.goalID = goalID; self.firstPrincipleID = firstPrincipleID
        self.kind = kind; self.title = title; self.location = location; self.sortIndex = sortIndex
    }
}

/// §3.4 — a milestone, one node of the goal's DAG.
public struct Objective: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var planKey: String?
    public var goalID: UUID
    public var title: String
    public var deadline: LocalDay?
    public var deadlineOverridden: Bool
    /// ≥ 1
    public var estimatedDays: Int
    public var status: ObjectiveStatus
    /// Other objectives of the same goal that must finish first. Must stay acyclic.
    public var dependsOnIDs: [UUID]
    public var systemIDs: [UUID]
    public var sortIndex: Int

    public init(id: UUID = UUID(), planKey: String? = nil, goalID: UUID, title: String, deadline: LocalDay? = nil,
                deadlineOverridden: Bool = false, estimatedDays: Int = 7, status: ObjectiveStatus = .notStarted,
                dependsOnIDs: [UUID] = [], systemIDs: [UUID] = [], sortIndex: Int = 0) {
        self.id = id; self.planKey = planKey; self.goalID = goalID; self.title = title; self.deadline = deadline
        self.deadlineOverridden = deadlineOverridden; self.estimatedDays = estimatedDays; self.status = status
        self.dependsOnIDs = dependsOnIDs; self.systemIDs = systemIDs; self.sortIndex = sortIndex
    }
}

/// §3.5
public struct Step: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var planKey: String?
    public var objectiveID: UUID
    public var title: String
    /// nil = inherits the objective's deadline.
    public var deadline: LocalDay?
    public var estimatedMinutes: Int
    public var done: Bool
    public var sortIndex: Int

    public init(id: UUID = UUID(), planKey: String? = nil, objectiveID: UUID, title: String, deadline: LocalDay? = nil,
                estimatedMinutes: Int = 30, done: Bool = false, sortIndex: Int = 0) {
        self.id = id; self.planKey = planKey; self.objectiveID = objectiveID; self.title = title; self.deadline = deadline
        self.estimatedMinutes = estimatedMinutes; self.done = done; self.sortIndex = sortIndex
    }
}

/// §3.6
public struct Habit: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var planKey: String?
    /// nil = standalone habit.
    public var systemID: UUID?
    /// Copied from the system; nil if standalone.
    public var goalID: UUID?
    public var title: String
    public var badDayTitle: String
    public var kind: HabitKind
    /// 1 for `check`.
    public var target: Int
    /// 1 for `check`; for `count`, 1 ≤ badDayTarget < target.
    public var badDayTarget: Int
    public var unit: String?
    public var frequency: Frequency
    /// Only for perWeek: the days nudges may fire. Empty = no nudges.
    public var preferredWeekdays: [Int]
    /// 1 … scheduled occurrences per week.
    public var setPointPerWeek: Int
    /// Minutes after midnight; nil = untimed.
    public var reminderTime: Int?
    public var durationMinutes: Int
    public var isPhysical: Bool
    /// 1 (highest) … 5.
    public var priority: Int
    public var isArchived: Bool
    public var createdAt: Date
    /// Display order within its section; also the last bottleneck tie-break (§4.6). BUILD_PLAN §2 addition.
    public var sortIndex: Int

    public init(id: UUID = UUID(), planKey: String? = nil, systemID: UUID? = nil, goalID: UUID? = nil, title: String,
                badDayTitle: String, kind: HabitKind = .check, target: Int = 1, badDayTarget: Int = 1, unit: String? = nil,
                frequency: Frequency = .daily, preferredWeekdays: [Int] = [], setPointPerWeek: Int? = nil,
                reminderTime: Int? = nil, durationMinutes: Int = 15, isPhysical: Bool = false, priority: Int = 3,
                isArchived: Bool = false, createdAt: Date = Date(), sortIndex: Int = 0) {
        self.id = id; self.planKey = planKey; self.systemID = systemID; self.goalID = goalID; self.title = title
        self.badDayTitle = badDayTitle; self.kind = kind; self.target = target; self.badDayTarget = badDayTarget
        self.unit = unit; self.frequency = frequency; self.preferredWeekdays = preferredWeekdays
        self.setPointPerWeek = setPointPerWeek ?? Habit.scheduledPerWeek(frequency)
        self.reminderTime = reminderTime; self.durationMinutes = durationMinutes; self.isPhysical = isPhysical
        self.priority = priority; self.isArchived = isArchived; self.createdAt = createdAt; self.sortIndex = sortIndex
    }

    /// `daily` = 7, `weekdays(d)` = d.count, `perWeek(n)` = n (§4.6).
    public static func scheduledPerWeek(_ frequency: Frequency) -> Int {
        switch frequency {
        case .daily: 7
        case .weekdays(let days): Set(days).count
        case .perWeek(let n): n
        }
    }
}

/// §3.7 — unique per (habitID, day).
public struct HabitLog: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var habitID: UUID
    public var day: LocalDay
    public var mark: Mark
    /// Count habits only; the mark is derived from it.
    public var count: Int?
    public var loggedAt: Date

    public init(id: UUID = UUID(), habitID: UUID, day: LocalDay, mark: Mark, count: Int? = nil, loggedAt: Date = Date()) {
        self.id = id; self.habitID = habitID; self.day = day; self.mark = mark; self.count = count; self.loggedAt = loggedAt
    }
}

/// §3.8 — unique per (goalID, weekStart).
public struct WeekReview: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var goalID: UUID
    /// A Monday.
    public var weekStart: LocalDay
    public var resultValue: Double?
    public var bottleneckHabitID: UUID?
    public var note: String?
    /// nil = still open.
    public var finishedAt: Date?

    public init(id: UUID = UUID(), goalID: UUID, weekStart: LocalDay, resultValue: Double? = nil,
                bottleneckHabitID: UUID? = nil, note: String? = nil, finishedAt: Date? = nil) {
        self.id = id; self.goalID = goalID; self.weekStart = weekStart; self.resultValue = resultValue
        self.bottleneckHabitID = bottleneckHabitID; self.note = note; self.finishedAt = finishedAt
    }
}

/// §3.9 — recurring block template.
public struct BlockRule: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var planKey: String?
    public var systemID: UUID
    public var title: String
    public var durationMinutes: Int
    public var weekdays: [Int]
    public var startTime: Int
    public var windowStart: Int
    public var windowEnd: Int
    public var isPhysical: Bool
    public var nudge: Bool
    public var active: Bool

    public init(id: UUID = UUID(), planKey: String? = nil, systemID: UUID, title: String, durationMinutes: Int = 60,
                weekdays: [Int], startTime: Int, windowStart: Int? = nil, windowEnd: Int? = nil,
                isPhysical: Bool = false, nudge: Bool = false, active: Bool = true) {
        self.id = id; self.planKey = planKey; self.systemID = systemID; self.title = title
        self.durationMinutes = durationMinutes; self.weekdays = weekdays; self.startTime = startTime
        self.windowStart = windowStart ?? startTime; self.windowEnd = windowEnd ?? (startTime + durationMinutes)
        self.isPhysical = isPhysical; self.nudge = nudge; self.active = active
    }
}

/// §3.10 — one concrete block. The only entity that syncs with Apple Calendar.
public struct CalendarBlock: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    /// nil = one-off block.
    public var ruleID: UUID?
    public var systemID: UUID?
    public var goalID: UUID?
    public var title: String
    public var start: Date
    public var end: Date
    public var status: BlockStatus
    /// External events the user chose "Keep" against.
    public var ignoredClashEventIDs: [String]
    /// Set when status == .clash.
    public var suggestedStart: Date?
    public var ekEventIdentifier: String?
    public var ekExternalIdentifier: String?
    public var lastSyncedAt: Date?
    public var isPhysical: Bool
    public var nudge: Bool

    public init(id: UUID = UUID(), ruleID: UUID? = nil, systemID: UUID? = nil, goalID: UUID? = nil, title: String,
                start: Date, end: Date, status: BlockStatus = .scheduled, ignoredClashEventIDs: [String] = [],
                suggestedStart: Date? = nil, ekEventIdentifier: String? = nil, ekExternalIdentifier: String? = nil,
                lastSyncedAt: Date? = nil, isPhysical: Bool = false, nudge: Bool = false) {
        self.id = id; self.ruleID = ruleID; self.systemID = systemID; self.goalID = goalID; self.title = title
        self.start = start; self.end = end; self.status = status; self.ignoredClashEventIDs = ignoredClashEventIDs
        self.suggestedStart = suggestedStart; self.ekEventIdentifier = ekEventIdentifier
        self.ekExternalIdentifier = ekExternalIdentifier; self.lastSyncedAt = lastSyncedAt
        self.isPhysical = isPhysical; self.nudge = nudge
    }

    /// The local day the block starts on.
    public var day: LocalDay { LocalDay(start) }
    public var durationMinutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

/// §3.11 — a one-off (`date`) or repeating (`weekdays`) reminder from a plan.
public struct PlanReminder: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var planKey: String?
    public var systemID: UUID?
    public var title: String
    public var body: String
    public var date: LocalDay?
    public var weekdays: [Int]
    public var time: Int
    public var priority: Int
    public var active: Bool

    public init(id: UUID = UUID(), planKey: String? = nil, systemID: UUID? = nil, title: String, body: String = "",
                date: LocalDay? = nil, weekdays: [Int] = [], time: Int, priority: Int = 3, active: Bool = true) {
        self.id = id; self.planKey = planKey; self.systemID = systemID; self.title = title; self.body = body
        self.date = date; self.weekdays = weekdays; self.time = time; self.priority = priority; self.active = active
    }
}

/// §3.12 `TimeWindow { weekday, start, end }` (minutes after midnight).
public struct TimeWindow: Codable, Equatable, Hashable, Sendable {
    public var weekday: Int
    public var start: Int
    public var end: Int

    public init(weekday: Int, start: Int, end: Int) {
        self.weekday = weekday; self.start = start; self.end = end
    }
}

/// §3.12 — a single record.
public struct AppSettings: Codable, Equatable, Sendable {
    public var morningTimeWeekday: Int
    public var morningTimeWeekend: Int
    public var eveningTime: Int
    public var checkInWeekday: Int
    public var checkInTime: Int
    /// Fixed at 6 in the MVP; shown read-only.
    public var maxNotificationsPerDay: Int
    public var maxTimedNudgesPerDay: Int
    public var bestHours: [TimeWindow]
    public var saturdayOff: Bool
    public var travelBufferMinutes: Int
    public var goalsCalendarIdentifier: String?
    public var backupFolderBookmark: Data?
    public var lastBackupAt: Date?
    public var onboardingDone: Bool

    public init(morningTimeWeekday: Int = 450, morningTimeWeekend: Int = 540, eveningTime: Int = 1290,
                checkInWeekday: Int = 1, checkInTime: Int = 1140, maxNotificationsPerDay: Int = 6,
                maxTimedNudgesPerDay: Int = 4, bestHours: [TimeWindow] = AppSettings.defaultBestHours,
                saturdayOff: Bool = true, travelBufferMinutes: Int = 15, goalsCalendarIdentifier: String? = nil,
                backupFolderBookmark: Data? = nil, lastBackupAt: Date? = nil, onboardingDone: Bool = false) {
        self.morningTimeWeekday = morningTimeWeekday; self.morningTimeWeekend = morningTimeWeekend
        self.eveningTime = eveningTime; self.checkInWeekday = checkInWeekday; self.checkInTime = checkInTime
        self.maxNotificationsPerDay = maxNotificationsPerDay; self.maxTimedNudgesPerDay = maxTimedNudgesPerDay
        self.bestHours = bestHours; self.saturdayOff = saturdayOff; self.travelBufferMinutes = travelBufferMinutes
        self.goalsCalendarIdentifier = goalsCalendarIdentifier; self.backupFolderBookmark = backupFolderBookmark
        self.lastBackupAt = lastBackupAt; self.onboardingDone = onboardingDone
    }

    public static let defaults = AppSettings()

    /// Mon–Fri 08:00–10:00, 14:00–17:00, 19:00–21:00; Sun 10:00–13:00, 16:00–19:00 (O3).
    public static let defaultBestHours: [TimeWindow] =
        (1...5).flatMap { day in
            [TimeWindow(weekday: day, start: 480, end: 600),
             TimeWindow(weekday: day, start: 840, end: 1020),
             TimeWindow(weekday: day, start: 1140, end: 1260)]
        } + [TimeWindow(weekday: 7, start: 600, end: 780), TimeWindow(weekday: 7, start: 960, end: 1140)]

    /// Morning summary time for a given ISO weekday (weekend = 6, 7).
    public func morningTime(on weekday: Int) -> Int { weekday >= 6 ? morningTimeWeekend : morningTimeWeekday }
}
