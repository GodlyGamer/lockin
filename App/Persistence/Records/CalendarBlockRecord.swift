import Foundation
import SwiftData

/// SwiftData mirror of `CalendarBlock` (DESIGN.md §3.10). The only entity that syncs with Apple Calendar.
@Model
final class CalendarBlockRecord {
    @Attribute(.unique) var id: UUID
    /// nil = one-off block.
    var ruleID: UUID?
    var systemID: UUID?
    var goalID: UUID?
    var title: String = ""
    var start: Date = Date(timeIntervalSinceReferenceDate: 0)
    var end: Date = Date(timeIntervalSinceReferenceDate: 0)
    /// `BlockStatus` raw value.
    var status: String = "scheduled"
    /// JSON `[String]`.
    var ignoredClashEventIDsJSON: Data = Data()
    var suggestedStart: Date?
    var ekEventIdentifier: String?
    var ekExternalIdentifier: String?
    var lastSyncedAt: Date?
    var isPhysical: Bool = false
    var nudge: Bool = false

    init(id: UUID) {
        self.id = id
    }
}
