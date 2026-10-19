import SwiftUI
import CoreKit

// Shared helpers for the Goals module (M5). Every type here is prefixed `Goals` (one-module rule).

// MARK: - Formatting

enum GoalsFormat {
    /// 84.6 -> "84.6", 78 -> "78", 0.125 -> "0.13" (up to 2 decimals, no trailing zeros).
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value == value.rounded(), abs(value) < 1_000_000_000 {
            return String(Int(value))
        }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// Accepts "84.6" and "84,6". Nil when the text is not a number.
    static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    /// "84.6 kg" (or just "84.6" when the unit is empty).
    static func withUnit(_ value: Double, _ unit: String) -> String {
        let trimmedUnit = unit.trimmingCharacters(in: .whitespaces)
        return trimmedUnit.isEmpty ? number(value) : "\(number(value)) \(trimmedUnit)"
    }

    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func daysLeft(_ days: Int) -> String {
        days == 1 ? "1 day left" : "\(days) days left"
    }

    /// "Starts 4 days too late" (§4.5).
    static func startsLate(_ days: Int) -> String {
        days == 1 ? "Starts 1 day too late" : "Starts \(days) days too late"
    }

    /// "Mon" ... "Sun" for ISO weekdays; "?" when out of range.
    static func weekdayName(_ weekday: Int) -> String {
        guard (1...7).contains(weekday) else { return "?" }
        return LockInFormat.weekdayShortNames[weekday - 1]
    }

    static let fullWeekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// "Sun 17:00" for one day, "M W F 17:00" for several.
    static func weekdaysAndTime(_ weekdays: [Int], minutes: Int) -> String {
        let days = Array(Set(weekdays)).sorted()
        let dayText: String
        if days.count == 1, let only = days.first {
            dayText = weekdayName(only)
        } else {
            dayText = LockInFormat.frequency(.weekdays(days))
        }
        return "\(dayText) \(LockInFormat.time(minutes))"
    }

    static func objectiveStatus(_ status: ObjectiveStatus) -> String {
        switch status {
        case .notStarted: "Not started"
        case .inProgress: "In progress"
        case .done: "Done"
        }
    }

    static func goalStatus(_ status: GoalStatus) -> String {
        switch status {
        case .active: "Active"
        case .paused: "Paused"
        case .achieved: "Achieved"
        case .dropped: "Dropped"
        }
    }

    /// A fixed day without a clock change, used to turn minutes-after-midnight into a `Date` for time pickers.
    static let referenceDay = LocalDay(year: 2026, month: 1, day: 15)
}

// MARK: - Ordering

enum GoalsOrdering {
    /// The `sortIndex` values to hand out to `count` siblings. Reuses the siblings' own values when they are all
    /// different (so the group keeps its place relative to other groups); otherwise numbers them from the lowest.
    static func slots(from values: [Int], count: Int) -> [Int] {
        let sorted = values.sorted()
        let allDifferent = zip(sorted, sorted.dropFirst()).allSatisfy { $0 < $1 }
        if allDifferent, sorted.count == count { return sorted }
        let base = sorted.first ?? 0
        return (0..<count).map { base + $0 }
    }

    /// Upserts for `items` (already in their new order) whose `sortIndex` has to change.
    static func reassign<T>(_ items: [T], index: WritableKeyPath<T, Int>, wrap: (T) -> AnyEntity) -> [AnyEntity] {
        let slots = slots(from: items.map { $0[keyPath: index] }, count: items.count)
        var upserts: [AnyEntity] = []
        for (offset, item) in items.enumerated() {
            guard item[keyPath: index] != slots[offset] else { continue }
            var copy = item
            copy[keyPath: index] = slots[offset]
            upserts.append(wrap(copy))
        }
        return upserts
    }
}

// MARK: - Back-scheduling

enum GoalsScheduling {
    /// Objectives of `goalID` whose stored deadline differs from the back-scheduled one. Overridden deadlines are kept (§4.5).
    static func deadlineUpdates(snapshot: StoreSnapshot, goalID: UUID, today: LocalDay) -> [Objective] {
        guard let goal = snapshot.goal(goalID) else { return [] }
        let objectives = snapshot.objectives(goalID: goalID)
        let result = ScheduleEngine.backSchedule(objectives: objectives, goal: goal, today: today)
        var updated: [Objective] = []
        for objective in objectives where !objective.deadlineOverridden {
            let computed = result.deadlines[objective.id]
            if objective.deadline != computed {
                var copy = objective
                copy.deadline = computed
                updated.append(copy)
            }
        }
        return updated
    }
}

// MARK: - Store writes

enum GoalsSideEffect {
    case none
    /// Habit / reminder / settings style edits.
    case reschedule
    /// Anything touching blocks or rules, and imports. `sync()` also reschedules.
    case calendarSync
}

enum GoalsActions {
    static let saveFailed = "Couldn't save. Try again."

    /// Applies `changes`. When `goalID` is given, back-scheduling is re-run on the result and every non-overridden
    /// objective deadline is written in the same change set (F8.3). Then runs the side effect.
    static func commit(_ changes: ChangeSet, goalID: UUID? = nil, then effect: GoalsSideEffect = .none,
                       services: AppServices) async throws {
        var all = changes
        if let goalID {
            let merged = services.store.snapshot().applying(changes)
            let updates = GoalsScheduling.deadlineUpdates(snapshot: merged, goalID: goalID, today: LocalDay.today)
            all.upserts.append(contentsOf: updates.map { AnyEntity.objective($0) })
        }
        try services.store.apply(all)
        switch effect {
        case .none:
            break
        case .reschedule:
            await services.notifications.reschedule()
        case .calendarSync:
            _ = await services.calendar.sync()
        }
    }
}

