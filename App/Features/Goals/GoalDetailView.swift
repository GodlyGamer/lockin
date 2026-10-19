import SwiftUI
import CoreKit

private enum GoalsDetailMode: String, CaseIterable, Hashable {
    case map = "Map"
    case outline = "Outline"
}

/// Goal detail (§7.5): feasibility warning, Map | Outline switch, empty state. Pushed inside the Goals NavigationStack.
struct GoalDetailView: View {
    let goalID: UUID

    @Environment(AppServices.self) private var services
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var mode: GoalsDetailMode = .map
    @State private var scrollTarget: UUID?
    @State private var busy: [BusyInterval] = []
    @State private var showPrincipleEditor = false

    init(goalID: UUID) {
        self.goalID = goalID
    }

    var body: some View {
        let _ = services.store.revision
        let snapshot = services.store.snapshot()
        let goal = snapshot.goal(goalID)

        NightCanvas {
            if let goal {
                content(goal: goal, snapshot: snapshot)
            } else {
                Text("This goal no longer exists.")
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(goal.map { LockInFormat.titled($0.title) } ?? "Goal.")
        .navigationSubtitle(subtitle(for: goal))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: services.store.revision) { await loadBusy() }
        .onChange(of: goal == nil) { _, missing in
            if missing { dismiss() }
        }
        .sheet(isPresented: $showPrincipleEditor) {
            PrincipleEditorSheet(goalID: goalID, principle: nil)
        }
    }

    private func subtitle(for goal: Goal?) -> String {
        guard let goal else { return "" }
        let left = max(0, LocalDay.today.days(to: goal.deadline))
        return "\(LockInFormat.shortDayMonth(goal.deadline)), \(GoalsFormat.daysLeft(left))"
    }

    @ViewBuilder
    private func content(goal: Goal, snapshot: StoreSnapshot) -> some View {
        let isEmpty = snapshot.systems(goalID: goalID).isEmpty && snapshot.firstPrinciples(goalID: goalID).isEmpty
        if isEmpty {
            emptyState
        } else {
            let report = ScheduleEngine.feasibility(goal: goal, snapshot: snapshot, busy: busy, now: Date())
            VStack(spacing: 12) {
                if let message = report.message {
                    FlagBox(text: message)
                        .padding(.horizontal, 16)
                }
                Picker("View", selection: $mode) {
                    ForEach(GoalsDetailMode.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                switch mode {
                case .map:
                    GoalMapView(goalID: goalID,
                                onSelect: { id in
                                    scrollTarget = id
                                    mode = .outline
                                },
                                onEdit: {
                                    scrollTarget = nil
                                    mode = .outline
                                })
                case .outline:
                    GoalOutlineView(goalID: goalID,
                                    scrollTarget: scrollTarget,
                                    onDone: {
                                        scrollTarget = nil
                                        mode = .map
                                    })
                }
            }
            .padding(.top, 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.largeTitle)
                .foregroundStyle(Color.cobaltText)
                .accessibilityHidden(true)
            Text("No systems yet")
                .font(.tileTitle)
                .foregroundStyle(Color.textPrimary)
            Text("Import a plan from Claude, or start by adding a first principle yourself.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Button("Import a plan") { router.sheet = .importPlan(goalID) }
                .buttonStyle(GoalsSolidButtonStyle())
                .padding(.top, 8)
            Button("Add a first principle") { showPrincipleEditor = true }
                .buttonStyle(GoalsSolidButtonStyle(prominent: false))
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadBusy() async {
        guard services.calendar.status == .granted else {
            busy = []
            return
        }
        let start = Date()
        let range = DateInterval(start: start, end: start.addingTimeInterval(7 * 24 * 3600))
        busy = await services.calendar.busyIntervals(in: range)
    }
}

#Preview {
    NavigationStack { GoalDetailView(goalID: SampleData.goalID) }
        .environment(AppServices.preview())
        .environment(Router())
}
