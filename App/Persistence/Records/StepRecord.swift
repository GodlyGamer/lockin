import Foundation
import SwiftData

/// SwiftData mirror of `Step` (DESIGN.md §3.5).
@Model
final class StepRecord {
    @Attribute(.unique) var id: UUID
    var planKey: String?
    var objectiveID: UUID = UUID()
    var title: String = ""
    /// `LocalDay` as "YYYY-MM-DD", or nil (inherits the objective's deadline).
    var deadline: String?
    var estimatedMinutes: Int = 30
    var done: Bool = false
    var sortIndex: Int = 0

    var objective: ObjectiveRecord?

    init(id: UUID) {
        self.id = id
    }
}
