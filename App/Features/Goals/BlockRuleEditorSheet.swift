import SwiftUI
import CoreKit

/// Add or edit a recurring block template (§3.9). Saving moves the rule's future blocks to match, then syncs the calendar.
struct BlockRuleEditorSheet: View {
    let goalID: UUID
    let rule: BlockRule?

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var systemID: UUID?
    @State private var duration: Int
    @State private var weekdays: [Int]
    @State private var startTime: Int
    @State private var windowStart: Int
    @State private var windowEnd: Int
    @State private var isPhysical: Bool
    @State private var nudge: Bool
    @State private var active: Bool
    @State private var errorText: String?
    @State private var confirmDelete = false

    init(goalID: UUID, rule: BlockRule?, defaultSystemID: UUID?) {
        self.goalID = goalID
        self.rule = rule
        _title = State(initialValue: rule?.title ?? "")
        _systemID = State(initialValue: rule?.systemID ?? defaultSystemID)
        _duration = State(initialValue: rule?.durationMinutes ?? 60)
        _weekdays = State(initialValue: rule?.weekdays ?? [7])
        _startTime = State(initialValue: rule?.startTime ?? 1020)
        _windowStart = State(initialValue: rule?.windowStart ?? 960)
        _windowEnd = State(initialValue: rule?.windowEnd ?? 1200)
        _isPhysical = State(initialValue: rule?.isPhysical ?? false)
        _nudge = State(initialValue: rule?.nudge ?? false)
        _active = State(initialValue: rule?.active ?? true)
    }

    private var validationMessage: String? {
        if GoalsFormat.trimmed(title).isEmpty { return "Add a title." }
        if systemID == nil { return "Pick a system first." }
        if weekdays.isEmpty { return "Pick at least one day." }
        if windowStart > startTime { return "The window has to start at or before the start time." }
        if windowEnd < startTime + duration { return "The window has to end after the block finishes." }
        return nil
    }

    var body: some View {
        let snapshot = services.store.snapshot()
        let systems = snapshot.systems(goalID: goalID)
        let saturdayOff = snapshot.settings.saturdayOff

        NavigationStack {
            Form {
                Section("Block") {
                    TextField("Meal prep", text: $title)
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
                    Stepper(value: $duration, in: 15...480, step: 15) {
                        Text("Length: \(duration) min")
                    }
                }
                Section("Days") {
                    GoalsWeekdayChips(days: $weekdays)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    if saturdayOff && weekdays.contains(6) && !isPhysical {
                        Text("Saturdays are off for goal work. Make this block physical or it won't be scheduled.")
                            .font(.footnote)
                            .foregroundStyle(Color.emberText)
                    }
                }
                Section {
                    GoalsTimePicker("Start", minutes: $startTime)
                    GoalsTimePicker("Earliest", minutes: $windowStart)
                    GoalsTimePicker("Latest finish", minutes: $windowEnd)
                } header: {
                    Text("Time")
                } footer: {
                    Text("The window is how far the block may be moved to avoid a clash.")
                }
                Section {
                    Toggle("Physical", isOn: $isPhysical)
                    Toggle("Nudge 10 min before", isOn: $nudge)
                    Toggle("Active", isOn: $active)
                }
                if let message = validationMessage {
                    Section { GoalsFormMessage(text: message) }
                }
                if let errorText {
                    Section { GoalsFormMessage(text: errorText) }
                }
                if rule != nil {
                    Section {
                        Button("Delete block", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Its future blocks are removed. Past blocks stay.")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .modifier(GoalsEditorChrome(title: rule == nil ? "New block" : "Block",
                                        canSave: validationMessage == nil, onSave: save))
            .confirmationDialog("Delete this block?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete block", role: .destructive) { deleteRule() }
                Button("Keep", role: .cancel) {}
            }
        }
    }

    private func save() {
        guard let systemID else { return }
        let now = Date()
        let snapshot = services.store.snapshot()
        var entity = rule ?? BlockRule(systemID: systemID, title: "", weekdays: weekdays, startTime: startTime)
        entity.systemID = systemID
        entity.title = GoalsFormat.trimmed(title)
        entity.durationMinutes = duration
        entity.weekdays = weekdays.sorted()
        entity.startTime = startTime
        entity.windowStart = windowStart
        entity.windowEnd = windowEnd
        entity.isPhysical = isPhysical
        entity.nudge = nudge
        entity.active = active

        var upserts: [AnyEntity] = [.blockRule(entity)]
        if let old = rule {
            // Bring the rule's future blocks along (blocks the user moved by hand keep their time).
            for block in snapshot.blocks where block.ruleID == old.id && block.start >= now
                && (block.status == .scheduled || block.status == .clash) {
                var copy = block
                if !entity.active || !entity.weekdays.contains(block.day.weekday) {
                    copy.status = .cancelled
                } else {
                    copy.title = entity.title
                    copy.systemID = entity.systemID
                    copy.isPhysical = entity.isPhysical
                    copy.nudge = entity.nudge
                    if TimeOfDay.minutes(of: block.start) == old.startTime {
                        copy.start = block.day.date(minutes: entity.startTime)
                        copy.end = copy.start.addingTimeInterval(TimeInterval(entity.durationMinutes * 60))
                        copy.status = .scheduled
                        copy.suggestedStart = nil
                    }
                }
                upserts.append(.block(copy))
            }
        }
        Task {
            do {
                try await GoalsActions.commit(ChangeSet(upserts: upserts), then: .calendarSync, services: services)
                dismiss()
            } catch {
                errorText = GoalsActions.saveFailed
            }
        }
    }

    private func deleteRule() {
        guard let rule else { return }
        Task {
            do {
                try await GoalsActions.commit(ChangeSet(deletes: [EntityRef(.blockRule, rule.id)]), then: .calendarSync,
                                              services: services)
                dismiss()
            } catch {
                errorText = GoalsActions.saveFailed
            }
        }
    }
}

#Preview {
    BlockRuleEditorSheet(goalID: SampleData.goalID, rule: nil, defaultSystemID: SampleData.mealsSystemID)
        .environment(AppServices.preview())
        .environment(Router())
}
