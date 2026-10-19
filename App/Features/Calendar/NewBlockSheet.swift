import SwiftUI
import CoreKit

/// New block sheet (DESIGN.md §5.1): title, system, duration and start. Creates a one-off block, then syncs.
struct NewBlockSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var systemID: UUID?
    @State private var durationMinutes = 60
    @State private var startDate: Date
    @State private var errorText: String?
    @State private var isSaving = false

    /// `start` is the long-pressed time, already rounded down to 15 minutes.
    init(start: Date) {
        _startDate = State(initialValue: start)
    }

    var body: some View {
        let _ = services.store.revision
        let snapshot = services.store.snapshot()
        let choices = systemChoices(snapshot)
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                }
                Section {
                    Picker("System", selection: $systemID) {
                        Text("None").tag(UUID?.none)
                        ForEach(choices) { choice in
                            Text(choice.label).tag(Optional(choice.id))
                        }
                    }
                }
                Section {
                    Stepper(value: $durationMinutes, in: 15...600, step: 15) {
                        LabeledContent("Duration", value: CalFormat.duration(minutes: durationMinutes))
                    }
                    DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.timeZone, Calendar.lockIn.timeZone)
                }
                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.subheadline)
                            .foregroundStyle(Color.emberText)
                    }
                }
            }
            .navigationTitle("New block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await add(choices: choices) } }
                        .disabled(trimmedTitle.isEmpty || isSaving)
                }
            }
            .onChange(of: systemID) { _, newValue in
                // Fill an empty title from the chosen system.
                if trimmedTitle.isEmpty, let choice = choices.first(where: { $0.id == newValue }) {
                    title = choice.systemTitle
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Systems of active goals, labelled "Goal · System".
    private func systemChoices(_ snapshot: StoreSnapshot) -> [CalSystemChoice] {
        var result: [CalSystemChoice] = []
        for goal in snapshot.sortedGoals where goal.status == .active {
            for system in snapshot.systems(goalID: goal.id) {
                result.append(CalSystemChoice(id: system.id, goalID: goal.id, systemTitle: system.title,
                                              label: "\(goal.title) · \(system.title)"))
            }
        }
        return result
    }

    private func add(choices: [CalSystemChoice]) async {
        guard !trimmedTitle.isEmpty else { return }
        isSaving = true
        errorText = nil
        let choice = choices.first { $0.id == systemID }
        let start = CalFormat.wholeMinute(startDate)
        let block = CalendarBlock(
            ruleID: nil,
            systemID: choice?.id,
            goalID: choice?.goalID,
            title: trimmedTitle,
            start: start,
            end: start.addingTimeInterval(TimeInterval(durationMinutes * 60)),
            status: .scheduled
        )
        do {
            try services.store.apply(ChangeSet(upserts: [.block(block)]))
        } catch {
            errorText = "Couldn't save. Try again."
            isSaving = false
            return
        }
        let report = await services.calendar.sync()
        if report.error != nil {
            router.toast = "Calendar didn't sync. Pull to retry."
        }
        isSaving = false
        dismiss()
    }
}

private struct CalSystemChoice: Identifiable {
    let id: UUID
    let goalID: UUID
    let systemTitle: String
    let label: String
}

#Preview {
    NewBlockSheet(start: LocalDay.today.date(minutes: 15 * 60))
        .environment(AppServices.preview())
        .environment(Router())
        .preferredColorScheme(.dark)
}
