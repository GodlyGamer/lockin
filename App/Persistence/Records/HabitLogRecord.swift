import Foundation
import SwiftData

/// SwiftData mirror of `HabitLog` (DESIGN.md §3.7). (habitID, day) is unique; `SwiftDataStore` enforces it on upsert.
@Model
final class HabitLogRecord {
    @Attribute(.unique) var id: UUID
    var habitID: UUID = UUID()
    /// `LocalDay` as "YYYY-MM-DD".
    var day: String = ""
    /// `Mark` raw value ("D", "B" or "M").
    var mark: String = "M"
    /// Count habits only.
    var count: Int?
    var loggedAt: Date = Date(timeIntervalSinceReferenceDate: 0)

    var habit: HabitRecord?

    init(id: UUID) {
        self.id = id
    }
}
