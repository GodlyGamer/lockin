import SwiftUI
import CoreKit

/// DESIGN.md §7.10. A tab root: the shell supplies the NavigationStack.
struct WeekTabView: View {
    @Environment(AppServices.self) private var services
    @Environment(Router.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var glassNamespace

    /// nil = the default week for today.
    @State private var shownWeek: Week?
    /// nil = the first goal.
    @State private var expandedGoalID: UUID?
    @State private var drafts = WeekDraftStore()
    @State private var isSending = false
    @State private var isFinishing = false
    @State private var finishTick = 0

    var body: some View {
        let _ = services.store.revision
        let snapshot = services.store.snapshot()
        let now = Date()
        let today = LocalDay(now)
        let currentWeek = Week(containing: today)
        let goals = snapshot.sortedGoals.filter { $0.status == .active }
        let defaultWeek = WeekRules.defaultWeek(snapshot: snapshot, goals: goals, today: today, currentWeek: currentWeek)
        let week = shownWeek ?? defaultWeek
        let earliest = WeekRules.earliestWeek(snapshot: snapshot, currentWeek: currentWeek)
        let mode = WeekRules.mode(for: week, currentWeek: currentWeek)
        let expandedID: UUID? = goals.contains(where: { $0.id == expandedGoalID }) ? expandedGoalID : goals.first?.id
        let showCluster = mode == .reviewable && !goals.isEmpty
        NightCanvas {
            Group {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header(week: week, mode: mode, goals: goals, snapshot: snapshot)
                        if goals.isEmpty {
                            Text("No goals to review yet.")
                                .font(.body)
                                .foregroundStyle(Color.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 24)
                        } else {
                            ForEach(goals, id: \.id) { goal in
                                goalSection(goal: goal, snapshot: snapshot, week: week, currentWeek: currentWeek,
                                            mode: mode, expandedID: expandedID, now: now)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) {
                    if showCluster, let expandedID {
                        actionCluster(goalID: expandedID, goals: goals, week: week)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    stepWeek(from: week, by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(week.start <= earliest.start)
                .accessibilityLabel("Previous week")
                Button {
                    stepWeek(from: week, by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(week.start >= currentWeek.start)
                .accessibilityLabel("Next week")
            }
        }
        .sensoryFeedback(.success, trigger: finishTick)
        .onDisappear { saveEditedDrafts() }
    }

    // MARK: - Layout pieces

    private func header(week: Week, mode: WeekTileMode, goals: [Goal], snapshot: StoreSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TitleText("Week")
                .accessibilityAddTraits(.isHeader)
            Text(WeekRules.rangeText(week))
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            if !goals.isEmpty {
                Text(caption(mode: mode, week: week, goals: goals, snapshot: snapshot))
                    .font(.footnote)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    private func caption(mode: WeekTileMode, week: Week, goals: [Goal], snapshot: StoreSnapshot) -> String {
        switch mode {
        case .live:
            return "This week so far. Reviews open on Monday."
        case .past:
            return "Read-only history."
        case .reviewable:
            let allFinished = goals.allSatisfy { snapshot.weekReview(goalID: $0.id, week: week)?.finishedAt != nil }
            return allFinished ? "Check-in saved. You can still edit and Finish again."
                               : "Last week. Add your result, then tap Finish."
        }
    }

    @ViewBuilder
    private func goalSection(goal: Goal, snapshot: StoreSnapshot, week: Week, currentWeek: Week, mode: WeekTileMode,
                             expandedID: UUID?, now: Date) -> some View {
        let model = WeekModelBuilder.build(goal: goal, snapshot: snapshot, week: week, currentWeek: currentWeek, now: now)
        if goal.id == expandedID {
            WeekGoalTile(model: model, mode: mode, draft: mode == .reviewable ? draft(for: goal, snapshot: snapshot, week: week) : nil)
        } else {
            WeekCollapsedRow(model: model) {
                expandedGoalID = goal.id
            }
        }
    }

    private func draft(for goal: Goal, snapshot: StoreSnapshot, week: Week) -> WeekDraft {
        drafts.draft(for: goal.id, week: week) {
            WeekModelBuilder.defaultValues(goal: goal, snapshot: snapshot, week: week)
        }
    }

    private func actionCluster(goalID: UUID, goals: [Goal], week: Week) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 24))
        return GlassEffectContainer(spacing: 24) {
            layout {
                Button {
                    sendToClaude(goalID: goalID, week: week)
                } label: {
                    Label("Send to Claude", systemImage: "paperplane")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.glass)
                .glassEffectID("week.send", in: glassNamespace)
                .disabled(isSending || isFinishing)

                Button {
                    finish(goals: goals, week: week)
                } label: {
                    Label("Finish", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.glass)
                .glassEffectID("week.finish", in: glassNamespace)
                .disabled(isSending || isFinishing)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Actions

    private func stepWeek(from week: Week, by delta: Int) {
        saveEditedDrafts()
        drafts.reset()
        shownWeek = delta < 0 ? week.previous : week.next
    }

    /// Persists what the user typed into open reviews so nothing is lost when they leave or step to another week.
    private func saveEditedDrafts() {
        guard let draftWeek = drafts.week else { return }
        let edited = drafts.edited
        guard !edited.isEmpty else { return }
        let snapshot = services.store.snapshot()
        var upserts: [AnyEntity] = []
        for item in edited where snapshot.goal(item.goalID) != nil {
            let review = WeekModelBuilder.review(goalID: item.goalID, week: draftWeek,
                                                 existing: snapshot.weekReview(goalID: item.goalID, week: draftWeek),
                                                 values: item.draft.values, finishedAt: nil)
            upserts.append(.weekReview(review))
        }
        guard !upserts.isEmpty else { return }
        do {
            try services.store.apply(ChangeSet(upserts: upserts))
            for item in edited { item.draft.commit() }
        } catch {
            router.toast = "Couldn't save. Try again."
        }
    }

    /// "Send to Claude": save the goal's review so the prompt carries it, copy the prompt, open Claude, then Import.
    private func sendToClaude(goalID: UUID, week: Week) {
        guard !isSending, !isFinishing else { return }
        isSending = true
        let services = self.services
        let router = self.router
        let snapshot = services.store.snapshot()
        guard let goal = snapshot.goal(goalID) else {
            isSending = false
            return
        }
        let current = draft(for: goal, snapshot: snapshot, week: week)
        let review = WeekModelBuilder.review(goalID: goalID, week: week,
                                             existing: snapshot.weekReview(goalID: goalID, week: week),
                                             values: current.values, finishedAt: nil)
        do {
            try services.store.apply(ChangeSet(upserts: [.weekReview(review)]))
            current.commit()
        } catch {
            router.toast = "Couldn't save. Try again."
            isSending = false
            return
        }
        Task {
            let fresh = services.store.snapshot()
            let prompt = PromptBuilder.checkInPrompt(goalID: goalID, snapshot: fresh, week: week)
            await ClaudeHandoff.send(prompt, router: router)
            router.sheet = .importPlan(goalID)
            isSending = false
        }
    }

    /// "Finish": save every goal's review with `finishedAt`, back up, reschedule, toast.
    private func finish(goals: [Goal], week: Week) {
        guard !isSending, !isFinishing else { return }
        isFinishing = true
        let services = self.services
        let router = self.router
        let snapshot = services.store.snapshot()
        let finishedAt = Date()
        var upserts: [AnyEntity] = []
        for goal in goals {
            let current = draft(for: goal, snapshot: snapshot, week: week)
            let review = WeekModelBuilder.review(goalID: goal.id, week: week,
                                                 existing: snapshot.weekReview(goalID: goal.id, week: week),
                                                 values: current.values, finishedAt: finishedAt)
            upserts.append(.weekReview(review))
            var updatedGoal = goal
            updatedGoal.bottleneckHabitID = current.bottleneckID
            if updatedGoal != goal {
                upserts.append(.goal(updatedGoal))
            }
        }
        do {
            try services.store.apply(ChangeSet(upserts: upserts))
        } catch {
            router.toast = "Couldn't save. Try again."
            isFinishing = false
            return
        }
        drafts.reset()
        shownWeek = week
        finishTick += 1
        Task {
            var message = "Week saved"
            if services.backup.folderName == nil {
                message += ". Backup skipped. Choose a folder in Settings."
            } else {
                do {
                    _ = try services.backup.backUpNow()
                } catch {
                    message += ". Backup failed."
                }
            }
            await services.notifications.reschedule()
            router.toast = message
            isFinishing = false
        }
    }
}

#Preview {
    NavigationStack { WeekTabView() }
        .environment(AppServices.preview())
        .environment(Router())
}
