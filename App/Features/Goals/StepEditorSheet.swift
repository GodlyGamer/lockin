import SwiftUI
import CoreKit

/// Add or edit a step of a milestone (§3.5). Without its own deadline a step inherits the milestone's.
struct StepEditorSheet: View {
    let goalID: UUID
    let step: Step?

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var objectiveID: UUID?
    @State private var minutes: Int
    @State private var isDone: Bool
    @State private var hasOwnDeadline: Bool
    @State private var deadline: LocalDay
    @State private var errorText: String?
    @State private var confirmDelete = false

    init(goalID: UUID, step: Step?, defaultObjectiveID: UUID?) {
        self.goalID = goalID
        self.step = step
        _title = State(initialValue: step?.title ?? "")
        _objectiveID = State(initialValue: step?.objectiveID ?? defaultObjectiveID)
        _minutes = State(initialValue: step?.estimatedMinutes ?? 30)
        _isDone = State(initialValue: step?.done ?? false)
        _hasOwnDeadline = State(initialValue: step?.deadline != nil)
        _deadline = State(initialValue: step?.deadline ?? LocalDay.today.adding(days: 7))
    }

    private var canSave: Bool {
        !GoalsFormat.trimmed(title).isEmpty && objectiveID != nil
    }

    var body: some View {
        let objectives = services.store.snapshot().objectives(goalID: goalID)

        NavigationStack {
            Form {
                Section("Step") {
                    TextField("Set up a food log", text: $title)
                    if objectives.isEmpty {
                        Text("Add a milestone first.")
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        Picker("Milestone", selection: $objectiveID) {
                            Text("Choose").tag(UUID?.none)
                            ForEach(objectives) { objective in
                                Text(objective.title).tag(Optional(objective.id))
                            }
                        }
                    }
                    Stepper(value: $minutes, in: 5...600, step: 5) {
                        Text("About \(minutes) min")
                    }
                    Toggle("Done", isOn: $isDone)
                }
                Section {
                    Toggle("Own deadline", isOn: $hasOwnDeadline)
                    if hasOwnDeadline {
                        GoalsDayPicker("Deadline", day: $deadline)
                    }
                } footer: {
                    Text("Off means the step finishes with its milestone.")
                }
                if let errorText {
                    Section { GoalsFormMessage(text: errorText) }
                }
                if step != nil {
                    Section {
                        Button("Delete step", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .modifier(GoalsEditorChrome(title: step == nil ? "New step" : "Step", canSave: canSave, onSave: save))
            .confirmationDialog("Delete this step?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete step", role: .destructive) { deleteStep() }
                Button("Keep", role: .cancel) {}
            }
        }
    }

    private func save() {
        guard let objectiveID else { return }
        let snapshot = services.store.snapshot()
        var entity = step ?? Step(objectiveID: objectiveID, title: "")
        if step == nil {
            let siblings = snapshot.steps.filter { $0.objectiveID == objectiveID }
            entity.sortIndex = (siblings.map(\.sortIndex).max() ?? -1) + 1
        }
        entity.title = GoalsFormat.trimmed(title)
        entity.objectiveID = objectiveID
        entity.estimatedMinutes = minutes
        entity.done = isDone
        entity.deadline = hasOwnDeadline ? deadline : nil
        Task {
            do {
                try await GoalsActions.commit(ChangeSet(upserts: [.step(entity)]), services: services)
                dismiss()
            } catch {
                errorText = GoalsActions.saveFailed
            }
        }
    }

    private func deleteStep() {
        guard let step else { return }
        Task {
            do {
                try await GoalsActions.commit(ChangeSet(deletes: [EntityRef(.step, step.id)]), services: services)
                dismiss()
            } catch {
                errorText = GoalsActions.saveFailed
            }
        }
    }
}

#Preview {
    StepEditorSheet(goalID: SampleData.goalID, step: nil, defaultObjectiveID: SampleData.objective84ID)
        .environment(AppServices.preview())
        .environment(Router())
}
