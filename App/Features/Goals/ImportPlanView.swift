import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CoreKit

private struct GoalsImportReview {
    var result: ImportResult
    var clashLines: [String]
    var feasibilityMessage: String?
}

private enum GoalsImportStage {
    case empty
    case parsing
    case failed([PlanIssue])
    case review(GoalsImportReview)
}

/// Plan import (§7.7): paste or open the JSON, validate, review, then add or update.
/// Presented bare from `RootTabView` (owns its NavigationStack), or embedded in the Intake sheet's stack.
struct ImportPlanView: View {
    let goalID: UUID?
    private let embedded: Bool
    private let onImported: (() -> Void)?

    @Environment(AppServices.self) private var services
    @Environment(Router.self) private var router

    @State private var stage: GoalsImportStage = .empty
    @State private var rawText = ""
    @State private var showFileImporter = false
    @State private var failureTick = 0
    @State private var isApplying = false
    @State private var notice: String?

    init(goalID: UUID?, embedded: Bool = false, onImported: (() -> Void)? = nil) {
        self.goalID = goalID
        self.embedded = embedded
        self.onImported = onImported
    }

    var body: some View {
        if embedded {
            screen
        } else {
            NavigationStack { screen }
        }
    }

    private var screen: some View {
        NightCanvas {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stageContent
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Import.")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { router.sheet = nil }
                }
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json]) { result in
            handleFile(result)
        }
        .haptic(.importFailed, trigger: failureTick)
        .task { consumePending() }
        .onChange(of: router.pendingImportURL) { _, url in
            if url != nil { consumePending() }
        }
    }

    // MARK: Stages

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .empty:
            emptyContent
        case .parsing:
            HStack(spacing: 12) {
                ProgressView()
                Text("Checking the plan…")
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        case .failed(let issues):
            failedContent(issues)
        case .review(let review):
            reviewContent(review)
        }
    }

    private var emptyContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.largeTitle)
                .foregroundStyle(Color.cobaltText)
                .accessibilityHidden(true)
            Text("Paste the JSON Claude gave you")
                .font(.tileTitle)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
            if let goalID, let goal = services.store.snapshot().goal(goalID) {
                Text("This updates \(goal.title). Nothing else changes until you confirm.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            sourceButtons
            if let notice {
                GoalsFormMessage(text: notice)
            }
        }
        .padding(.top, 24)
    }

    private var sourceButtons: some View {
        VStack(spacing: 8) {
            Button("Paste") { paste() }
                .buttonStyle(GoalsSolidButtonStyle())
            Button("Open file") { showFileImporter = true }
                .buttonStyle(GoalsSolidButtonStyle(prominent: false))
        }
        .padding(.top, 8)
    }

    private func failedContent(_ issues: [PlanIssue]) -> some View {
        let shown = issues.prefix(5).map { $0.description }
        var lines = shown
        if issues.count > 5 { lines.append("and \(issues.count - 5) more") }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Claude's plan has problems")
                .font(.tileTitle)
                .foregroundStyle(Color.textPrimary)
            FlagBox(text: lines.joined(separator: "\n"))
            Button("Copy errors") {
                UIPasteboard.general.string = issues.map { $0.description }.joined(separator: "\n")
                router.toast = "Errors copied. Paste them back to Claude."
            }
            .buttonStyle(GoalsSolidButtonStyle())
            Text("Nothing was created. Fix the plan with Claude, then paste it again.")
                .font(.footnote)
                .foregroundStyle(Color.textTertiary)
            sourceButtons
        }
    }

    // MARK: Review

    @ViewBuilder
    private func reviewContent(_ review: GoalsImportReview) -> some View {
        let summary = review.result.summary
        VStack(alignment: .leading, spacing: 16) {
            Text(summary.goalTitle)
                .font(.tileTitle)
                .foregroundStyle(Color.textPrimary)
            if summary.isUpdate {
                Text("Updates \(summary.goalTitle): +\(summary.inserted) new, \(summary.changed) changed, \(summary.removed) removed")
                    .font(.subheadline)
                    .foregroundStyle(Color.cobaltText)
            }
            GoalsCard {
                VStack(spacing: 10) {
                    countRow("First principles", summary.principles)
                    countRow("Systems", summary.systems)
                    countRow("Habits", summary.habits)
                    countRow("Blocks", summary.blocks)
                    countRow("Reminders", summary.reminders)
                }
            }
            if !summary.movedOffSaturday.isEmpty {
                listSection("Moved off Saturday", summary.movedOffSaturday, tint: Color.textSecondary)
            }
            if !review.clashLines.isEmpty {
                listSection("Clashes with your calendar", review.clashLines, tint: Color.emberText)
            }
            if let message = review.feasibilityMessage {
                FlagBox(text: message)
            }
            if !summary.startsLate.isEmpty {
                listSection("Starting late", summary.startsLate, tint: Color.emberText)
            }
            if let notice {
                GoalsFormMessage(text: notice)
            }
            Button {
                apply(review)
            } label: {
                if isApplying {
                    ProgressView()
                } else {
                    Text(summary.isUpdate ? "Update goal" : "Add to app")
                }
            }
            .buttonStyle(GoalsSolidButtonStyle())
            .disabled(isApplying)
            Button("Start over") {
                stage = .empty
                notice = nil
            }
            .buttonStyle(GoalsSolidButtonStyle(prominent: false))
        }
    }

    private func countRow(_ label: String, _ count: Int) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text("\(count)")
                .font(.gaugeNumber)
                .foregroundStyle(Color.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private func listSection(_ title: String, _ lines: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.sectionTitle)
                .foregroundStyle(Color.textPrimary)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(tint)
            }
        }
    }

    // MARK: Input

    private func paste() {
        let text = UIPasteboard.general.string ?? ""
        if GoalsFormat.trimmed(text).isEmpty {
            notice = "Nothing to paste. Copy Claude's whole reply first."
            return
        }
        notice = nil
        Task { await process(text) }
    }

    private func handleFile(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            loadFile(url)
        case .failure:
            fail([PlanIssue(path: "file", message: "couldn't open it")])
        }
    }

    private func loadFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            fail([PlanIssue(path: "file", message: "couldn't read it as text")])
            return
        }
        notice = nil
        Task { await process(text) }
    }

    private func consumePending() {
        guard let url = router.pendingImportURL else { return }
        router.pendingImportURL = nil
        loadFile(url)
    }

    private func fail(_ issues: [PlanIssue]) {
        stage = .failed(issues)
        failureTick += 1
    }

    // MARK: Processing

    private func process(_ text: String) async {
        stage = .parsing
        rawText = text
        guard let data = PlanImporter.extractJSON(from: text) else {
            fail([PlanImportError.noJSON.issue])
            return
        }
        var plan: PlanV1
        do throws(PlanImportError) {
            plan = try PlanImporter.decode(data)
        } catch {
            fail([error.issue])
            return
        }
        let issues = PlanImporter.validate(plan)
        if !issues.isEmpty {
            fail(issues)
            return
        }
        // Update mode: a plan opened for a goal without its own goal id updates that goal.
        if let goalID {
            let given = plan.goal.id.flatMap { UUID(uuidString: $0) }
            if given == nil { plan.goal.id = goalID.uuidString }
        }
        let snapshot = services.store.snapshot()
        let result = PlanImporter.materialise(plan, into: snapshot, today: LocalDay.today, settings: snapshot.settings)
        let review = await makeReview(result: result, snapshot: snapshot)
        stage = .review(review)
    }

    private func makeReview(result: ImportResult, snapshot: StoreSnapshot) async -> GoalsImportReview {
        let now = Date()
        let merged = snapshot.applying(result.changes)
        var busy: [BusyInterval] = []
        if services.calendar.status == .granted {
            let start = LocalDay(now).date()
            busy = await services.calendar.busyIntervals(in: DateInterval(start: start, end: start.addingTimeInterval(14 * 24 * 3600)))
        }

        var newBlocks: [CalendarBlock] = []
        var newRules: [BlockRule] = []
        for entity in result.changes.upserts {
            switch entity {
            case .block(let block): newBlocks.append(block)
            case .blockRule(let rule): newRules.append(rule)
            default: break
            }
        }
        let generated = ScheduleEngine.materialise(rules: newRules, existing: merged.blocks, from: LocalDay(now), days: 14,
                                                   settings: merged.settings, systems: merged.systems)
        newBlocks += generated
        let checked = ScheduleEngine.detectClashes(blocks: newBlocks, busy: busy, settings: merged.settings, now: now)
        let clashes = checked.filter { $0.status == .clash }.sorted { $0.start < $1.start }
        var lines: [String] = []
        for block in clashes.prefix(5) {
            let rule = block.ruleID.flatMap { merged.blockRule($0) }
            var line = "\(block.title), \(LockInFormat.dayMonthTime(block.start))"
            if let slot = ScheduleEngine.suggestSlot(for: block, rule: rule, busy: busy, blocks: merged.blocks + generated,
                                                     settings: merged.settings) {
                line += ". Try \(LockInFormat.dayMonthTime(slot))."
            }
            lines.append(line)
        }
        if clashes.count > 5 { lines.append("and \(clashes.count - 5) more") }

        var feasibility: String? = nil
        if let goal = merged.goal(result.goalID) {
            let weekAhead = now.addingTimeInterval(7 * 24 * 3600)
            let nearBusy = busy.filter { $0.start < weekAhead }
            feasibility = ScheduleEngine.feasibility(goal: goal, snapshot: merged, busy: nearBusy, now: now).message
        }
        return GoalsImportReview(result: result, clashLines: lines, feasibilityMessage: feasibility)
    }

    // MARK: Apply

    private func apply(_ review: GoalsImportReview) {
        guard !isApplying else { return }
        isApplying = true
        notice = nil
        let importedGoalID = review.result.goalID
        let text = rawText
        Task {
            var changes = review.result.changes
            changes.upserts = changes.upserts.map { (entity: AnyEntity) -> AnyEntity in
                if case .goal(var goal) = entity, goal.id == importedGoalID {
                    goal.importedPlanJSON = text
                    return .goal(goal)
                }
                return entity
            }
            do {
                try services.store.apply(changes)
            } catch {
                notice = GoalsActions.saveFailed
                isApplying = false
                return
            }
            _ = await services.calendar.sync()
            onImported?()
            isApplying = false
            router.sheet = nil
            let alreadyThere = router.tab == .goals && router.goalsPath.last == .goalDetail(importedGoalID)
            if !alreadyThere { router.push(.goalDetail(importedGoalID)) }
        }
    }
}

#Preview {
    ImportPlanView(goalID: nil)
        .environment(AppServices.preview())
        .environment(Router())
}
