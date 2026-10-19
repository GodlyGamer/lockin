import Foundation
import SwiftData

/// SwiftData mirror of `GoalSystem` (DESIGN.md §3.3).
///
/// The many-to-many link with objectives is kept as `ObjectiveRecord.systemIDsJSON` (CoreKit stores `systemIDs`), so
/// deleting a system strips its id from those lists in code.
@Model
final class GoalSystemRecord {
    @Attribute(.unique) var id: UUID
    var planKey: String?
    var goalID: UUID = UUID()
    /// nil when `kind` is "sustaining".
    var firstPrincipleID: UUID?
    /// `SystemKind` raw value.
    var kind: String = "principle"
    var title: String = ""
    var location: String?
    var sortIndex: Int = 0

    var goal: GoalRecord?
    var firstPrinciple: FirstPrincipleRecord?

    /// Deleting a system leaves its habits standalone (§3.3: nullify); the store also clears `systemID` / `goalID`.
    @Relationship(deleteRule: .nullify, inverse: \HabitRecord.system)
    var habits: [HabitRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \BlockRuleRecord.system)
    var blockRules: [BlockRuleRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \PlanReminderRecord.system)
    var reminders: [PlanReminderRecord] = []

    init(id: UUID) {
        self.id = id
    }
}
