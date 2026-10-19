import Foundation

/// Calendar fake: serves `events`, materialises rules and flags clashes through `ScheduleEngine`, never touches EventKit.
@MainActor
public final class FakeCalendarService: CalendarServicing {
    public var status: PermissionStatus
    public var events: [ExternalEvent]
    public private(set) var syncCount = 0
    private let store: any Store
    private let notifications: (any NotificationServicing)?

    public init(store: any Store, notifications: (any NotificationServicing)? = nil,
                status: PermissionStatus = .granted, events: [ExternalEvent] = []) {
        self.store = store; self.notifications = notifications; self.status = status; self.events = events
    }

    public func requestAccess() async -> PermissionStatus {
        if status == .notDetermined { status = .granted }
        return status
    }

    public func busyIntervals(in range: DateInterval) async -> [BusyInterval] {
        guard status == .granted else { return [] }
        return events.compactMap(\.busyInterval).filter { $0.start < range.end && $0.end > range.start }
    }

    public func externalEvents(in range: DateInterval) async -> [ExternalEvent] {
        guard status == .granted else { return [] }
        return events.filter { $0.start < range.end && $0.end > range.start }
    }

    public func sync() async -> SyncReport {
        syncCount += 1
        let snapshot = store.snapshot()
        let now = Date()
        let created = ScheduleEngine.materialise(rules: snapshot.blockRules, existing: snapshot.blocks, from: LocalDay(now),
                                                 days: 14, settings: snapshot.settings, systems: snapshot.systems)
        let busy = status == .granted ? events.compactMap(\.busyInterval) : []
        let checked = ScheduleEngine.detectClashes(blocks: snapshot.blocks + created, busy: busy,
                                                   settings: snapshot.settings, now: now)
        try? store.apply(ChangeSet(upserts: checked.map(AnyEntity.block)))
        await notifications?.reschedule()
        return SyncReport(created: created.count, clashes: checked.filter { $0.status == .clash }.count)
    }

    public func move(blockID: UUID, to start: Date) async throws {
        guard var block = store.snapshot().block(blockID) else { return }
        let duration = block.end.timeIntervalSince(block.start)
        block.start = start
        block.end = start.addingTimeInterval(duration)
        block.status = .scheduled
        block.suggestedStart = nil
        try store.apply(ChangeSet(upserts: [.block(block)]))
    }
}

/// Notification fake: records what `ReminderPlanner` would schedule.
@MainActor
public final class FakeNotificationService: NotificationServicing {
    public var status: PermissionStatus
    /// The last planned set.
    public private(set) var planned: [PlannedNotification] = []
    public private(set) var rescheduleCount = 0
    private let store: any Store
    private let signing: any SigningInfoProviding
    /// Injectable clock for tests.
    public var now: () -> Date

    public init(store: any Store, signing: any SigningInfoProviding = FixedSigningInfo(nil),
                status: PermissionStatus = .granted, now: @escaping () -> Date = { Date() }) {
        self.store = store; self.signing = signing; self.status = status; self.now = now
    }

    public func requestAccess() async -> PermissionStatus {
        if status == .notDetermined { status = .granted }
        return status
    }

    public func reschedule() async {
        rescheduleCount += 1
        planned = status == .granted
            ? ReminderPlanner.plan(snapshot: store.snapshot(), now: now(), signingExpiry: signing.expiryDate())
            : []
    }

    public func pendingCount() async -> Int { planned.count }
}

/// Backup fake: keeps backups in memory, keyed by a fake URL.
@MainActor
public final class FakeBackupService: BackupServicing {
    public private(set) var folderName: String?
    public private(set) var files: [URL: Data] = [:]
    private let store: any Store

    public init(store: any Store, folderName: String? = "Lock in backups") {
        self.store = store; self.folderName = folderName
    }

    public struct NoFolderError: Error {}

    public func setFolder(_ url: URL) throws {
        folderName = url.lastPathComponent
    }

    public func backUpNow() throws -> URL {
        guard let folderName else { throw NoFolderError() }
        let url = URL(fileURLWithPath: "/\(folderName)/\(BackupCodec.fileName(for: .today))")
        files[url] = BackupCodec.encode(store.snapshot())
        return url
    }

    public func restore(from url: URL) throws {
        guard let data = files[url] else { throw BackupError.notABackup }
        try store.replaceAll(with: BackupCodec.decode(data))
    }
}

/// A fixed signing expiry (nil = unknown).
public struct FixedSigningInfo: SigningInfoProviding, Sendable {
    public var date: Date?

    public init(_ date: Date?) { self.date = date }

    public func expiryDate() -> Date? { date }
}
