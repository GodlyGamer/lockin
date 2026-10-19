import Foundation
import Observation
import UserNotifications
import CoreKit

/// Local notifications (DESIGN.md §6).
///
/// `reschedule()` asks `ReminderPlanner` for the full plan, removes every pending request and adds the plan back as
/// calendar-triggered requests (§6.3). The class is `UNUserNotificationCenterDelegate` too: it shows banners while the
/// app is open and routes taps through `onOpenLink` (§6.5).
///
/// Concurrency: with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` this class is main-actor isolated. The two delegate
/// methods are `nonisolated` because UserNotifications calls them off the main actor; they copy the link text (a
/// `String`) out of the response first and then hop to the main actor. The `UNUserNotificationCenter` completion
/// handlers below are written as `@Sendable` closures that capture only a continuation, so Swift never installs a
/// main-actor check on a callback that the system runs on a background queue.
@Observable
final class LocalNotificationService: NSObject, NotificationServicing, UNUserNotificationCenterDelegate {
    /// Refreshed from `notificationSettings()` at launch, on every reschedule and after `requestAccess()`.
    /// authorized / provisional / ephemeral all count as granted.
    private(set) var status: PermissionStatus = .notDetermined

    /// Set by `LockInApp`. Called on the main actor when the user taps a notification. A tap that arrives before the
    /// closure is set (cold launch from a notification) is kept and delivered as soon as it is set.
    @ObservationIgnored
    var onOpenLink: ((DeepLink) -> Void)? {
        didSet { deliverPendingLink() }
    }

    @ObservationIgnored private let store: any Store
    @ObservationIgnored private let signing: any SigningInfoProviding
    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private var pendingLink: DeepLink?

    // Debounce: a burst of `reschedule()` calls shares one pass. See `reschedule()`.
    @ObservationIgnored private var requestedCount = 0
    @ObservationIgnored private var appliedCount = 0
    @ObservationIgnored private var worker: Task<Void, Never>?

    init(store: any Store, signing: any SigningInfoProviding) {
        self.store = store
        self.signing = signing
        super.init()
        center.delegate = self
        Task { await refreshStatus() }
    }

    // MARK: NotificationServicing

    func requestAccess() async -> PermissionStatus {
        await requestAuthorization()
        await refreshStatus()
        if status == .granted {
            // Fire and forget: the caller (onboarding, Settings) should not wait out the debounce.
            Task { await reschedule() }
        }
        return status
    }

    /// Replaces every pending request with the current plan (§6.3). Calls made close together are merged into one
    /// pass that runs 200 ms after the first call, so the schedule is always in place well inside 1 s. Every caller
    /// waits for the pass that covers its own call.
    func reschedule() async {
        requestedCount += 1
        let ticket = requestedCount
        while appliedCount < ticket {
            let pass: Task<Void, Never>
            if let running = worker {
                pass = running
            } else {
                pass = Task { await self.runPasses() }
                worker = pass
            }
            await pass.value
        }
    }

    func pendingCount() async -> Int {
        await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            center.getPendingNotificationRequests { @Sendable (requests: [UNNotificationRequest]) -> Void in
                continuation.resume(returning: requests.count)
            }
        }
    }

    // MARK: Planning and scheduling

    /// Runs passes until every request made so far is covered, then clears `worker`.
    private func runPasses() async {
        while appliedCount < requestedCount {
            try? await Task.sleep(for: .milliseconds(200))
            await refreshStatus()
            // The store is read in the same turn as the count, so every call up to `covered` is in the snapshot.
            let covered = requestedCount
            let snapshot = store.snapshot()
            await schedule(from: snapshot)
            appliedCount = covered
        }
        worker = nil
    }

    private func schedule(from snapshot: StoreSnapshot) async {
        guard status == .granted else { return }
        let planned = ReminderPlanner.plan(snapshot: snapshot, now: .now, signingExpiry: signing.expiryDate())
        center.removeAllPendingNotificationRequests()
        for item in planned {
            await add(Self.makeRequest(for: item))
        }
    }

    /// §6.3: `UNCalendarNotificationTrigger(dateMatching: y, m, d, h, min, repeats: false)`, `.active`, default sound,
    /// no category (no action buttons), `userInfo["link"]` = the deep link URL.
    private static func makeRequest(for item: PlannedNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = UNNotificationSound.default
        content.interruptionLevel = .active
        content.userInfo = ["link": item.link.url.absoluteString]

        var parts = Calendar.lockIn.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
        parts.calendar = Calendar.lockIn
        parts.timeZone = Calendar.lockIn.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)
    }

    // MARK: UserNotifications wrappers

    private func add(_ request: UNNotificationRequest) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            center.add(request) { @Sendable (_: (any Error)?) -> Void in
                continuation.resume()
            }
        }
    }

    private func requestAuthorization() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { @Sendable (_: Bool, _: (any Error)?) -> Void in
                continuation.resume()
            }
        }
    }

    private func refreshStatus() async {
        let raw: UNAuthorizationStatus = await withCheckedContinuation {
            (continuation: CheckedContinuation<UNAuthorizationStatus, Never>) in
            center.getNotificationSettings { @Sendable (settings: UNNotificationSettings) -> Void in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
        status = Self.permission(from: raw)
    }

    private static func permission(from status: UNAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .granted
        @unknown default: .restricted
        }
    }

    // MARK: Taps

    private func handleTap(linkText: String) {
        guard let url = URL(string: linkText), let link = DeepLink(url: url) else { return }
        if let onOpenLink {
            onOpenLink(link)
        } else {
            pendingLink = link
        }
    }

    private func deliverPendingLink() {
        guard let link = pendingLink, let onOpenLink else { return }
        pendingLink = nil
        onOpenLink(link)
    }

    // MARK: UNUserNotificationCenterDelegate (called off the main actor)

    /// Show a banner (and sound, and Notification Centre entry) even while the app is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// A tap: copy the link text out (a Sendable `String`), then open it on the main actor.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard let text = response.notification.request.content.userInfo["link"] as? String else { return }
        await handleTap(linkText: text)
    }
}
