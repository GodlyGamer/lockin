import SwiftUI
import EventKit
import CoreKit

/// The Calendar tab (DESIGN.md §5.1, §7.8): Week and Day views over the app's blocks, the Apple Calendar
/// timetable and timed habits.
///
/// This view does not wrap itself in a `NavigationStack`; the shell's Calendar tab provides one. The Day | Week
/// control sits in the principal toolbar slot and "Today" in a trailing toolbar item.
struct CalendarTabView: View {
    @Environment(AppServices.self) private var services
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    @State private var mode: CalMode = .week
    /// Page 0 is the page that contains `origin`.
    @State private var origin: LocalDay = .today
    @State private var selection = 0
    /// Any day on the visible page; used to keep the position when the mode changes.
    @State private var anchor: LocalDay = .today
    @State private var events: [ExternalEvent] = []
    @State private var reloadTick = 0

    private let pageRange = -40...40

    var body: some View {
        let _ = services.store.revision
        let snapshot = services.store.snapshot()
        let access = services.calendar.status
        NightCanvas {
            VStack(spacing: 0) {
                if access == .denied || access == .restricted {
                    PermissionBanner(title: "Calendar access is off",
                                     body: "Turn it on so plans fit your timetable.")
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
                TabView(selection: $selection) {
                    ForEach(pageRange, id: \.self) { index in
                        CalPageView(days: days(forPage: index),
                                    hourHeight: hourHeight,
                                    snapshot: snapshot,
                                    events: events,
                                    onRefresh: { await refresh() })
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Calendar view", selection: $mode) {
                    Text("Day").tag(CalMode.day)
                    Text("Week").tag(CalMode.week)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") { goToToday() }
            }
        }
        .task(id: CalLoadKey(mode: mode, origin: origin, selection: selection,
                             tick: reloadTick, access: access)) {
            await loadEvents()
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            reloadTick += 1
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reloadTick += 1 }
        }
        .onChange(of: selection) { _, _ in
            anchor = days(forPage: selection).first ?? origin
        }
        .onChange(of: mode) { _, newMode in
            switchMode(to: newMode)
        }
    }

    // MARK: Paging

    private var hourHeight: CGFloat {
        mode == .week ? CalMetrics.weekHourHeight : CalMetrics.dayHourHeight
    }

    private func days(forPage index: Int) -> [LocalDay] {
        switch mode {
        case .week: Week(containing: origin.adding(days: 7 * index)).days
        case .day: [origin.adding(days: index)]
        }
    }

    private func switchMode(to newMode: CalMode) {
        let today = LocalDay.today
        switch newMode {
        case .day:
            origin = Week(containing: anchor).contains(today) ? today : anchor
        case .week:
            origin = anchor
        }
        selection = 0
        anchor = origin
    }

    private func goToToday() {
        let today = LocalDay.today
        origin = today
        anchor = today
        withAnimation { selection = 0 }
    }

    // MARK: Data

    /// External events for the visible page and its neighbours.
    private func loadEvents() async {
        guard services.calendar.status == .granted else {
            if !events.isEmpty { events = [] }
            return
        }
        let radius = mode == .week ? 1 : 3
        guard let first = days(forPage: selection - radius).first,
              let last = days(forPage: selection + radius).last else { return }
        let range = DateInterval(start: first.date(), end: last.adding(days: 1).date())
        let loaded = await services.calendar.externalEvents(in: range)
        if Task.isCancelled { return }
        events = loaded
    }

    /// Pull to refresh: a full sync, then reload the events.
    private func refresh() async {
        let report = await services.calendar.sync()
        if report.error != nil {
            router.toast = "Calendar didn't sync. Pull to retry."
        }
        reloadTick += 1
    }
}

private struct CalLoadKey: Hashable {
    let mode: CalMode
    let origin: LocalDay
    let selection: Int
    let tick: Int
    let access: PermissionStatus
}

#Preview {
    NavigationStack { CalendarTabView() }
        .environment(calPreviewServices())
        .environment(Router())
        .preferredColorScheme(.dark)
}
