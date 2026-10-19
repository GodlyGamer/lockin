import Foundation
import CoreKit

/// The four tabs, in order (§7).
enum AppTab: Hashable {
    case goals, calendar, habits, week
}

/// Pushed screens. Goals and Habits own a navigation path in `Router`.
enum PushRoute: Hashable {
    case goalDetail(UUID)
    /// nil = new standalone habit.
    case habitEditor(UUID?)
    case settings
}

/// Every sheet in the app, presented from `RootTabView` through `Router.sheet`.
enum SheetRoute: Identifiable, Hashable {
    case markHabit(UUID, LocalDay)
    case today
    case conflict(UUID)
    case block(UUID)
    case newBlock(Date)
    case newGoal
    /// nil = new goal from a plan; a goal id = update mode.
    case importPlan(UUID?)

    var id: String {
        switch self {
        case .markHabit(let habitID, let day): "markHabit-\(habitID.uuidString)-\(day.string)"
        case .today: "today"
        case .conflict(let blockID): "conflict-\(blockID.uuidString)"
        case .block(let blockID): "block-\(blockID.uuidString)"
        case .newBlock(let start): "newBlock-\(start.timeIntervalSince1970)"
        case .newGoal: "newGoal"
        case .importPlan(let goalID): "importPlan-\(goalID?.uuidString ?? "new")"
        }
    }
}
