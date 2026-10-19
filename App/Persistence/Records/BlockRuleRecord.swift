import Foundation
import SwiftData

/// SwiftData mirror of `BlockRule` (DESIGN.md §3.9).
///
/// Its `CalendarBlock` instances are not a relationship: deleting a rule deletes its future blocks and turns past ones into
/// one-offs (§4.4), which neither cascade nor nullify can express. `CalendarBlockRecord.ruleID` is a plain UUID.
@Model
final class BlockRuleRecord {
    @Attribute(.unique) var id: UUID
    var planKey: String?
    var systemID: UUID = UUID()
    var title: String = ""
    var durationMinutes: Int = 60
    /// JSON `[Int]` (ISO weekdays).
    var weekdaysJSON: Data = Data()
    var startTime: Int = 0
    var windowStart: Int = 0
    var windowEnd: Int = 0
    var isPhysical: Bool = false
    var nudge: Bool = false
    var active: Bool = true

    var system: GoalSystemRecord?

    init(id: UUID) {
        self.id = id
    }
}
