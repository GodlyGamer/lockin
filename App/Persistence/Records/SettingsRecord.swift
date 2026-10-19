import Foundation
import SwiftData

/// SwiftData mirror of `AppSettings` (DESIGN.md §3.12). The store keeps exactly one of these.
@Model
final class SettingsRecord {
    @Attribute(.unique) var id: UUID
    var morningTimeWeekday: Int = 450
    var morningTimeWeekend: Int = 540
    var eveningTime: Int = 1290
    var checkInWeekday: Int = 1
    var checkInTime: Int = 1140
    var maxNotificationsPerDay: Int = 6
    var maxTimedNudgesPerDay: Int = 4
    /// JSON `[TimeWindow]`.
    var bestHoursJSON: Data = Data()
    var saturdayOff: Bool = true
    var travelBufferMinutes: Int = 15
    var goalsCalendarIdentifier: String?
    /// Security-scoped bookmark of the backup folder.
    var backupFolderBookmark: Data?
    var lastBackupAt: Date?
    var onboardingDone: Bool = false

    init(id: UUID) {
        self.id = id
    }
}
