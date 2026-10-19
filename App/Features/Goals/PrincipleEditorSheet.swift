import SwiftUI
import CoreKit

/// Add or edit a first principle (§3.2).
struct PrincipleEditorSheet: View {
    let goalID: UUID
    let principle: FirstPrinciple?

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var why: String
    @State private var errorText: String?
    @State private var confirmDelete = false

    init(goalID: UUID, principle: FirstPrinciple?) {
        self.goalID = goalID
        self.principle = principle
        _title = State(initialValue: principle?.title ?? "")
        _why = State(initialValue: principle?.why ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("First principle") {
                    TextField("Eat in a calorie deficit", text: $title)
                    TextField("Why it holds", text: $why, axis: .vertical)
                        .lineLimit(1...5)
                }
                if let errorText {
                    Section { GoalsFormMessage(text: errorText) }
                }
                if principle != nil {
                    Section {
                        Button("Delete principle", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Its systems stay, but lose this principle.")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .modifier(GoalsEditorChrome(title: principle == nil ? "New principle" : "Principle",
                                        canSave: !GoalsFormat.trimmed(title).isEmpty, onSave: save))
            .confirmationDialog("Delete this principle?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete principle", role: .destructive) { deletePrinciple() }
                Button("Keep", role: .cancel) {}
            }
        }
    }

    private func save() {
        let snapshot = services.store.snapshot()
        var entity = principle ?? FirstPrinciple(goalID: goalID, title: "")
        if principle == nil {
            entity.sortIndex = (snapshot.firstPrinciples(goalID: goalID).map(\.sortIndex).max() ?? -1) + 1
        }
        entity.title = GoalsFormat.trimmed(title)
        entity.why = GoalsFormat.trimmed(why)
        Task {
            do {
                try await GoalsActions.commit(ChangeSet(upserts: [.firstPrinciple(entity)]), services: services)
                dismiss()
            } catch {
                errorText = GoalsActions.saveFailed
            }
        }
    }

    private func deletePrinciple() {
        guard let principle else { return }
        Task {
            do {
                try await GoalsActions.commit(ChangeSet(deletes: [EntityRef(.firstPrinciple, principle.id)]), services: services)
                dismiss()
            } catch {
                errorText = GoalsActions.saveFailed
            }
        }
    }
}

#Preview {
    PrincipleEditorSheet(goalID: SampleData.goalID, principle: nil)
        .environment(AppServices.preview())
        .environment(Router())
}
