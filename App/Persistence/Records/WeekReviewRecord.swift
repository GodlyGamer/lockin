import Foundation
import SwiftData

/// SwiftData mirror of `WeekReview` (DESIGN.md §3.8). (goalID, weekStart) is unique; `SwiftDataStore` enforces it on upsert.
@Model
final class WeekReviewRecord {
    @Attribute(.unique) var id: UUID
    var goalID: UUID = UUID()
    /// `LocalDay` (a Monday) as "YYYY-MM-DD".
    var weekStart: String = ""
    var resultValue: Double?
    var bottleneckHabitID: UUID?
    var note: String?
    /// nil = still open.
    var finishedAt: Date?

    var goal: GoalRecord?

    init(id: UUID) {
        self.id = id
    }
}
