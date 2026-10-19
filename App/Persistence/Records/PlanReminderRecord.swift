import Foundation
import SwiftData

/// SwiftData mirror of `PlanReminder` (DESIGN.md §3.11).
@Model
final class PlanReminderRecord {
    @Attribute(.unique) var id: UUID
    var planKey: String?
    var systemID: UUID?
    var title: String = ""
    var body: String = ""
    /// `LocalDay` as "YYYY-MM-DD" for a one-off reminder, or nil.
    var date: String?
    /// JSON `[Int]` (ISO weekdays) for a repeating reminder.
    var weekdaysJSON: Data = Data()
    var time: Int = 0
    var priority: Int = 3
    var active: Bool = true

    var system: GoalSystemRecord?

    init(id: UUID) {
        self.id = id
    }
}
