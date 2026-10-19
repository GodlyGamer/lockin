import Foundation

/// Plans every pending notification (§6). Stateless.
public enum ReminderPlanner {
    /// Every regular notification for `now` → `now + horizonDays`, after the daily cap (§6.2), sorted by fire date,
    /// first `maxPending` kept, plus the re-sign notification on top when `signingExpiry` is within 7 days.
    /// Text follows §6.4 exactly; identifiers and links follow §6.3 and §6.5. Notifications whose fire date is not
    /// after `now` are dropped.
    public static func plan(snapshot: StoreSnapshot, now: Date, signingExpiry: Date?, horizonDays: Int = 10,
                            maxPending: Int = 60) -> [PlannedNotification] {
        // M1: implement (§6).
        []
    }
}
