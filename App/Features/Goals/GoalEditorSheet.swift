import SwiftUI
import CoreKit

/// Edits the goal itself: title, outcome, deadline, buffer, result fields, status (§7.5).
struct GoalEditorSheet: View {
    let goal: Goal

    @Environment(AppServices.self) private var services
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var outcome: String
    @State private var deadline: LocalDay
    @State private var bufferDays: Int
    @State private var resultName: String
    @State private var resultUnit: String
    @State private var resultStart: Double
    @State private var resultTarget: Double
    @State private var direction: ResultDirection
    @State private var status: GoalStatus
    @State private var errorText: String?
    @State private var confirmDelete = false

    init(goal: Goal) {
        self.goal = goal
        _title = State(initialValue: goal.title)
        _outcome = State(initialValue: goal.outcome)
        _deadline = State(initialValue: goal.deadline)
        _bufferDays = State(initialValue: goal.bufferDays)
        _resultName = State(initialValue: goal.resultName)
        _resultUnit = State(initialValue: goal.resultUnit)
        _resultStart = State(initialValue: goal.resultStart)
        _resultTarget = State(initialValue: goal.resultTarget)
        _direction = State(initialValue: goal.resultDirection)
        _status = State(initialValue: goal.status)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("What do you want?", text: $title)
                    TextField("What success looks like", text: $outcome, axis: .vertical)
                        .lineLimit(1...4)
                    GoalsDayPicker("Deadline", day: $deadline)
                    Stepper(value: $bufferDays, in: 0...60) {
                        Text("Buffer: \(bufferDays) days")
                    }
                }
                Section("Result") {
                    TextField("Result name", text: $resultName)
                    TextField("Unit", text: $resultUnit)
                    LabeledContent("Start") {
                        GoalsNumberField("0", value: $resultStart)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Target") {
                        GoalsNumberField("0", value: $resultTarget)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Direction", selection: $direction) {
                        Text("Down").tag(ResultDirection.down)
                        Text("Up").tag(ResultDirection.up)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach(GoalStatus.allCases, id: \.self) { item in
                            Text(GoalsFormat.goalStatus(item)).tag(item)
                        }
                    }
                }
                if let errorText {
                    Section { GoalsFormMessage(text: errorText) }
                }
                Section {
                    Button("Delete goal", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("Deletes its principles, systems, milestones and reviews. Habits stay as standalone habits.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .modifier(GoalsEditorChrome(title: "Goal", canSave: !GoalsFormat.trimmed(title).isEmpty, onSave: save))
            .onChange(of: resultTarget) { _, newTarget in
                direction = newTarget < resultStart ? .down : .up
            }
            .onChange(of: resultStart) { _, newStart in
                direction = resultTarget < newStart ? .down : .up
            }
            .confirmationDialog("Delete this goal?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete goal", role: .destructive) { deleteGoal() }
                Button("Keep", role: .cancel) {}
            }
        }
    }

    private func save() {
        var updated = goal
        updated.title = GoalsFormat.trimmed(title)
        updated.outcome = GoalsFormat.trimmed(outcome)
        updated.deadline = deadline
        updated.bufferDays = bufferDays
        updated.resultName = GoalsFormat.trimmed(resultName)
        updated.resultUnit = GoalsFormat.trimmed(resultUnit)
        updated.resultStart = resultStart
        updated.resultTarget = resultTarget
        updated.resultDirection = direction
        updated.status = status
        let statusChanged = status != goal.status
        Task {
            do {
                try await GoalsActions.commit(ChangeSet(upserts: [.goal(updated)]), goalID: goal.id,
                                              then: statusChanged ? .reschedule : .none, services: services)
                dismiss()
            } catch {
                errorText = GoalsActions.saveFailed
            }
        }
    }

    private func deleteGoal() {
        Task {
            do {
                try await GoalsActions.commit(ChangeSet(deletes: [EntityRef(.goal, goal.id)]), then: .calendarSync,
                                              services: services)
                dismiss()
            } catch {
                errorText = GoalsActions.saveFailed
            }
        }
    }
}

#Preview {
    GoalEditorSheet(goal: SampleData.bodyFatGoal().goals[0])
        .environment(AppServices.preview())
        .environment(Router())
}
