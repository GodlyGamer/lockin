import Foundation
import SwiftData

/// SwiftData mirror of `Goal` (DESIGN.md §3.1).
///
/// Conventions for every record in this folder:
/// - `id` is the CoreKit id and the only unique key; foreign keys are kept as plain UUIDs too, so mapping never
///   depends on a relationship being loaded.
/// - Enums are stored as their raw `String`, `LocalDay` as its "YYYY-MM-DD" `String`, and arrays / `Frequency`
///   as JSON `Data` (see `PersistenceCoding`), so SwiftData never has to understand a CoreKit type.
/// - Every stored property has a default, which keeps lightweight migrations possible later.
/// - The relationships exist for the §3 delete rules; `SwiftDataStore` links them from the foreign keys.
@Model
final class GoalRecord {
    @Attribute(.unique) var id: UUID
    var planKey: String?
    var title: String = ""
    var outcome: String = ""
    /// `LocalDay` as "YYYY-MM-DD".
    var deadline: String = ""
    var bufferDays: Int = 7
    /// `GoalStatus` raw value.
    var status: String = "active"
    var resultName: String = ""
    var resultUnit: String = ""
    var resultStart: Double = 0
    var resultTarget: Double = 0
    /// `ResultDirection` raw value.
    var resultDirection: String = "up"
    var bottleneckHabitID: UUID?
    var sortIndex: Int = 0
    var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)
    var importedPlanJSON: String?

    /// Goal deletes cascade to everything below it (§3.1).
    @Relationship(deleteRule: .cascade, inverse: \FirstPrincipleRecord.goal)
    var firstPrinciples: [FirstPrincipleRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \GoalSystemRecord.goal)
    var systems: [GoalSystemRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \ObjectiveRecord.goal)
    var objectives: [ObjectiveRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \WeekReviewRecord.goal)
    var weekReviews: [WeekReviewRecord] = []

    init(id: UUID) {
        self.id = id
    }
}
