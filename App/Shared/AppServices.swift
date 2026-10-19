import Foundation
import Observation
import CoreKit

/// Every service the features use. Injected with `.environment(services)`; read with `@Environment(AppServices.self)`.
@Observable
@MainActor
final class AppServices {
    let store: any Store
    let calendar: any CalendarServicing
    let notifications: any NotificationServicing
    let backup: any BackupServicing
    let signing: any SigningInfoProviding

    init(store: any Store, calendar: any CalendarServicing, notifications: any NotificationServicing,
         backup: any BackupServicing, signing: any SigningInfoProviding) {
        self.store = store
        self.calendar = calendar
        self.notifications = notifications
        self.backup = backup
        self.signing = signing
    }

    /// The real app: SwiftData (M2), EventKit (M6), UserNotifications (M7), Files backups and provisioning (M2).
    static func live() -> AppServices {
        let store = SwiftDataStore()
        let signing = ProvisioningSigningInfo()
        let notifications = LocalNotificationService(store: store, signing: signing)
        let calendar = EventKitCalendarService(store: store, notifications: notifications)
        let backup = FileBackupService(store: store)
        return AppServices(store: store, calendar: calendar, notifications: notifications, backup: backup, signing: signing)
    }

    /// Previews: CoreKit fakes over `SampleData.bodyFatGoal()` and this week's timetable.
    static func preview(snapshot: StoreSnapshot = SampleData.bodyFatGoal()) -> AppServices {
        let store = InMemoryStore(snapshot: snapshot)
        let signing = FixedSigningInfo(Date().addingTimeInterval(5 * 24 * 3600))
        let notifications = FakeNotificationService(store: store, signing: signing)
        let calendar = FakeCalendarService(store: store, notifications: notifications, events: SampleData.timetable())
        let backup = FakeBackupService(store: store)
        return AppServices(store: store, calendar: calendar, notifications: notifications, backup: backup, signing: signing)
    }
}
