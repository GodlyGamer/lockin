import SwiftUI
import CoreKit

/// The shell (DESIGN.md §7, §8.7): the system `TabView` (Liquid Glass tab bar, no custom chrome), one
/// `NavigationStack` per tab, the Today accessory, every cross-feature sheet, and the onboarding cover.
struct RootTabView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.tab) {
            Tab("Goals", systemImage: "target", value: AppTab.goals) {
                NavigationStack(path: $router.goalsPath) {
                    GoalsDashboardView()
                        .navigationDestination(for: PushRoute.self) { route in
                            ShellDestinationView(route: route)
                        }
                }
            }

            Tab("Calendar", systemImage: "calendar", value: AppTab.calendar) {
                // CalendarTabView puts its Day/Week control in the principal toolbar slot, so it needs a stack.
                NavigationStack {
                    CalendarTabView()
                }
            }

            Tab("Habits", systemImage: "checklist", value: AppTab.habits) {
                NavigationStack(path: $router.habitsPath) {
                    HabitsTabView()
                        .navigationDestination(for: PushRoute.self) { route in
                            ShellDestinationView(route: route)
                        }
                }
            }

            Tab("Week", systemImage: "chart.bar", value: AppTab.week) {
                NavigationStack {
                    WeekTabView()
                }
            }
        }
        // System glass, shown on every tab. TodayAccessoryView handles its own tap (router.sheet = .today).
        .tabViewBottomAccessory {
            TodayAccessoryView()
        }
        // The only place a cross-feature sheet is presented.
        .sheet(item: $router.sheet) { route in
            ShellSheetContent(route: route)
        }
        .modifier(ShellOnboardingCover())
    }
}

/// Maps a pushed route to its screen. Registered once on the root of the Goals and Habits stacks.
private struct ShellDestinationView: View {
    let route: PushRoute

    var body: some View {
        switch route {
        case .goalDetail(let goalID):
            GoalDetailView(goalID: goalID)
        case .habitEditor(let habitID):
            HabitEditorView(habitID: habitID)
        case .settings:
            SettingsView()
        }
    }
}

/// Maps a sheet route to its screen. The feature views are presented bare: `IntakeFlowView` and `ImportPlanView`
/// wrap themselves in a `NavigationStack`, and the other sheets need none. The environment flows in from the root.
/// A toast set from inside a sheet would hide behind it, so the sheet carries its own copy of the toast overlay.
private struct ShellSheetContent: View {
    @Environment(Router.self) private var router
    let route: SheetRoute

    var body: some View {
        @Bindable var router = router

        content
            .toast(text: $router.toast)
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .markHabit(let habitID, let day):
            HabitMarkSheet(habitID: habitID, day: day)
        case .today:
            TodaySheet()
        case .conflict(let blockID):
            ConflictSheet(blockID: blockID)
        case .block(let blockID):
            BlockSheet(blockID: blockID)
        case .newBlock(let start):
            NewBlockSheet(start: start)
        case .newGoal:
            IntakeFlowView()
        case .importPlan(let goalID):
            ImportPlanView(goalID: goalID)
        }
    }
}

/// Full-screen onboarding while `onboardingDone` is false (§7.1). Lives in its own modifier so that the tab view
/// itself does not re-evaluate on every store change.
private struct ShellOnboardingCover: ViewModifier {
    @Environment(AppServices.self) private var services

    func body(content: Content) -> some View {
        let _ = services.store.revision
        let onboardingDone = services.store.snapshot().settings.onboardingDone
        content
            .fullScreenCover(isPresented: .constant(!onboardingDone)) {
                OnboardingView()
            }
    }
}

#Preview {
    RootTabView()
        .environment(AppServices.preview())
        .environment(Router())
        .preferredColorScheme(.dark)
}
