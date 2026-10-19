import Foundation
import SwiftData

/// SwiftData mirror of `Objective` (DESIGN.md §3.4), one node of the goal's DAG.
@Model
final class ObjectiveRecord {
    @Attribute(.unique) var id: UUID
    var planKey: String?
    var goalID: UUID = UUID()
    var title: String = ""
    /// `LocalDay` as "YYYY-MM-DD", or nil.
    var deadline: String?
    var deadlineOverridden: Bool = false
    var estimatedDays: Int = 7
    /// `ObjectiveStatus` raw value.
    var status: String = "notStarted"
    /// JSON `[UUID]`.
    var dependsOnIDsJSON: Data = Data()
    /// JSON `[UUID]`.
    var systemIDsJSON: Data = Data()
    var sortIndex: Int = 0

    var goal: GoalRecord?

    @Relationship(deleteRule: .cascade, inverse: \StepRecord.objective)
    var steps: [StepRecord] = []

    init(id: UUID) {
        self.id = id
    }
}
