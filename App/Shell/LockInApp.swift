import SwiftUI
import CoreKit

/// App entry point (DESIGN.md §10.2 M7): builds the live services and the router, injects both, applies the
/// accent and dark scheme, and wires URLs, notification taps and scene-phase syncs.
@main
struct LockInApp: App {
    @State private var services: AppServices
    @State private var router: Router
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let services = AppServices.live()
        let router = Router()
        // Notification taps open their deep link. Set here (not on appear) so that a cold launch from a
        // notification already has a target when the system delivers the tap.
        if let notifications = services.notifications as? LocalNotificationService {
            notifications.onOpenLink = { link in router.open(link) }
        }
        _services = State(initialValue: services)
        _router = State(initialValue: router)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(services)
                .environment(router)
                .tint(Color.cobalt)
                .preferredColorScheme(.dark)
                .toast(text: $router.toast)
                .onOpenURL { url in
                    handleIncoming(url)
                }
                // Launch and every return to the foreground (§5.5). `sync()` always ends with a notification
                // reschedule, so this also refreshes the 10-day window (§6.3).
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active {
                        syncCalendar()
                    }
                }
        }
    }

    /// `lockin://…` links go to the router; a `.json` file opened from Files or another app goes to Import.
    private func handleIncoming(_ url: URL) {
        if let link = DeepLink(url: url) {
            router.open(link)
        } else if url.isFileURL, url.pathExtension.lowercased() == "json" {
            router.pendingImportURL = url
            router.sheet = .importPlan(nil)
        }
    }

    private func syncCalendar() {
        let calendar = services.calendar
        Task {
            _ = await calendar.sync()
        }
    }
}
