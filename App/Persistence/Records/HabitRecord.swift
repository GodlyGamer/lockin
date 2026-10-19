import Foundation
import SwiftData

/// SwiftData mirror of `Habit` (DESIGN.md §3.6).
@Model
final class HabitRecord {
    @Attribute(.unique) var id: UUID
    var planKey: String?
    /// nil = standalone habit.
    var systemID: UUID?
    /// Copied from the system; nil if standalone.
    var goalID: UUID?
    var title: String = ""
    var badDayTitle: String = ""
    /// `HabitKind` raw value.
    var kind: String = "check"
    var target: Int = 1
    var badDayTarget: Int = 1
    var unit: String?
    /// JSON-encoded `Frequency`.
    var frequencyJSON: Data = Data()
    /// JSON `[Int]`.
    var preferredWeekdaysJSON: Data = Data()
    var setPointPerWeek: Int = 7
    var reminderTime: Int?
    var durationMinutes: Int = 15
    var isPhysical: Bool = false
    var priority: Int = 3
    var isArchived: Bool = false
    var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)
    var sortIndex: Int = 0

    var system: GoalSystemRecord?

    /// Deleting a habit deletes its marks (§3.6: cascade). Archiving does not delete anything.
    @Relationship(deleteRule: .cascade, inverse: \HabitLogRecord.habit)
    var logs: [HabitLogRecord] = []

    init(id: UUID) {
        self.id = id
    }
}
