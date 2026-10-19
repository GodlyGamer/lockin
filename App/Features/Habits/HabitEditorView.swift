import SwiftUI
import CoreKit

/// DESIGN.md §7.9 habit editor. Pushed by the shell onto the Habits stack, so it has no stack of its own.
struct HabitEditorView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let habitID: UUID?

    @State private var draft = HabitsEditorDraft()
    @State private var reminderTime = Date()
    @State private var existing: Habit?
    @State private var isLoaded = false
    @State private var isMissing = false
    @State private var isSaving = false
    @State private var saveError: String?

    init(habitID: UUID?) {
        self.habitID = habitID
    }

    var body: some View {
        let _ = services.store.revision
        let snapshot = services.store.snapshot()
        NightCanvas {
            Group {
                if isMissing {
                    Text("This habit no longer exists.")
                        .font(.body)
                        .foregroundStyle(Color.textSecondary)
                } else if isLoaded {
                    form(snapshot: snapshot)
                } else {
                    Color.clear
                }
            }
        }
        .navigationTitle(habitID == nil ? "New habit" : "Edit habit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!isLoaded || !draft.isValid || isSaving)
            }
        }
        .task { load() }
    }

    // MARK: - Loading

    private func load() {
        guard !isLoaded, !isMissing else { return }
        var loadedDraft = HabitsEditorDraft()
        if let habitID {
            guard let habit = services.store.snapshot().habit(habitID) else {
                isMissing = true
                return
            }
            existing = habit
            loadedDraft = HabitsEditorDraft(habit: habit)
        }
        draft = loadedDraft
        reminderTime = Self.date(forMinutes: loadedDraft.reminderMinutes)
        isLoaded = true
    }

    private static func date(forMinutes minutes: Int) -> Date {
        Calendar.lockIn.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    // MARK: - Form

    private func form(snapshot: StoreSnapshot) -> some View {
        let notificationsDenied = services.notifications.status == .denied || services.notifications.status == .restricted
        return Form {
            basicsSection
            typeSection
            scheduleSection
            setPointSection
            reminderSection(notificationsDenied: notificationsDenied)
            systemSection(snapshot: snapshot)
            if existing != nil {
                archiveSection
            }
            if let message = saveError ?? draft.problem {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(saveError != nil ? Color.emberText : Color.textSecondary)
                }
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: draft.scheduledPerWeek) { old, new in
            if draft.setPoint == old || draft.setPoint > new {
                draft.setPoint = max(1, new)
            }
        }
        .onChange(of: draft.target) { _, new in
            if draft.badDayTarget >= new {
                draft.badDayTarget = max(1, new - 1)
            }
        }
        .onChange(of: draft.remind) { _, isOn in
            if isOn { requestNotificationAccessIfNeeded() }
        }
        .onChange(of: reminderTime) { _, newTime in
            draft.reminderMinutes = TimeOfDay.minutes(of: newTime)
        }
    }

    private var basicsSection: some View {
        Section {
            TextField("Title", text: $draft.title)
                .textInputAutocapitalization(.sentences)
            TextField("Bad-day version", text: $draft.badDayTitle)
                .textInputAutocapitalization(.sentences)
        } header: {
            Text("Habit")
        } footer: {
            Text("The bad-day version is the smallest thing you would still do. It counts as a B.")
        }
        .listRowBackground(HabitsFieldSurface())
    }

    private var typeSection: some View {
        Section {
            Picker("Type", selection: $draft.kind) {
                Text("Check").tag(HabitKind.check)
                Text("Count").tag(HabitKind.count)
            }
            .pickerStyle(.segmented)
            if draft.kind == .count {
                Stepper("Target: \(draft.target)", value: $draft.target, in: 2...99)
                Stepper("Bad-day target: \(draft.badDayTarget)", value: $draft.badDayTarget,
                        in: 1...max(1, draft.target - 1))
                TextField("Unit, for example portions", text: $draft.unit)
            }
        } header: {
            Text("Type")
        }
        .listRowBackground(HabitsFieldSurface())
    }

    private var scheduleSection: some View {
        Section {
            Picker("Repeats", selection: $draft.frequencyKind) {
                ForEach(HabitsFrequencyKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            switch draft.frequencyKind {
            case .daily:
                EmptyView()
            case .days:
                HabitsWeekdayRow(title: "Days", selection: $draft.weekdays)
            case .perWeek:
                Stepper("Times a week: \(draft.timesPerWeek)", value: $draft.timesPerWeek, in: 1...7)
                HabitsWeekdayRow(title: "Nudge days", selection: $draft.preferredWeekdays)
            }
        } header: {
            Text("Schedule")
        } footer: {
            Text(scheduleFooter)
        }
        .listRowBackground(HabitsFieldSurface())
    }

    private var scheduleFooter: String {
        switch draft.frequencyKind {
        case .daily: return "Every day."
        case .days: return "Only on the days you pick."
        case .perWeek: return "Shows every day until it is done this many times in a week. Reminders only fire on the nudge days."
        }
    }

    private var setPointSection: some View {
        Section {
            Stepper("Set point: \(draft.setPoint) a week", value: $draft.setPoint,
                    in: 1...max(1, draft.scheduledPerWeek))
        } header: {
            Text("Set point")
        } footer: {
            Text("Out of \(draft.scheduledPerWeek) scheduled. Reach it and the habit counts as on target for the week.")
        }
        .listRowBackground(HabitsFieldSurface())
    }

    private func reminderSection(notificationsDenied: Bool) -> some View {
        Section {
            Toggle("Remind me", isOn: $draft.remind)
            if draft.remind {
                DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    .environment(\.timeZone, Calendar.lockIn.timeZone)
                if notificationsDenied {
                    PermissionBanner(title: "Reminders are off",
                                     body: "Turn on notifications in Settings so this nudge can fire.")
                }
            }
            Stepper("Duration: \(draft.durationMinutes) min", value: $draft.durationMinutes, in: 5...240, step: 5)
            Toggle("Physical", isOn: $draft.isPhysical)
            Picker("Priority", selection: $draft.priority) {
                Text("1 (highest)").tag(1)
                Text("2").tag(2)
                Text("3 (default)").tag(3)
                Text("4").tag(4)
                Text("5 (lowest)").tag(5)
            }
        } header: {
            Text("Reminder and effort")
        } footer: {
            Text("When more than four nudges land on one day, the lowest priority numbers win.")
        }
        .listRowBackground(HabitsFieldSurface())
    }

    private func systemSection(snapshot: StoreSnapshot) -> some View {
        Section {
            Picker("System", selection: $draft.systemID) {
                Text("None").tag(UUID?.none)
                ForEach(snapshot.sortedGoals, id: \.id) { goal in
                    ForEach(snapshot.systems(goalID: goal.id), id: \.id) { system in
                        Text("\(goal.title) · \(system.title)").tag(Optional(system.id))
                    }
                }
            }
        } header: {
            Text("System")
        } footer: {
            Text("Optional. A habit with no system is standalone.")
        }
        .listRowBackground(HabitsFieldSurface())
    }

    private var archiveSection: some View {
        Section {
            Button(existing?.isArchived == true ? "Restore habit" : "Archive habit") {
                toggleArchive()
            }
        } footer: {
            Text("Archived habits are hidden but keep their past marks in the Week tab.")
        }
        .listRowBackground(HabitsFieldSurface())
    }

    // MARK: - Actions

    private func requestNotificationAccessIfNeeded() {
        let services = self.services
        guard services.notifications.status == .notDetermined else { return }
        Task { _ = await services.notifications.requestAccess() }
    }

    private func save() {
        guard draft.isValid, !isSaving else { return }
        isSaving = true
        let services = self.services
        let dismiss = self.dismiss
        let snapshot = services.store.snapshot()
        var habit = existing ?? Habit(title: draft.trimmedTitle, badDayTitle: draft.trimmedBadDayTitle)

        habit.title = draft.trimmedTitle
        habit.badDayTitle = draft.trimmedBadDayTitle
        habit.kind = draft.kind
        if draft.kind == .count {
            habit.target = draft.target
            habit.badDayTarget = min(max(1, draft.badDayTarget), draft.target - 1)
            habit.unit = draft.trimmedUnit.isEmpty ? nil : draft.trimmedUnit
        } else {
            habit.target = 1
            habit.badDayTarget = 1
            habit.unit = nil
        }
        habit.frequency = draft.frequency
        habit.preferredWeekdays = draft.frequencyKind == .perWeek ? draft.preferredWeekdays.sorted() : []
        habit.setPointPerWeek = min(max(draft.setPoint, 1), max(1, draft.scheduledPerWeek))
        habit.reminderTime = draft.remind ? draft.reminderMinutes : nil
        habit.durationMinutes = draft.durationMinutes
        habit.isPhysical = draft.isPhysical
        habit.priority = draft.priority
        habit.systemID = draft.systemID
        if let systemID = draft.systemID {
            habit.goalID = snapshot.system(systemID)?.goalID ?? existing?.goalID
        } else {
            habit.goalID = nil
        }
        if existing == nil {
            let siblings = snapshot.habits.filter { $0.goalID == habit.goalID }
            habit.sortIndex = (siblings.map { $0.sortIndex }.max() ?? -1) + 1
        }

        do {
            try services.store.apply(ChangeSet(upserts: [.habit(habit)]))
        } catch {
            saveError = "Couldn't save. Try again."
            isSaving = false
            return
        }
        saveError = nil
        dismiss()
        Task { await services.notifications.reschedule() }
    }

    private func toggleArchive() {
        guard var habit = existing, !isSaving else { return }
        isSaving = true
        let services = self.services
        let dismiss = self.dismiss
        habit.isArchived.toggle()
        do {
            try services.store.apply(ChangeSet(upserts: [.habit(habit)]))
        } catch {
            saveError = "Couldn't save. Try again."
            isSaving = false
            return
        }
        dismiss()
        Task { await services.notifications.reschedule() }
    }
}

/// Seven round weekday toggles (M … S), each at least 44 pt tall.
struct HabitsWeekdayRow: View {
    let title: String
    @Binding var selection: Set<Int>

    private static let fullNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { weekday in
                    let isOn = selection.contains(weekday)
                    Button {
                        if isOn {
                            selection.remove(weekday)
                        } else {
                            selection.insert(weekday)
                        }
                    } label: {
                        Text(LockInFormat.weekdayLetters[weekday - 1])
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isOn ? Color.white : Color.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background { Capsule().fill(isOn ? Color.cobalt : Color.white.opacity(0.06)) }
                            .overlay { Capsule().strokeBorder(Color.white.opacity(isOn ? 0 : 0.14), lineWidth: 1) }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Self.fullNames[weekday - 1])
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview("New") {
    NavigationStack { HabitEditorView(habitID: nil) }
        .environment(AppServices.preview())
        .environment(Router())
}

#Preview("Count habit") {
    NavigationStack { HabitEditorView(habitID: SampleData.proteinHabitID) }
        .environment(AppServices.preview())
        .environment(Router())
}
