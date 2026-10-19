import Foundation
import CoreKit

nonisolated struct HabitsRowModel: Identifiable {
    let id: UUID
    let habit: Habit
    let subtitle: String
    let mark: Mark?
}

nonisolated struct HabitsSectionModel: Identifiable {
    let id: String
    let title: String
    let rows: [HabitsRowModel]
}

nonisolated struct HabitsListModel {
    var sections: [HabitsSectionModel]
    var activeCount: Int
    var archivedCount: Int

    var isEmpty: Bool { activeCount == 0 && archivedCount == 0 }
}

/// Builds the Habits tab sections from a snapshot (DESIGN.md §7.9).
enum HabitsListBuilder {
    static func build(snapshot: StoreSnapshot, showArchived: Bool, today: LocalDay) -> HabitsListModel {
        let week = Week(containing: today)

        func row(_ habit: Habit) -> HabitsRowModel {
            let score = HabitEngine.weekScore(habit: habit, week: week, logs: snapshot.logs)
            let streak = HabitEngine.habitStreak(habit: habit, logs: snapshot.logs, currentWeek: week)
            var parts: [String] = []
            if habit.isArchived { parts.append("Archived") }
            parts.append(LockInFormat.frequency(habit.frequency))
            parts.append("this week \(score.done)/\(score.setPoint)")
            if streak > 0 { parts.append("\(streak)-week streak") }
            let mark: Mark? = habit.isArchived ? nil : snapshot.log(habitID: habit.id, day: today)?.mark
            return HabitsRowModel(id: habit.id, habit: habit, subtitle: parts.joined(separator: " · "), mark: mark)
        }

        func sorted(_ habits: [Habit]) -> [Habit] {
            habits.sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
                return lhs.createdAt < rhs.createdAt
            }
        }

        let active = snapshot.habits.filter { !$0.isArchived }
        let archived = sorted(snapshot.habits.filter { $0.isArchived })
        let goals = snapshot.sortedGoals
        let goalIDs = Set(goals.map { $0.id })

        var sections: [HabitsSectionModel] = []
        for goal in goals {
            let habits = sorted(active.filter { $0.goalID == goal.id })
            if !habits.isEmpty {
                sections.append(HabitsSectionModel(id: goal.id.uuidString, title: LockInFormat.titled(goal.title),
                                                   rows: habits.map { row($0) }))
            }
        }
        let standalone = sorted(active.filter { habit in
            guard let goalID = habit.goalID else { return true }
            return !goalIDs.contains(goalID)
        })
        if !standalone.isEmpty {
            sections.append(HabitsSectionModel(id: "standalone", title: "Standalone", rows: standalone.map { row($0) }))
        }
        if showArchived && !archived.isEmpty {
            sections.append(HabitsSectionModel(id: "archived", title: "Archived", rows: archived.map { row($0) }))
        }
        return HabitsListModel(sections: sections, activeCount: active.count, archivedCount: archived.count)
    }
}