// MARK: - Layout pieces

/// A solid tile: the tile gradient with the 1 pt stroke. Content is never glass (§8.7).
struct GoalsCard<Content: View>: View {
    private let content: Content
    private let radius: CGFloat

    init(radius: CGFloat = 22, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Color.tileTop, Color.tileBottom], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
            )
    }
}

/// A solid banner (check-in, re-sign, errors). Optionally tappable.
struct GoalsBannerCard: View {
    let systemImage: String
    let title: String
    var message: String? = nil
    var iconTint: Color = Color.cobaltText
    var fill: Color = Color.white.opacity(0.06)
    var stroke: Color = Color.white.opacity(0.14)
    var showsChevron = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(iconTint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(stroke, lineWidth: 1)
        )
    }
}

/// Solid capsule buttons for in-content actions. (The only prominent glass button is the toolbar "New goal".)
struct GoalsSolidButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(prominent ? Color.white : Color.textPrimary)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Capsule().fill(prominent ? Color.cobalt : Color.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(prominent ? 0 : 0.14), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

/// A multi-select / single-select chip (intake rounds, weekday pickers).
struct GoalsChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(isOn ? Color.white : Color.textPrimary)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(isOn ? Color.cobalt : Color.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(isOn ? Color.cobaltText.opacity(0.4) : Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The field look used on intake pages: 6% fill, 14% stroke, radius 10 (§8.1, §8.3).
struct GoalsFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
    }
}

// MARK: - Form controls

/// A decimal field that writes to `value` on every keystroke (so "Next" never loses a half-committed number).
struct GoalsNumberField: View {
    let placeholder: String
    @Binding var value: Double
    @State private var text = ""
    @State private var didLoad = false

    init(_ placeholder: String, value: Binding<Double>) {
        self.placeholder = placeholder
        self._value = value
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.decimalPad)
            .onAppear {
                if !didLoad {
                    text = GoalsFormat.number(value)
                    didLoad = true
                }
            }
            .onChange(of: text) { _, newText in
                if let parsed = GoalsFormat.parse(newText) {
                    if parsed != value { value = parsed }
                } else if GoalsFormat.trimmed(newText).isEmpty, value != 0 {
                    value = 0
                }
            }
    }
}

/// A `DatePicker` over a `LocalDay` (London calendar), without closure-based bindings.
struct GoalsDayPicker: View {
    let title: String
    @Binding var day: LocalDay
    let minimum: LocalDay?
    @State private var date: Date

    init(_ title: String, day: Binding<LocalDay>, minimum: LocalDay? = nil) {
        self.title = title
        self._day = day
        self.minimum = minimum
        self._date = State(initialValue: day.wrappedValue.date(minutes: 720))
    }

    var body: some View {
        Group {
            if let minimum {
                DatePicker(title, selection: $date, in: minimum.date(minutes: 0)..., displayedComponents: .date)
            } else {
                DatePicker(title, selection: $date, displayedComponents: .date)
            }
        }
        .environment(\.calendar, Calendar.lockIn)
        .environment(\.timeZone, Calendar.lockIn.timeZone)
        .onChange(of: date) { _, newDate in
            let newDay = LocalDay(newDate)
            if newDay != day { day = newDay }
        }
        .onChange(of: day) { _, newDay in
            if LocalDay(date) != newDay { date = newDay.date(minutes: 720) }
        }
    }
}

/// A time-of-day `DatePicker` over minutes after midnight.
struct GoalsTimePicker: View {
    let title: String
    @Binding var minutes: Int
    @State private var date: Date

    init(_ title: String, minutes: Binding<Int>) {
        self.title = title
        self._minutes = minutes
        self._date = State(initialValue: GoalsFormat.referenceDay.date(minutes: minutes.wrappedValue))
    }

    var body: some View {
        DatePicker(title, selection: $date, displayedComponents: .hourAndMinute)
            .environment(\.calendar, Calendar.lockIn)
            .environment(\.timeZone, Calendar.lockIn.timeZone)
            .onChange(of: date) { _, newDate in
                let newMinutes = TimeOfDay.minutes(of: newDate)
                if newMinutes != minutes { minutes = newMinutes }
            }
            .onChange(of: minutes) { _, newMinutes in
                if TimeOfDay.minutes(of: date) != newMinutes {
                    date = GoalsFormat.referenceDay.date(minutes: newMinutes)
                }
            }
    }
}

/// Seven weekday toggles, M ... S (ISO 1 ... 7).
struct GoalsWeekdayChips: View {
    @Binding var days: [Int]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let isOn = days.contains(day)
                Button {
                    if isOn {
                        days.removeAll { $0 == day }
                    } else {
                        days.append(day)
                        days.sort()
                    }
                } label: {
                    Text(LockInFormat.weekdayLetters[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isOn ? Color.white : Color.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isOn ? Color.cobalt : Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(isOn ? Color.cobaltText.opacity(0.4) : Color.white.opacity(0.14), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(GoalsFormat.fullWeekdayNames[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

// MARK: - Editor chrome

/// Cancel / Save toolbar and inline title for the editor sheets. Apply inside the sheet's `NavigationStack`.
struct GoalsEditorChrome: ViewModifier {
    let title: String
    let canSave: Bool
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .disabled(!canSave)
                }
            }
    }
}

/// A small ember line under a form for validation text or a failed save.
struct GoalsFormMessage: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.emberText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
