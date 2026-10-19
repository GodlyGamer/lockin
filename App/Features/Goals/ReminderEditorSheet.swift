import SwiftUI
import CoreKit

private enum GoalsReminderRepeat: Hashable {
    case once, weekly
}

/// Add or edit a plan reminder (§3.11): one-off on a date, or repeating on weekdays.
struct ReminderEditorSheet: View {
    let goalID: UUID
    let reminder: PlanReminder?

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var message: String
    @State private var systemID: UUID?
    @State private var repeatMode: GoalsReminderRepeat
    @State private var date: LocalDay
    @State private var weekdays: [Int]
    @State private var time: Int
    @State private var priority: Int
    @State private var active: Bool
    @State private var errorText: String?
    @State private var confirmDelete = false

    init(goalID: UUID, reminder: PlanReminder?, defaultSystemID: UUID?) {
        self.goalID = goalID
        self.reminder = reminder
        _title = State(initialValue: reminder?.title ?? "")
        _message = State(initialValue: reminder?.body ?? "")
        _systemID = State(initialValue: reminder?.systemID ?? defaultSystemID)
        _repeatMode = State(initialValue: (reminder?.date == nil && !(reminder?.weekdays.isEmpty ?? true)) ? .weekly : .once)
        _date = State(initialValue: reminder?.date ?? LocalDay.today.adding(days: 1))
        _weekdays = State(initialValue: reminder?.weekdays ?? [])
        _time = State(initialValue: reminder?.time ?? 600)
        _priority = State(initialValue: reminder?.priority ?? 3)
        _active = State(initialValue: reminder?.active ?? true)
    }

    private var validationMessage: String? {
        if GoalsFormat.trimmed(title).isEmpty { return "Add a title." }
        if systemID == nil { return "Pick a system first." }
        if repeatMode == .weekly && weekdays.isEmpty { return "Pick at least one day." }
        return nil
    }

    var body: some View {
        let systems = services.store.snapshot().systems(goalID: goalID)

        NavigationStack {
            Form {
                Section("Reminder") {
                    TextField("Order the food shop", text: $title)
                    TextField("Message", text: $message, axis: .vertical)
                        .lineLimit(1...4)
                    if systems.isEmpty {
                        Text("Add a system first.")
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        Picker("System", selection: $systemID) {
                            Text("Choose").tag(UUID?.none)
                            ForEach(systems) { system in
                                Text(system.title).tag(Optional(system.id))
                            }
                        }
                    }
                }
                Section("When") {
                    Picker("Repeat", selection: $repeatMode) {
                        Text("Once").tag(GoalsReminderRepeat.once)
                        Text("Weekly").tag(GoalsReminderRepeat.weekly)
                    }
                    .pickerStyle(.segmented)
                    if repeatMode == .once {
                        GoalsDayPicker("Date", day: $date)
                    } else {
                        GoalsWeekdayChips(days: $weekdays)
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    }
                    GoalsTimePicker("Time", minutes: $time)
                }
                Section {
                    Stepper(value: $priority, in: 1...5) {
                        Text("Priority \(priority)")
                    }
                    Toggle("Active", isOn: $active)
                } footer: {
                    Text("1 is the highest. Priority decides which nudges win the daily limit.")
                }
                if let message = validationMessage {
                    Section { GoalsFormMessage(text: message) }
                }
                if let errorText {
                    Section { GoalsFormMessage(text: errorText) }
                }
                if reminder != nil {
                    Section {
                        Button("Delete reminder", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .modifier(GoalsEditorChrome(title: reminder == nil ? "New reminder" : "Reminder",
                                        canSave: validationMessage == nil, onSave: save))
            .confirmationDialog("Delete this reminder?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete reminder", role: .destructive) { deleteReminder() }
                Button("Keep", role: .cancel) {}
            }
        }
    }

    private func save() {
        var entity = reminder ?? PlanReminder(title: "", time: time)
        entity.title = GoalsFormat.trimmed(title)
        entity.body = GoalsFormat.trimmed(message)
        entity.systemID = systemID
        entity.date = repeatMode == .once ? date : nil
        entity.weekdays = repeatMode == .weekly ? weekdays.sorted() : []
        entity.time = time
        entity.priority = priority
        entity.active = active
        Task {
            do {
                try await GoalsActions.commit(ChangeSet(upserts: [.reminder(entity)]), then: .reschedule, services: services)
                dismiss()
            } catch {
                errorText = GoalsActions.saveFailed
            }
        }
    }

    private func deleteReminder() {
        guard let reminder else { return }
        Task {
            do {
                try await GoalsActions.commit(ChangeSet(deletes: [EntityRef(.reminder, reminder.id)]), then: .reschedule,
                                              services: services)
                dismiss()
            } catch {
                errorText = GoalsActions.saveFailed
            }
        }
    }
}

#Preview {
    ReminderEditorSheet(goalID: SampleData.goalID, reminder: nil, defaultSystemID: SampleData.mealsSystemID)
        .environment(AppServices.preview())
        .environment(Router())
}
