import SwiftUI
import CoreKit

/// Add or edit a system (§3.3): title, location, kind and the principle it serves.
struct SystemEditorSheet: View {
    let goalID: UUID
    let system: GoalSystem?

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var location: String
    @State private var kind: SystemKind
    @State private var principleID: UUID?
    @State private var errorText: String?
    @State private var confirmDelete = false

    init(goalID: UUID, system: GoalSystem?, defaultPrincipleID: UUID?) {
        self.goalID = goalID
        self.system = system
        _title = State(initialValue: system?.title ?? "")
        _location = State(initialValue: system?.location ?? "")
        _kind = State(initialValue: system?.kind ?? .principle)
        _principleID = State(initialValue: system?.firstPrincipleID ?? defaultPrincipleID)
    }

    var body: some View {
        let snapshot = services.store.snapshot()
        let principles = snapshot.firstPrinciples(goalID: goalID)
        let otherSustaining = snapshot.systems(goalID: goalID).contains { $0.kind == .sustaining && $0.id != system?.id }

        NavigationStack {
            Form {
                Section("System") {
                    TextField("Lifting M/W/F", text: $title)
                    TextField("Location (optional)", text: $location)
                }
                Section {
                    Picker("Type", selection: $kind) {
                        Text("Principle system").tag(SystemKind.principle)
                        Text("Sustaining system").tag(SystemKind.sustaining)
                    }
                    .pickerStyle(.segmented)
                    .disabled(otherSustaining && kind == .principle)
                } footer: {
                    Text(otherSustaining
                         ? "This goal already has its one sustaining system."
                         : "A goal needs exactly one sustaining system.")
                }
                if kind == .principle {
                    Section("Serves") {
                        Picker("First principle", selection: $principleID) {
                            Text("None").tag(UUID?.none)
                            ForEach(principles) { principle in
                                Text(principle.title).tag(Optional(principle.id))
                            }
                        }
                    }
                }
                if let errorText {
                    Section { GoalsFormMessage(text: errorText) }
                }
                if system != nil {
                    Section {
                        Button("Delete system", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Its blocks and reminders are deleted. Its habits stay as standalone habits.")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .modifier(GoalsEditorChrome(title: system == nil ? "New system" : "System",
                                        canSave: !GoalsFormat.trimmed(title).isEmpty, onSave: save))
            .confirmationDialog("Delete this system?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete system", role: .destructive) { deleteSystem() }
                Button("Keep", role: .cancel) {}
            }
        }
    }

    private func save() {
        let snapshot = services.store.snapshot()
        var entity = system ?? GoalSystem(goalID: goalID, title: "")
        if system == nil {
            entity.sortIndex = (snapshot.systems(goalID: goalID).map(\.sortIndex).max() ?? -1) + 1
        }
        entity.title = GoalsFormat.trimmed(title)
        let place = GoalsFormat.trimmed(location)
        entity.location = place.isEmpty ? nil : place
        entity.kind = kind
        entity.firstPrincipleID = kind == .principle ? principleID : nil
        Task {
            do {
                try await GoalsActions.commit(ChangeSet(upserts: [.system(entity)]), services: services)
                dismiss()
            } catch {
                errorText = GoalsActions.saveFailed
            }
        }
    }

    private func deleteSystem() {
        guard let system else { return }
        Task {
            do {
                try await GoalsActions.commit(ChangeSet(deletes: [EntityRef(.system, system.id)]), then: .calendarSync,
                                              services: services)
                dismiss()
            } catch {
                errorText = GoalsActions.saveFailed
            }
        }
    }
}

#Preview {
    SystemEditorSheet(goalID: SampleData.goalID, system: nil, defaultPrincipleID: nil)
        .environment(AppServices.preview())
        .environment(Router())
}
