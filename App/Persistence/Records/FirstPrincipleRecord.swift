import Foundation
import SwiftData

/// SwiftData mirror of `FirstPrinciple` (DESIGN.md §3.2).
@Model
final class FirstPrincipleRecord {
    @Attribute(.unique) var id: UUID
    var planKey: String?
    var goalID: UUID = UUID()
    var title: String = ""
    var why: String = ""
    var sortIndex: Int = 0

    var goal: GoalRecord?

    /// Deleting a principle leaves its systems in place (§3.2: nullify).
    @Relationship(deleteRule: .nullify, inverse: \GoalSystemRecord.firstPrinciple)
    var systems: [GoalSystemRecord] = []

    init(id: UUID) {
        self.id = id
    }
}
