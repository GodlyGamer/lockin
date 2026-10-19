import Foundation

/// Apple Calendar pairing (§5). Live implementation: `EventKitCalendarService` (M6).
@MainActor public protocol CalendarServicing: AnyObject {
    var status: PermissionStatus { get }
    func requestAccess() async -> PermissionStatus
    /// Raw busy intervals (no travel buffer), excluding the Goals calendar, all-day and free events.
    func busyIntervals(in range: DateInterval) async -> [BusyInterval]
    func externalEvents(in range: DateInterval) async -> [ExternalEvent]
    /// The §5.5 sequence; reads and writes the Store. Always ends with `notifications.reschedule()`,
    /// even when calendar access is denied.
    func sync() async -> SyncReport
    func move(blockID: UUID, to start: Date) async throws
}

/// Local notifications (§6). Live implementation: `LocalNotificationService` (M7).
@MainActor public protocol NotificationServicing: AnyObject {
    var status: PermissionStatus { get }
    func requestAccess() async -> PermissionStatus
    /// Removes every pending request and adds `ReminderPlanner.plan(...)`.
    func reschedule() async
    func pendingCount() async -> Int
}

/// JSON backups (§9.3). Live implementation: `FileBackupService` (M2).
@MainActor public protocol BackupServicing: AnyObject {
    var folderName: String? { get }
    func setFolder(_ url: URL) throws
    func backUpNow() throws -> URL
    func restore(from url: URL) throws
}

/// Signing profile expiry (§9.3). Live implementation: `ProvisioningSigningInfo` (M2).
public protocol SigningInfoProviding {
    func expiryDate() -> Date?
}

public struct SyncReport: Equatable, Sendable {
    public var created: Int
    public var updated: Int
    public var cancelled: Int
    public var clashes: Int
    public var error: String?

    public init(created: Int = 0, updated: Int = 0, cancelled: Int = 0, clashes: Int = 0, error: String? = nil) {
        self.created = created; self.updated = updated; self.cancelled = cancelled; self.clashes = clashes; self.error = error
    }
}
