import Foundation
import Observation
import CoreKit

/// App-wide navigation state. Injected with `.environment(router)`; read with `@Environment(Router.self)`.
@Observable
@MainActor
final class Router {
    var tab: AppTab = .goals
    var goalsPath: [PushRoute] = []
    var habitsPath: [PushRoute] = []
    var sheet: SheetRoute?
    /// Shown by `.toast(text:)` at the root for 2.5 s.
    var toast: String?
    /// A `.json` file opened from outside the app (Files, share). `ImportPlanView` reads it on appear and sets it to nil.
    var pendingImportURL: URL?

    init() {}

    /// Maps notification and URL links (§6.5).
    func open(_ link: DeepLink) {
        switch link {
        case .habit(let habitID, let day):
            sheet = .markHabit(habitID, day)
        case .today:
            sheet = .today
        case .week:
            sheet = nil
            tab = .week
        case .goal(let goalID):
            sheet = nil
            tab = .goals
            goalsPath = [.goalDetail(goalID)]
        case .block(let blockID):
            tab = .calendar
            sheet = .block(blockID)
        case .settings:
            sheet = nil
            tab = .goals
            goalsPath = [.settings]
        }
    }

    /// Pushes onto the current tab's path. Calendar and Week have no paths, so pushes from there go to Goals.
    func push(_ route: PushRoute) {
        switch tab {
        case .habits:
            habitsPath.append(route)
        case .goals:
            goalsPath.append(route)
        case .calendar, .week:
            tab = .goals
            goalsPath.append(route)
        }
    }
}
