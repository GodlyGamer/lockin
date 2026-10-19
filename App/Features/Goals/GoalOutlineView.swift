import SwiftUI
import CoreKit

// MARK: - Row model

private enum GoalsOutlineKind: Equatable {
    case header, goal, principle, system, habit, blockRule, reminder, milestone, step
}

/// Stable ids for the section-header rows.
private enum GoalsOutlineHeaderID {
    static let principles = UUID()
    static let orphans = UUID()
    static let milestones = UUID()
    static let sustaining = UUID()
}

private struct GoalsOutlineRow: Identifiable {
    let id: UUID
    let kind: GoalsOutlineKind
    let depth: Int
    let title: String
    let icon: String
    var subtitle: String? = nil
    var warning: String? = nil
    var badge: String? = nil
    /// The entity this row sits under; rows with the same kind and parentKey are siblings.
    var parentKey: UUID? = nil
    var isMovable = false
    var isDone = false
    var isInactive = false
}

private enum GoalsOutlineSheet: Identifiable {
    case goal
    case principle(UUID?)
    case system(UUID?)
    case blockRule(UUID?)
    case reminder(UUID?)
    case milestone(UUID?)
    case step(UUID?)
    case dependencies(UUID)

    var id: String {
        switch self {
        case .goal: "goal"
        case .principle(let id): "principle-\(id?.uuidString ?? "new")"
        case .system(let id): "system-\(id?.uuidString ?? "new")"
        case .blockRule(let id): "blockRule-\(id?.uuidString ?? "new")"
        case .reminder(let id): "reminder-\(id?.uuidString ?? "new")"
        case .milestone(let id): "milestone-\(id?.uuidString ?? "new")"
        case .step(let id): "step-\(id?.uuidString ?? "new")"
        case .dependencies(let id): "dependencies-\(id.uuidString)"
        }
    }
}

// MARK: - View

/// The Outline (§4.8): the only place where the goal's structure is edited.
///
/// Gestures: drag (or "Reorder" in the + menu, or VoiceOver Move up / Move down) reorders inside the same parent.
/// Swipe right = Indent, swipe left = Outdent. A row's parent must be of an allowed type, so Indent moves a
/// habit / block / reminder into the previous system, a system into the previous principle and a step into the
/// previous milestone (Outdent moves it into the next one). Rows with no such neighbour offer neither.
struct GoalOutlineView: View {
    let goalID: UUID
    let scrollTarget: UUID?
    let onDone: (() -> Void)?

    @Environment(AppServices.self) private var services
    @Environment(Router.self) private var router

    @State private var sheet: GoalsOutlineSheet?
    @State private var editMode: EditMode = .inactive
    @State private var highlighted: UUID?
    @State private var tick = 0

    init(goalID: UUID, scrollTarget: UUID? = nil, onDone: (() -> Void)? = nil) {
        self.goalID = goalID
        self.scrollTarget = scrollTarget
        self.onDone = onDone
    }

