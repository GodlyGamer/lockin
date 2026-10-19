import SwiftUI
import CoreKit

/// Goals tab root (§7.2). Lives inside the Goals tab's NavigationStack (owned by RootTabView).
struct GoalsDashboardView: View {
    @Environment(AppServices.self) private var services
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isReordering = false
    @State private var showFinished = false
    @State private var dropTarget: Goal?
    @State private var showDropDialog = false
    @State private var achievedCount = 0

    init() {}

    var body: some View {
        let _ = services.store.revision
        let snapshot = services.store.snapshot()
        let now = Date()
        let today = LocalDay(now)
        let shown = snapshot.sortedGoals.filter { $0.status == .active || $0.status == .paused }
        let finished = snapshot.sortedGoals.filter { $0.status == .achieved || $0.status == .dropped }
        let transition: AnyTransition = reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))

        NightCanvas {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if services.store.loadError != nil {
                        loadErrorCard
                    }
                    if let expiry = resignExpiry(now: now) {
                        resignBanner(expiry)
                    }
                    if calendarIsOff {
                        PermissionBanner(title: "Calendar access is off",
                                         body: "Turn it on so plans fit your timetable.")
                    }
                    if isCheckInPending(snapshot: snapshot, today: today) {
                        checkInBanner(settings: snapshot.settings, now: now)
                    }
                    if isReordering {
                        reorderHeader
                    }
                    ForEach(shown) { goal in
                        goalRow(goal, snapshot: snapshot, now: now, today: today, ordered: shown)
                            .transition(transition)
                    }
                    if snapshot.goals.isEmpty && services.store.loadError == nil {
                        emptyState
                    }
                    if !finished.isEmpty {
                        finishedSection(finished)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: shown.map(\.id))
            }
        }
        .navigationTitle("Goals.")
        .navigationSubtitle(LockInFormat.dayMonth(today))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.push(.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.sheet = .newGoal
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.glassProminent)
                .accessibilityLabel("New goal")
            }
        }
        .confirmationDialog("Drop this goal?", isPresented: $showDropDialog, titleVisibility: .visible, presenting: dropTarget) { goal in
            Button("Drop goal", role: .destructive) { setStatus(goal, .dropped) }
            Button("Keep", role: .cancel) {}
        } message: { _ in
            Text("It moves to Finished. You can reactivate it later.")
        }
        .sensoryFeedback(.success, trigger: achievedCount)
    }

    // MARK: Banners

    private var calendarIsOff: Bool {
        let status = services.calendar.status
        return status == .denied || status == .restricted
    }

    private var loadErrorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            GoalsBannerCard(systemImage: "exclamationmark.triangle",
                            title: "Your data couldn't load.",
                            message: "Restore from a backup.",
                            iconTint: Color.emberText)
            Button("Restore") { router.push(.settings) }
                .buttonStyle(GoalsSolidButtonStyle(prominent: false))
        }
    }

    private func resignExpiry(now: Date) -> Date? {
        guard let expiry = services.signing.expiryDate() else { return nil }
        return expiry.timeIntervalSince(now) <= 48 * 3600 ? expiry : nil
    }

    private func resignBanner(_ expiry: Date) -> some View {
        let day = LockInFormat.dayMonth(LocalDay(expiry))
        let time = LockInFormat.time(expiry)
        return GoalsBannerCard(systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                               title: "Re-sign Lock in.",
                               message: "It stops opening \(day) at \(time). Your data is safe. Plug in and run Sideloadly.",
                               iconTint: Color.emberText)
    }

    /// Shows on the check-in weekday until every active goal's review of last week is finished.
    private func isCheckInPending(snapshot: StoreSnapshot, today: LocalDay) -> Bool {
        guard today.weekday == snapshot.settings.checkInWeekday else { return false }
        let reviewWeek = Week(containing: today).previous
        let weekEnd = reviewWeek.next.start.date()
        let goals = snapshot.goals.filter { $0.status == .active && $0.createdAt < weekEnd }
        guard !goals.isEmpty else { return false }
        return goals.contains { goal in
            snapshot.weekReview(goalID: goal.id, week: reviewWeek)?.finishedAt == nil
        }
    }

    private func checkInBanner(settings: AppSettings, now: Date) -> some View {
        let beforeCheckIn = TimeOfDay.minutes(of: now) < settings.checkInTime
        let text = beforeCheckIn ? "Check-in tonight, \(LockInFormat.time(settings.checkInTime))" : "Check-in ready"
        return Button {
            router.tab = .week
        } label: {
            GoalsBannerCard(systemImage: "checklist",
                            title: text,
                            iconTint: Color.cobaltText,
                            fill: Color.cobalt.opacity(0.10),
                            stroke: Color.cobaltText.opacity(0.28),
                            showsChevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the Week tab")
    }

    // MARK: Goal tiles

    private func gaugeState(_ state: ProgressState) -> GaugeModel.State {
        switch state {
        case .onTrack: return .onTrack
        case .behind: return .behind
        case .neutral: return .neutral
        }
    }

    @ViewBuilder
    private func goalRow(_ goal: Goal, snapshot: StoreSnapshot, now: Date, today: LocalDay, ordered: [Goal]) -> some View {
        let week = Week(containing: HabitEngine.logicalDay(for: now))
        let score = HabitEngine.goalWeekScore(goal: goal, habits: snapshot.habits, week: week, logs: snapshot.logs,
                                              now: now, settings: snapshot.settings)
        let streak = HabitEngine.goalStreak(goal: goal, habits: snapshot.habits, logs: snapshot.logs, currentWeek: week)
        let latestReview = snapshot.weekReviews
            .filter { $0.goalID == goal.id && $0.resultValue != nil }
            .max { $0.weekStart < $1.weekStart }
        let currentValue = latestReview?.resultValue ?? goal.resultStart
        let resultText = "\(GoalsFormat.withUnit(currentValue, goal.resultUnit)), target \(GoalsFormat.withUnit(goal.resultTarget, goal.resultUnit))"
        let bottleneck = goal.bottleneckHabitID.flatMap { snapshot.habit($0)?.title }
        let gauge = GaugeModel(fraction: score.fraction,
                               setPoint: score.schedOcc > 0 ? score.setPointFraction : nil,
                               label: score.dashboardLabel,
                               state: gaugeState(score.dashboardState),
                               lowLabel: "0",
                               highLabel: "\(score.schedOcc)")
        let daysLeft = max(0, today.days(to: goal.deadline))
        let index = ordered.firstIndex { $0.id == goal.id } ?? 0

        VStack(spacing: 8) {
            Button {
                router.push(.goalDetail(goal.id))
            } label: {
                GoalTile(title: goal.title,
                         daysLeft: daysLeft,
                         gauge: gauge,
                         resultText: resultText,
                         streakText: streak > 0 ? "\(streak)-week streak" : "no streak",
                         bottleneck: bottleneck)
            }
            .buttonStyle(.plain)
            .opacity(goal.status == .paused ? 0.55 : 1)
            .accessibilityValue(goal.status == .paused ? "Paused" : "")
            .contextMenu {
                if goal.status == .paused {
                    Button { setStatus(goal, .active) } label: { Label("Resume", systemImage: "play.circle") }
                } else {
                    Button { setStatus(goal, .paused) } label: { Label("Pause", systemImage: "pause.circle") }
                }
                Button { setStatus(goal, .achieved) } label: { Label("Mark achieved", systemImage: "checkmark.seal") }
                Button(role: .destructive) {
                    dropTarget = goal
                    showDropDialog = true
                } label: {
                    Label("Drop", systemImage: "xmark.circle")
                }
                Button { isReordering = true } label: { Label("Reorder", systemImage: "arrow.up.arrow.down") }
            }

            if isReordering {
                HStack(spacing: 8) {
                    Button { move(goal, by: -1, in: ordered) } label: {
                        Label("Move up", systemImage: "chevron.up")
                    }
                    .disabled(index == 0)
                    Button { move(goal, by: 1, in: ordered) } label: {
                        Label("Move down", systemImage: "chevron.down")
                    }
                    .disabled(index == ordered.count - 1)
                }
                .buttonStyle(GoalsSolidButtonStyle(prominent: false))
            }
        }
    }

    private var reorderHeader: some View {
        HStack {
            Text("Reordering goals")
                .font(.sectionTitle)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Button("Done") { isReordering = false }
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.cobaltText)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 4)
    }

    // MARK: Finished goals

    private func finishedSection(_ finished: [Goal]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showFinished.toggle()
            } label: {
                HStack {
                    Text("Finished (\(finished.count))")
                        .font(.sectionTitle)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Image(systemName: showFinished ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(showFinished ? "Collapse" : "Expand")

            if showFinished {
                ForEach(finished) { goal in
                    Button {
                        router.push(.goalDetail(goal.id))
                    } label: {
                        GoalsBannerCard(systemImage: goal.status == .achieved ? "checkmark.seal" : "xmark.circle",
                                        title: goal.title,
                                        message: GoalsFormat.goalStatus(goal.status),
                                        iconTint: Color.textSecondary,
                                        showsChevron: true)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { setStatus(goal, .active) } label: { Label("Reactivate", systemImage: "arrow.uturn.backward") }
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "target")
                .font(.largeTitle)
                .foregroundStyle(Color.cobaltText)
                .accessibilityHidden(true)
            Text("Build your first system")
                .font(.tileTitle)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
            Text("Answer a few questions and Claude turns your goal into habits and calendar blocks.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Button("New goal") { router.sheet = .newGoal }
                .buttonStyle(GoalsSolidButtonStyle())
                .padding(.top, 8)
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 8)
    }

    // MARK: Writes

    private func setStatus(_ goal: Goal, _ status: GoalStatus) {
        var updated = goal
        updated.status = status
        Task {
            do {
                try await GoalsActions.commit(ChangeSet(upserts: [.goal(updated)]), then: .reschedule, services: services)
                if status == .achieved { achievedCount += 1 }
            } catch {
                router.toast = GoalsActions.saveFailed
            }
        }
    }

    private func move(_ goal: Goal, by delta: Int, in ordered: [Goal]) {
        guard let index = ordered.firstIndex(where: { $0.id == goal.id }) else { return }
        let target = index + delta
        guard ordered.indices.contains(target) else { return }
        var list = ordered
        list.swapAt(index, target)
        let upserts = GoalsOrdering.reassign(list, index: \.sortIndex, wrap: { AnyEntity.goal($0) })
        guard !upserts.isEmpty else { return }
        Task {
            do {
                try await GoalsActions.commit(ChangeSet(upserts: upserts), services: services)
            } catch {
                router.toast = GoalsActions.saveFailed
            }
        }
    }
}

#Preview {
    NavigationStack { GoalsDashboardView() }
        .environment(AppServices.preview())
        .environment(Router())
}
