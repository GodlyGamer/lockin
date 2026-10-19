import SwiftUI
import CoreKit

/// DESIGN.md §7.4. Presented bare by the shell through `Router.sheet`, so it carries its own detents and no navigation bar.
struct HabitMarkSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let habitID: UUID
    let day: LocalDay

    @State private var currentDay: LocalDay
    @State private var count = 0
    @State private var countDirty = false
    @State private var countTask: Task<Void, Never>?
    @State private var saveFailed = false
    @State private var isClosing = false
    @State private var haptic = HapticEvent.mMarkedOrCleared
    @State private var hapticTick = 0

    init(habitID: UUID, day: LocalDay) {
        self.habitID = habitID
        self.day = day
        _currentDay = State(initialValue: day)
    }

    var body: some View {
        let _ = services.store.revision
        let snapshot = services.store.snapshot()
        let habit = snapshot.habit(habitID)
        let detentHeight: CGFloat = habit?.kind == .count ? 300 : 220
        Group {
            if let habit {
                sheetContent(habit: habit, snapshot: snapshot)
            } else {
                missingContent
            }
        }
        .presentationDetents([.height(detentHeight)])
        .presentationDragIndicator(.visible)
        .haptic(haptic, trigger: hapticTick)
        .onAppear { syncCount() }
        .onDisappear { flushCount() }
    }

    // MARK: - Content

    private func sheetContent(habit: Habit, snapshot: StoreSnapshot) -> some View {
        let today = HabitEngine.logicalDay(for: Date())
        let existing = snapshot.log(habitID: habit.id, day: currentDay)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(habit: habit, snapshot: snapshot, today: today, hasMark: existing != nil)
                if habit.kind == .count {
                    countControls(habit: habit, hasLog: existing != nil)
                } else {
                    checkControls(habit: habit, current: existing?.mark)
                }
                if saveFailed {
                    Text("Couldn't save. Try again.")
                        .font(.footnote)
                        .foregroundStyle(Color.emberText)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var missingContent: some View {
        VStack(spacing: 12) {
            Text("This habit no longer exists.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private func header(habit: Habit, snapshot: StoreSnapshot, today: LocalDay, hasMark: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title)
                    .font(.sectionTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                dayControl(habit: habit, snapshot: snapshot, today: today)
            }
            Spacer(minLength: 8)
            Button("Clear mark") { clearMark() }
                .font(.subheadline)
                .buttonStyle(.plain)
                .foregroundStyle(hasMark ? Color.cobaltText : Color.textTertiary)
                .disabled(!hasMark || isClosing)
                .frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private func dayControl(habit: Habit, snapshot: StoreSnapshot, today: LocalDay) -> some View {
        let options = allowedDays(habit: habit, snapshot: snapshot, today: today)
        let label = LockInFormat.relativeDay(currentDay, today: today)
        if options.count > 1 {
            Menu {
                ForEach(options, id: \.self) { option in
                    Button {
                        changeDay(to: option)
                    } label: {
                        if option == currentDay {
                            Label(dayLabel(option, today: today), systemImage: "checkmark")
                        } else {
                            Text(dayLabel(option, today: today))
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(label)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .font(.subheadline)
                .foregroundStyle(Color.cobaltText)
                .frame(minHeight: 28)
            }
            .accessibilityLabel("Day: \(label)")
            .accessibilityHint("Change the day")
        } else {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Check habits

    private func checkControls(habit: Habit, current: Mark?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            markButton(.D, title: "Done", caption: nil, accessibility: "Done", current: current)
            markButton(.B, title: habit.badDayTitle, caption: "Bad day", accessibility: "Bad-day version: \(habit.badDayTitle)", current: current)
            markButton(.M, title: "Missed", caption: nil, accessibility: "Missed", current: current)
        }
    }

    private func markButton(_ mark: Mark, title: String, caption: String?, accessibility: String, current: Mark?) -> some View {
        let isCurrent = current == mark
        return Button {
            setMark(mark)
        } label: {
            VStack(spacing: 6) {
                MarkDot(mark: mark, scheduled: true, size: 36)
                    .frame(height: 40)
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(isCurrent ? 0.14 : 0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isCurrent ? Color.cobaltText.opacity(0.7) : Color.white.opacity(0.14), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isClosing)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    // MARK: - Count habits

    private func countControls(habit: Habit, hasLog: Bool) -> some View {
        let showMark = hasLog || countDirty
        let derived: Mark? = showMark ? HabitEngine.derivedMark(count: count, habit: habit) : nil
        let unitText = (habit.unit ?? "").isEmpty ? "" : " \(habit.unit ?? "")"
        return VStack(spacing: 10) {
            HStack(spacing: 24) {
                stepButton(systemImage: "minus", label: "Decrease", enabled: count > 0) { bump(-1) }
                Text("\(count)")
                    .font(.largeTitle.monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                    .frame(minWidth: 64)
                    .accessibilityLabel("Count \(count)\(unitText)")
                stepButton(systemImage: "plus", label: "Increase", enabled: count < 99) { bump(1) }
            }
            Text("Target \(habit.target)\(unitText), bad day \(habit.badDayTarget)")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: 8) {
                MarkDot(mark: derived, scheduled: true, size: 16)
                Text(derivedText(derived, habit: habit))
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity)
    }

    private func derivedText(_ mark: Mark?, habit: Habit) -> String {
        guard let mark else { return "No mark yet" }
        switch mark {
        case .D: return "Done"
        case .B: return "Bad-day version: \(habit.badDayTitle)"
        case .M: return "Missed"
        }
    }

    private func stepButton(systemImage: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(enabled ? Color.textPrimary : Color.textTertiary)
                .frame(width: 56, height: 56)
                .background { Circle().fill(Color.white.opacity(0.08)) }
                .overlay { Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isClosing)
        .accessibilityLabel(label)
    }

    // MARK: - Days

    private func dayLabel(_ day: LocalDay, today: LocalDay) -> String {
        let relative = LockInFormat.relativeDay(day, today: today)
        let full = LockInFormat.dayMonth(day)
        return relative == full ? full : "\(relative), \(full)"
    }

    /// The current week up to today, plus last week while its review is unfinished (§7.4). Newest first.
    private func allowedDays(habit: Habit, snapshot: StoreSnapshot, today: LocalDay) -> [LocalDay] {
        let thisWeek = Week(containing: today)
        var days = thisWeek.days.filter { $0 <= today }
        let previous = thisWeek.previous
        var previousLocked = false
        if let goalID = habit.goalID, let review = snapshot.weekReview(goalID: goalID, week: previous), review.finishedAt != nil {
            previousLocked = true
        }
        if !previousLocked {
            days += previous.days
        }
        if !days.contains(currentDay) {
            days.append(currentDay)
        }
        return Array(Set(days)).sorted(by: >)
    }

    private func changeDay(to newDay: LocalDay) {
        guard newDay != currentDay else { return }
        countTask?.cancel()
        commitCount()
        currentDay = newDay
        syncCount()
    }

    // MARK: - Writing marks

    private func fire(_ event: HapticEvent) {
        haptic = event
        hapticTick += 1
    }

    private func setMark(_ mark: Mark) {
        guard !isClosing else { return }
        let services = self.services
        let existing = services.store.snapshot().log(habitID: habitID, day: currentDay)
        let log = HabitLog(id: existing?.id ?? UUID(), habitID: habitID, day: currentDay, mark: mark, count: nil, loggedAt: Date())
        do {
            try services.store.apply(ChangeSet(upserts: [.log(log)]))
        } catch {
            saveFailed = true
            return
        }
        saveFailed = false
        fire(HapticEvent.forMark(mark))
        closeAndReschedule()
    }

    private func clearMark() {
        guard !isClosing else { return }
        let services = self.services
        countTask?.cancel()
        countDirty = false
        guard let existing = services.store.snapshot().log(habitID: habitID, day: currentDay) else { return }
        do {
            try services.store.apply(ChangeSet(deletes: [EntityRef(.log, existing.id)]))
        } catch {
            saveFailed = true
            return
        }
        saveFailed = false
        count = 0
        fire(HapticEvent.forMark(nil))
        closeAndReschedule()
    }

    /// Closes the sheet a beat after the haptic fires, then reschedules the reminders (§4 rules: after every mark).
    private func closeAndReschedule() {
        isClosing = true
        let services = self.services
        let dismiss = self.dismiss
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            dismiss()
            await services.notifications.reschedule()
        }
    }

    // MARK: - Count habits: derived mark, saved 0.6 s after the last tap

    private func bump(_ delta: Int) {
        guard !isClosing else { return }
        let next = min(max(count + delta, 0), 99)
        guard next != count else { return }
        count = next
        countDirty = true
        countTask?.cancel()
        countTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            commitCount()
        }
    }

    private func commitCount() {
        guard countDirty else { return }
        let services = self.services
        let snapshot = services.store.snapshot()
        guard let habit = snapshot.habit(habitID) else { return }
        let existing = snapshot.log(habitID: habitID, day: currentDay)
        let mark = HabitEngine.derivedMark(count: count, habit: habit)
        let log = HabitLog(id: existing?.id ?? UUID(), habitID: habitID, day: currentDay, mark: mark, count: count, loggedAt: Date())
        do {
            try services.store.apply(ChangeSet(upserts: [.log(log)]))
        } catch {
            saveFailed = true
            return
        }
        saveFailed = false
        countDirty = false
        fire(HapticEvent.forMark(mark))
        Task { await services.notifications.reschedule() }
    }

    /// Leaving the sheet within 0.6 s of the last tap still saves the count.
    private func flushCount() {
        countTask?.cancel()
        commitCount()
    }

    private func syncCount() {
        let log = services.store.snapshot().log(habitID: habitID, day: currentDay)
        count = log?.count ?? 0
        countDirty = false
    }
}

#Preview("Check habit") {
    HabitMarkSheet(habitID: SampleData.liftHabitID, day: HabitEngine.logicalDay(for: .now))
        .environment(AppServices.preview())
        .environment(Router())
}

#Preview("Count habit") {
    HabitMarkSheet(habitID: SampleData.proteinHabitID, day: HabitEngine.logicalDay(for: .now))
        .environment(AppServices.preview())
        .environment(Router())
}
