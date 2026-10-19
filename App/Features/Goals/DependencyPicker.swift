import SwiftUI
import CoreKit

/// Choose which other milestones an objective waits for (§4.8). A choice that would create a loop is disabled with
/// the reason "Would create a loop". Nothing is saved until Done; `onSave` receives the chosen ids.
struct DependencyPicker: View {
    let objectiveID: UUID
    let goalID: UUID
    let onSave: ([UUID]) -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var selection: [UUID]

    init(objectiveID: UUID, goalID: UUID, initial: [UUID], onSave: @escaping ([UUID]) -> Void) {
        self.objectiveID = objectiveID
        self.goalID = goalID
        self.onSave = onSave
        _selection = State(initialValue: initial)
    }

    var body: some View {
        let all = services.store.snapshot().objectives(goalID: goalID)
        let candidates = all.filter { $0.id != objectiveID }

        NavigationStack {
            List {
                if candidates.isEmpty {
                    Text("There are no other milestones yet.")
                        .foregroundStyle(Color.textSecondary)
                }
                ForEach(candidates) { objective in
                    let isSelected = selection.contains(objective.id)
                    let blocked = !isSelected
                        && ScheduleEngine.wouldCreateCycle(objectives: all, from: objectiveID, to: objective.id)
                    Button {
                        toggle(objective.id)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(objective.title)
                                    .foregroundStyle(Color.textPrimary)
                                if blocked {
                                    Text("Would create a loop")
                                        .font(.footnote)
                                        .foregroundStyle(Color.emberText)
                                }
                            }
                            Spacer(minLength: 0)
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.cobaltText)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(blocked)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityHint(blocked ? "Would create a loop" : "")
                }
            }
            .navigationTitle("Depends on")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(selection)
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else {
            selection.append(id)
        }
    }
}

#Preview {
    DependencyPicker(objectiveID: SampleData.objective84ID, goalID: SampleData.goalID, initial: []) { _ in }
        .environment(AppServices.preview())
        .environment(Router())
}
