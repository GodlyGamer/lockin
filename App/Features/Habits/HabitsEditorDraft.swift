import Foundation
import CoreKit

nonisolated enum HabitsFrequencyKind: CaseIterable, Hashable {
    case daily
    case days
    case perWeek

    var title: String {
        switch self {
        case .daily: return "Daily"
        case .days: return "Days"
        case .perWeek: return "Times a week"
        }
    }
}

/// The editable copy of a habit while the editor is open (DESIGN.md §7.9, §3.6).
nonisolated struct HabitsEditorDraft {
    var title = ""
    var badDayTitle = ""
    var kind: HabitKind = .check
    var target = 4
    var badDayTarget = 3
    var unit = ""
    var frequencyKind: HabitsFrequencyKind = .daily
    var weekdays: Set<Int> = [1, 2, 3, 4, 5]
    var timesPerWeek = 3
    var preferredWeekdays: Set<Int> = []
    var setPoint = 7
    var remind = false
    var reminderMinutes = 480
    var durationMinutes = 15
    var isPhysical = false
    var priority = 3
    var systemID: UUID?

    init() {}

    init(habit: Habit) {
        title = habit.title
        badDayTitle = habit.badDayTitle
        kind = habit.kind
        if habit.kind == .count {
            target = max(2, habit.target)
            badDayTarget = min(max(1, habit.badDayTarget), target - 1)
        }
        unit = habit.unit ?? ""
        switch habit.frequency {
        case .daily:
            frequencyKind = .daily
        case .weekdays(let days):
            frequencyKind = .days
            weekdays = Set(days)
        case .perWeek(let n):
            frequencyKind = .perWeek
            timesPerWeek = n
        }
        preferredWeekdays = Set(habit.preferredWeekdays)
        setPoint = habit.setPointPerWeek
        remind = habit.reminderTime != nil
        reminderMinutes = habit.reminderTime ?? 480
        durationMinutes = habit.durationMinutes
        isPhysical = habit.isPhysical
        priority = habit.priority
        systemID = habit.systemID
    }

    var frequency: Frequency {
        switch frequencyKind {
        case .daily: return .daily
        case .days: return .weekdays(weekdays.sorted())
        case .perWeek: return .perWeek(timesPerWeek)
        }
    }

    var scheduledPerWeek: Int { Habit.scheduledPerWeek(frequency) }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedBadDayTitle: String { badDayTitle.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedUnit: String { unit.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Why the draft can't be saved yet, or nil when it can.
    var problem: String? {
        if trimmedTitle.isEmpty { return "Add a title." }
        if trimmedBadDayTitle.isEmpty { return "Add a bad-day version: the smallest thing you would still do." }
        if frequencyKind == .days && weekdays.isEmpty { return "Pick at least one day." }
        if kind == .count && (target < 2 || badDayTarget < 1 || badDayTarget >= target) {
            return "The bad-day target must be lower than the target."
        }
        return nil
    }

    var isValid: Bool { problem == nil }
}
