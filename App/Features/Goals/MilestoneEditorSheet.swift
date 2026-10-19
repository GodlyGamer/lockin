import SwiftUI
import CoreKit

/// Add or edit a milestone (§3.4): estimate, status, optional fixed deadline, driving systems, dependencies.
/// Saving re-runs back-scheduling for the whole goal (F8.3).
struct MilestoneEditorSheet: View {
    let goalID: UUID
    let objective: Objective?
    private let objectiveID: UUID

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var estimatedDays: Int
    @State private var status: ObjectiveStatus
    @State private var isOverridden: Bool
    @State private var deadline: LocalDay
    @State private var systemIDs: [UUID]
    @State private var dependsOnIDs: [UUID]
    @State private var showDependencies = false
    @State private var errorText: String?
    @State private var confirmDelete = false

    init(goalID: UUID, objective: Objective?) {
        self.goalID = goalID
        self.objective = objective
        self.objectiveID = objective?.id ?? UUID()
        _title = State(initialValue: objective?.title ?? "")
        _estimatedDays = State(initialValue: objective?.estimatedDays ?? 14)
        _status = State(initialValue: objective?.status ?? .notStarted)
        _isOverridden = State(initialValue: objective?.deadlineOverridden ?? false)
        _deadline = State(initialValue: objective?.deadline ?? LocalDay.today.adding(days: 30))
        _systemIDs = State(initialValue: objective?.systemIDs ?? [])
        _dependsOnIDs = State(initialValue: objective?.dependsOnIDs ?? [])
    }

    var body: some View {
        let snapshot = services.store.snapshot()
        let systems = snapshot.systems(goalID: goalID)

        NavigationStack {
            Form {
                Section("Milestone") {
                    TextField("82.0 kg", text: $title)
                    Stepper(value: $estimatedDays, in: 1...365) {
                        Text("Takes \(estimatedDays) day\(estimatedDays == 1 ? "" : "s")")
                    }
                    Picker("Status", selection: $status) {
                        ForEach(ObjectiveStatus.allCases, id: \.self) { item in
                            Text(GoalsFormat.objectiveStatus(item)).tag(item)
                        }
                    }
                }
                Section {
                    Toggle("Fix the deadline", isOn: $isOverridden)
                    if isOverridden {
                        GoalsDayPicker("Deadline", day: $deadline)
                    } else if let calculated = objective?.deadline {
                        LabeledContent("Calculated", value: LockInFormat.dayMonth(calculated))
                    }
                } header: {
                    Text("Deadline")
                } footer: {
                    Text("Unless fixed, the deadline is worked out backwards from the goal deadline.")
                }
                Section("Depends on") {
                    if dependsOnIDs.isEmpty {
                        Text("Nothing. It can start right away.")
                            .foregroundStyle(Color.textSecondary)
                    }
                    ForEach(dependsOnIDs, id: \.self) { id in
                        Text(snapshot.objective(id)?.title ?? "Milestone")
                    }
                    Button("Choose…") { showDependencies = true }
                }
                Section("Driven by") {
                    if systems.isEmpty {
                        Text("No systems yet.")
                            .foregroundStyle(Color.textSecondary)
                    }
                    ForEach(systems) { system in
                        Button {
                            toggleSystem(system.id)
                        } label: {
                            HStack {
                                Text(system.title)
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                if systemIDs.contains(system.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.cobaltText)
                                }
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(systemIDs.contains(system.id) ? .isSelected : [])
                    }
                }
                if let errorText {
                    Section { GoalsFormMessage(text: errorText) }
                }
                if objective != nil {
                    Section {
                        Button("Delete milestone", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Its steps are deleted too.")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .modifier(GoalsEditorChrome(title: objective == nil ? "New milestone" : "Milestone",
                                        canSave: !GoalsFormat.trimmed(title).isEmpty, onSave: save))
            .sheet(isPresented: $showDependencies) {
                DependencyPicker(objectiveID: objectiveID, goalID: goalID, initial: dependsOnIDs) { chosen in
                    dependsOnIDs = chosen
                }
            }
            .confirmationDialog("Delete this milestone?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete milestone", role: .destructive) { deleteObjective() }
                Button("Keep", role: .cancel) {}
            }
        }
    }

    private func toggleSystem(_ id: UUID) {
        if let index = systemIDs.firstIndex(of: id) {
            systemIDs.remove(at: index)
        } else {
            systemIDs.append(id)
        }
    }

    private func save() {
        let snapshot = services.store.snapshot()
        var entity = objective ?? Objective(id: objectiveID, goalID: goalID, title: "")
        if objective == nil {
            entity.sortIndex = (snapshot.objectives(goalID: goalID).map(\.sortIndex).max() ?? -1) + 1
        }
        entity.title = GoalsFormat.trimmed(title)
        entity.estimatedDays = estimatedDays
        entity.status = status
        entity.deadlineOverridden = isOverridden
        if isOverridden { entity.deadline = deadline }
        entity.systemIDs = systemIDs
        entity.dependsOnIDs = dependsOnIDs
        Task {
            do {
                try await GoalsActions.commit(ChangeSet(upserts: [.objective(entity)]), goalID: goalID, services: services)
                dismiss()
            } catch {
                errorText = GoalsActions.saveFailed
            }
        }
    }

    private func deleteObjective() {
        guard let objective else { return }
        Task {
            do {
                try await GoalsActions.commit(ChangeSet(deletes: [EntityRef(.objective, objective.id)]), goalID: goalID,
                                              services: services)
                dismiss()
            } catch {
                errorText = GoalsActions.saveFailed
            }
        }
    }
}

#Preview {
    MilestoneEditorSheet(goalID: SampleData.goalID, objective: nil)
        .environment(AppServices.preview())
        .environment(Router())
}