    var body: some View {
        let _ = services.store.revision
        let snapshot = services.store.snapshot()

        Group {
            if let goal = snapshot.goal(goalID) {
                outline(goal: goal, snapshot: snapshot)
            } else {
                Color.clear
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                addMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    editMode = .inactive
                    onDone?()
                }
            }
        }
        .sheet(item: $sheet) { item in
            sheetContent(item)
        }
        .haptic(.outlineReorder, trigger: tick)
    }

    // MARK: Toolbar

    private var addMenu: some View {
        Menu {
            Button("First principle", systemImage: "lightbulb") { sheet = .principle(nil) }
            Button("System", systemImage: "gearshape.2") { sheet = .system(nil) }
            Button("Habit", systemImage: "checkmark.square") { router.push(.habitEditor(nil)) }
            Button("Block", systemImage: "calendar") { sheet = .blockRule(nil) }
            Button("Reminder", systemImage: "bell") { sheet = .reminder(nil) }
            Button("Milestone", systemImage: "flag") { sheet = .milestone(nil) }
            Button("Step", systemImage: "circle") { sheet = .step(nil) }
            Divider()
            Button(editMode == .active ? "Stop reordering" : "Reorder rows", systemImage: "arrow.up.arrow.down") {
                editMode = editMode == .active ? .inactive : .active
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add")
    }

    // MARK: List

    @ViewBuilder
    private func outline(goal: Goal, snapshot: StoreSnapshot) -> some View {
        let late = ScheduleEngine.backSchedule(objectives: snapshot.objectives(goalID: goalID), goal: goal,
                                               today: LocalDay.today).startsLateByDays
        let rows = makeRows(goal: goal, snapshot: snapshot, late: late)

        ScrollViewReader { proxy in
            List {
                ForEach(rows) { row in
                    outlineRow(row, rows: rows, snapshot: snapshot)
                }
                .onMove { source, destination in
                    handleMove(rows: rows, source: source, destination: destination, snapshot: snapshot)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, $editMode)
            .task(id: scrollTarget) {
                await scroll(proxy)
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) async {
        guard let target = scrollTarget else { return }
        try? await Task.sleep(for: .milliseconds(250))
        proxy.scrollTo(target, anchor: .center)
        highlighted = target
        try? await Task.sleep(for: .milliseconds(1600))
        if highlighted == target { highlighted = nil }
    }

    @ViewBuilder
    private func outlineRow(_ row: GoalsOutlineRow, rows: [GoalsOutlineRow], snapshot: StoreSnapshot) -> some View {
        if row.kind == .header {
            Text(row.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
                .textCase(.uppercase)
                .padding(.top, 12)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                .moveDisabled(true)
                .accessibilityAddTraits(.isHeader)
        } else {
            let canIndent = reparentChanges(row, direction: -1, snapshot: snapshot) != nil
            let canOutdent = reparentChanges(row, direction: 1, snapshot: snapshot) != nil
            let siblings = rows.filter { $0.kind == row.kind && $0.parentKey == row.parentKey }
            let siblingIndex = siblings.firstIndex { $0.id == row.id } ?? 0
            let canMoveUp = row.isMovable && siblingIndex > 0
            let canMoveDown = row.isMovable && siblingIndex < siblings.count - 1

            rowContent(row)
                .listRowBackground(rowBackground(highlighted: highlighted == row.id))
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 28, bottom: 0, trailing: 28))
                .moveDisabled(!row.isMovable)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if canIndent {
                        Button {
                            runReparent(row, direction: -1, snapshot: snapshot)
                        } label: {
                            Label("Indent", systemImage: "increase.indent")
                        }
                        .tint(Color.cobalt)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if canOutdent {
                        Button {
                            runReparent(row, direction: 1, snapshot: snapshot)
                        } label: {
                            Label("Outdent", systemImage: "decrease.indent")
                        }
                        .tint(Color.markMStroke)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText(row))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { open(row) }
                .accessibilityActions {
                    if canMoveUp {
                        Button("Move up") { move(row, by: -1, rows: rows, snapshot: snapshot) }
                    }
                    if canMoveDown {
                        Button("Move down") { move(row, by: 1, rows: rows, snapshot: snapshot) }
                    }
                    if canIndent {
                        Button("Indent") { runReparent(row, direction: -1, snapshot: snapshot) }
                    }
                    if canOutdent {
                        Button("Outdent") { runReparent(row, direction: 1, snapshot: snapshot) }
                    }
                    if row.kind == .milestone {
                        Button("Change dependencies") { sheet = .dependencies(row.id) }
                    }
                    Button("Edit") { open(row) }
                }
        }
    }

    private func rowBackground(highlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(highlighted
                  ? AnyShapeStyle(Color.cobalt.opacity(0.25))
                  : AnyShapeStyle(LinearGradient(colors: [Color.tileTop, Color.tileBottom], startPoint: .top, endPoint: .bottom)))
            .padding(.vertical, 2)
            .padding(.horizontal, 16)
    }

    private func rowContent(_ row: GoalsOutlineRow) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                open(row)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: row.isDone ? "checkmark.circle.fill" : row.icon)
                        .font(.callout)
                        .foregroundStyle(row.isDone ? Color.textSecondary : Color.cobaltText)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(.body)
                            .foregroundStyle(row.isDone || row.isInactive ? Color.textSecondary : Color.textPrimary)
                            .strikethrough(row.isDone)
                            .multilineTextAlignment(.leading)
                        if let subtitle = row.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(Color.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        if let warning = row.warning {
                            Text(warning)
                                .font(.footnote)
                                .foregroundStyle(Color.emberText)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let badge = row.badge {
                if row.kind == .milestone {
                    Button {
                        sheet = .dependencies(row.id)
                    } label: {
                        badgeLabel(badge, tappable: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    badgeLabel(badge, tappable: false)
                }
            }
        }
        .padding(.leading, CGFloat(row.depth) * 20 + 12)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
    }

    private func badgeLabel(_ text: String, tappable: Bool) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(tappable ? Color.cobaltText : Color.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }

    private func accessibilityText(_ row: GoalsOutlineRow) -> String {
        var parts: [String] = []
        switch row.kind {
        case .goal: parts.append("Goal")
        case .principle: parts.append("First principle")
        case .system: parts.append("System")
        case .habit: parts.append("Habit")
        case .blockRule: parts.append("Block")
        case .reminder: parts.append("Reminder")
        case .milestone: parts.append("Milestone")
        case .step: parts.append("Step")
        case .header: break
        }
        parts.append(row.title)
        if let badge = row.badge { parts.append(badge) }
        if let warning = row.warning { parts.append(warning) }
        if row.isDone { parts.append("done") }
        return parts.joined(separator: ", ")
    }

    // MARK: Row building

    private func makeRows(goal: Goal, snapshot: StoreSnapshot, late: [UUID: Int]) -> [GoalsOutlineRow] {
        var rows: [GoalsOutlineRow] = []
        let target = GoalsFormat.withUnit(goal.resultTarget, goal.resultUnit)
        rows.append(GoalsOutlineRow(id: goal.id, kind: .goal, depth: 0, title: goal.title, icon: "target",
                                    subtitle: "Goal: \(target) by \(LockInFormat.shortDayMonth(goal.deadline))"))

        let principles = snapshot.firstPrinciples(goalID: goalID)
        let principleIDs = Set(principles.map(\.id))
        let principleSystems = snapshot.systems(goalID: goalID).filter { $0.kind == .principle }
        let sustaining = snapshot.systems(goalID: goalID).filter { $0.kind == .sustaining }
        let orphans = principleSystems.filter { system in
            system.firstPrincipleID.map { !principleIDs.contains($0) } ?? true
        }

        if !principles.isEmpty {
            rows.append(header("First principles", id: GoalsOutlineHeaderID.principles))
        }
        for principle in principles {
            rows.append(GoalsOutlineRow(id: principle.id, kind: .principle, depth: 0, title: principle.title,
                                        icon: "lightbulb", subtitle: principle.why, parentKey: goalID, isMovable: true))
            for system in principleSystems where system.firstPrincipleID == principle.id {
                appendSystem(system, depth: 1, parentKey: principle.id, movable: true, snapshot: snapshot, into: &rows)
            }
        }
        if !orphans.isEmpty {
            rows.append(header("Systems without a principle", id: GoalsOutlineHeaderID.orphans))
            for system in orphans {
                appendSystem(system, depth: 0, parentKey: nil, movable: true, snapshot: snapshot, into: &rows)
            }
        }

        let objectives = snapshot.objectives(goalID: goalID)
        if !objectives.isEmpty {
            rows.append(header("Milestones", id: GoalsOutlineHeaderID.milestones))
        }
        for objective in objectives {
            rows.append(GoalsOutlineRow(id: objective.id, kind: .milestone, depth: 0, title: objective.title, icon: "flag",
                                        warning: late[objective.id].map { GoalsFormat.startsLate($0) },
                                        badge: milestoneBadge(objective, snapshot: snapshot),
                                        parentKey: goalID, isMovable: true, isDone: objective.status == .done))
            let steps = snapshot.steps.filter { $0.objectiveID == objective.id }.sorted { $0.sortIndex < $1.sortIndex }
            for step in steps {
                rows.append(GoalsOutlineRow(id: step.id, kind: .step, depth: 1, title: step.title, icon: "circle",
                                            badge: "\(step.estimatedMinutes) min", parentKey: objective.id,
                                            isMovable: true, isDone: step.done))
            }
        }

        if !sustaining.isEmpty {
            rows.append(header("Sustaining system", id: GoalsOutlineHeaderID.sustaining))
        }
        for system in sustaining {
            appendSystem(system, depth: 0, parentKey: goalID, movable: false, snapshot: snapshot, into: &rows)
        }
        return rows
    }

    private func header(_ title: String, id: UUID) -> GoalsOutlineRow {
        GoalsOutlineRow(id: id, kind: .header, depth: 0, title: title, icon: "")
    }

    private func appendSystem(_ system: GoalSystem, depth: Int, parentKey: UUID?, movable: Bool,
                              snapshot: StoreSnapshot, into rows: inout [GoalsOutlineRow]) {
        rows.append(GoalsOutlineRow(id: system.id, kind: .system, depth: depth, title: system.title, icon: "gearshape.2",
                                    subtitle: system.location, parentKey: parentKey, isMovable: movable))
        let habits = snapshot.habits.filter { $0.systemID == system.id && !$0.isArchived }.sorted { $0.sortIndex < $1.sortIndex }
        for habit in habits {
            rows.append(GoalsOutlineRow(id: habit.id, kind: .habit, depth: depth + 1, title: habit.title,
                                        icon: "checkmark.square", badge: LockInFormat.frequency(habit.frequency),
                                        parentKey: system.id, isMovable: true))
        }
        let rules = snapshot.blockRules.filter { $0.systemID == system.id }
            .sorted { ($0.weekdays.min() ?? 8, $0.startTime) < ($1.weekdays.min() ?? 8, $1.startTime) }
        for rule in rules {
            rows.append(GoalsOutlineRow(id: rule.id, kind: .blockRule, depth: depth + 1, title: rule.title, icon: "calendar",
                                        badge: GoalsFormat.weekdaysAndTime(rule.weekdays, minutes: rule.startTime),
                                        parentKey: system.id, isInactive: !rule.active))
        }
        let reminders = snapshot.reminders.filter { $0.systemID == system.id }.sorted { $0.time < $1.time }
        for reminder in reminders {
            rows.append(GoalsOutlineRow(id: reminder.id, kind: .reminder, depth: depth + 1, title: reminder.title, icon: "bell",
                                        badge: reminderBadge(reminder), parentKey: system.id, isInactive: !reminder.active))
        }
    }

    private func reminderBadge(_ reminder: PlanReminder) -> String {
        if let date = reminder.date {
            return "\(LockInFormat.shortDayMonth(date)) \(LockInFormat.time(reminder.time))"
        }
        if !reminder.weekdays.isEmpty {
            return GoalsFormat.weekdaysAndTime(reminder.weekdays, minutes: reminder.time)
        }
        return LockInFormat.time(reminder.time)
    }

    private func milestoneBadge(_ objective: Objective, snapshot: StoreSnapshot) -> String {
        if objective.dependsOnIDs.count == 1, let first = objective.dependsOnIDs.first,
           let dependency = snapshot.objective(first) {
            return "after \(dependency.title)"
        }
        if objective.dependsOnIDs.count > 1 {
            return "after \(objective.dependsOnIDs.count) milestones"
        }
        if !objective.systemIDs.isEmpty {
            let count = objective.systemIDs.count
            return "after \(count) system\(count == 1 ? "" : "s")"
        }
        return "no dependency"
    }

    // MARK: Opening editors

    private func open(_ row: GoalsOutlineRow) {
        switch row.kind {
        case .header: break
        case .goal: sheet = .goal
        case .principle: sheet = .principle(row.id)
        case .system: sheet = .system(row.id)
        case .habit: router.push(.habitEditor(row.id))
        case .blockRule: sheet = .blockRule(row.id)
        case .reminder: sheet = .reminder(row.id)
        case .milestone: sheet = .milestone(row.id)
        case .step: sheet = .step(row.id)
        }
    }

    @ViewBuilder
    private func sheetContent(_ item: GoalsOutlineSheet) -> some View {
        let snapshot = services.store.snapshot()
        switch item {
        case .goal:
            if let goal = snapshot.goal(goalID) {
                GoalEditorSheet(goal: goal)
            }
        case .principle(let id):
            PrincipleEditorSheet(goalID: goalID, principle: id.flatMap { pid in snapshot.firstPrinciples.first { $0.id == pid } })
        case .system(let id):
            SystemEditorSheet(goalID: goalID, system: id.flatMap { snapshot.system($0) }, defaultPrincipleID: nil)
        case .blockRule(let id):
            BlockRuleEditorSheet(goalID: goalID, rule: id.flatMap { snapshot.blockRule($0) }, defaultSystemID: nil)
        case .reminder(let id):
            ReminderEditorSheet(goalID: goalID, reminder: id.flatMap { rid in snapshot.reminders.first { $0.id == rid } },
                                defaultSystemID: nil)
        case .milestone(let id):
            MilestoneEditorSheet(goalID: goalID, objective: id.flatMap { snapshot.objective($0) })
        case .step(let id):
            StepEditorSheet(goalID: goalID, step: id.flatMap { sid in snapshot.steps.first { $0.id == sid } },
                            defaultObjectiveID: nil)
        case .dependencies(let id):
            if let objective = snapshot.objective(id) {
                DependencyPicker(objectiveID: id, goalID: goalID, initial: objective.dependsOnIDs) { chosen in
                    saveDependencies(objective, chosen)
                }
            }
        }
    }

    private func saveDependencies(_ objective: Objective, _ chosen: [UUID]) {
        var updated = objective
        updated.dependsOnIDs = chosen
        run(ChangeSet(upserts: [.objective(updated)]), recomputeDeadlines: true)
    }

    // MARK: Reordering

    private func handleMove(rows: [GoalsOutlineRow], source: IndexSet, destination: Int, snapshot: StoreSnapshot) {
        guard let from = source.first, rows.indices.contains(from) else { return }
        let moved = rows[from]
        guard moved.isMovable else { return }
        let siblings = rows.enumerated().filter { $0.element.kind == moved.kind && $0.element.parentKey == moved.parentKey }
        let before = siblings.filter { $0.offset < destination && $0.element.id != moved.id }.count
        var order = siblings.map { $0.element.id }.filter { $0 != moved.id }
        order.insert(moved.id, at: min(before, order.count))
        applyOrder(kind: moved.kind, orderedIDs: order, snapshot: snapshot)
    }

    private func move(_ row: GoalsOutlineRow, by delta: Int, rows: [GoalsOutlineRow], snapshot: StoreSnapshot) {
        var order = rows.filter { $0.kind == row.kind && $0.parentKey == row.parentKey }.map(\.id)
        guard let index = order.firstIndex(of: row.id) else { return }
        let target = index + delta
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        applyOrder(kind: row.kind, orderedIDs: order, snapshot: snapshot)
    }

    private func applyOrder(kind: GoalsOutlineKind, orderedIDs: [UUID], snapshot: StoreSnapshot) {
        var upserts: [AnyEntity] = []
        switch kind {
        case .principle:
            let items = orderedIDs.compactMap { id in snapshot.firstPrinciples.first { $0.id == id } }
            upserts = GoalsOrdering.reassign(items, index: \.sortIndex, wrap: { AnyEntity.firstPrinciple($0) })
        case .system:
            let items = orderedIDs.compactMap { id in snapshot.systems.first { $0.id == id } }
            upserts = GoalsOrdering.reassign(items, index: \.sortIndex, wrap: { AnyEntity.system($0) })
        case .habit:
            let items = orderedIDs.compactMap { id in snapshot.habits.first { $0.id == id } }
            upserts = GoalsOrdering.reassign(items, index: \.sortIndex, wrap: { AnyEntity.habit($0) })
        case .milestone:
            let items = orderedIDs.compactMap { id in snapshot.objectives.first { $0.id == id } }
            upserts = GoalsOrdering.reassign(items, index: \.sortIndex, wrap: { AnyEntity.objective($0) })
        case .step:
            let items = orderedIDs.compactMap { id in snapshot.steps.first { $0.id == id } }
            upserts = GoalsOrdering.reassign(items, index: \.sortIndex, wrap: { AnyEntity.step($0) })
        case .header, .goal, .blockRule, .reminder:
            break
        }
        guard !upserts.isEmpty else { return }
        run(ChangeSet(upserts: upserts), recomputeDeadlines: false)
    }

    // MARK: Indent / outdent

    /// The ids of the systems in outline order (principle systems under their principles, orphans, then sustaining).
    private func systemOrder(snapshot: StoreSnapshot) -> [UUID] {
        let principles = snapshot.firstPrinciples(goalID: goalID)
        let principleIDs = Set(principles.map(\.id))
        let all = snapshot.systems(goalID: goalID)
        var order: [UUID] = []
        for principle in principles {
            order += all.filter { $0.kind == .principle && $0.firstPrincipleID == principle.id }.map(\.id)
        }
        order += all.filter { system in
            system.kind == .principle && (system.firstPrincipleID.map { !principleIDs.contains($0) } ?? true)
        }.map(\.id)
        order += all.filter { $0.kind == .sustaining }.map(\.id)
        return order
    }

    /// The neighbour of `current` in `order`: `direction` -1 = previous, +1 = next. A nil `current` counts as "before the first".
    private func neighbour(of current: UUID?, in order: [UUID], direction: Int) -> UUID? {
        let index: Int
        if let current {
            guard let found = order.firstIndex(of: current) else { return nil }
            index = found
        } else {
            index = -1
        }
        let target = index + direction
        return order.indices.contains(target) ? order[target] : nil
    }

    /// The changes for Indent (`direction` -1: appended to the previous parent) or Outdent (`direction` +1: put first in
    /// the next parent). Nil when the row has no neighbouring parent of an allowed type.
    private func reparentChanges(_ row: GoalsOutlineRow, direction: Int, snapshot: StoreSnapshot) -> ChangeSet? {
        switch row.kind {
        case .habit:
            guard let habit = snapshot.habit(row.id),
                  let target = neighbour(of: habit.systemID, in: systemOrder(snapshot: snapshot), direction: direction)
            else { return nil }
            let others = snapshot.habits.filter { $0.systemID == target && !$0.isArchived && $0.id != habit.id }.map(\.sortIndex)
            var updated = habit
            updated.systemID = target
            updated.goalID = goalID
            updated.sortIndex = direction < 0 ? (others.max() ?? habit.sortIndex) + 1 : (others.min() ?? habit.sortIndex) - 1
            return ChangeSet(upserts: [.habit(updated)])

        case .blockRule:
            guard let rule = snapshot.blockRule(row.id),
                  let target = neighbour(of: rule.systemID, in: systemOrder(snapshot: snapshot), direction: direction)
            else { return nil }
            var updated = rule
            updated.systemID = target
            var upserts: [AnyEntity] = [.blockRule(updated)]
            for block in snapshot.blocks where block.ruleID == rule.id {
                var copy = block
                copy.systemID = target
                upserts.append(.block(copy))
            }
            return ChangeSet(upserts: upserts)

        case .reminder:
            guard let reminder = snapshot.reminders.first(where: { $0.id == row.id }),
                  let target = neighbour(of: reminder.systemID, in: systemOrder(snapshot: snapshot), direction: direction)
            else { return nil }
            var updated = reminder
            updated.systemID = target
            return ChangeSet(upserts: [.reminder(updated)])

        case .system:
            guard let system = snapshot.system(row.id), system.kind == .principle else { return nil }
            let order = snapshot.firstPrinciples(goalID: goalID).map(\.id)
            let current = system.firstPrincipleID.flatMap { order.contains($0) ? $0 : nil }
            guard let target = neighbour(of: current, in: order, direction: direction) else { return nil }
            let others = snapshot.systems.filter { $0.firstPrincipleID == target && $0.id != system.id }.map(\.sortIndex)
            var updated = system
            updated.firstPrincipleID = target
            updated.sortIndex = direction < 0 ? (others.max() ?? system.sortIndex) + 1 : (others.min() ?? system.sortIndex) - 1
            return ChangeSet(upserts: [.system(updated)])

        case .step:
            guard let step = snapshot.steps.first(where: { $0.id == row.id }) else { return nil }
            let order = snapshot.objectives(goalID: goalID).map(\.id)
            guard let target = neighbour(of: step.objectiveID, in: order, direction: direction) else { return nil }
            let others = snapshot.steps.filter { $0.objectiveID == target && $0.id != step.id }.map(\.sortIndex)
            var updated = step
            updated.objectiveID = target
            updated.sortIndex = direction < 0 ? (others.max() ?? step.sortIndex) + 1 : (others.min() ?? step.sortIndex) - 1
            return ChangeSet(upserts: [.step(updated)])

        case .header, .goal, .principle, .milestone:
            return nil
        }
    }

    private func runReparent(_ row: GoalsOutlineRow, direction: Int, snapshot: StoreSnapshot) {
        guard let changes = reparentChanges(row, direction: direction, snapshot: snapshot) else { return }
        run(changes, recomputeDeadlines: false)
    }

    private func run(_ changes: ChangeSet, recomputeDeadlines: Bool) {
        Task {
            do {
                try await GoalsActions.commit(changes, goalID: recomputeDeadlines ? goalID : nil, services: services)
                tick += 1
            } catch {
                router.toast = GoalsActions.saveFailed
            }
        }
    }
}

#Preview {
    NavigationStack { GoalOutlineView(goalID: SampleData.goalID) }
        .environment(AppServices.preview())
        .environment(Router())
}
