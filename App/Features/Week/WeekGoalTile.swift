import SwiftUI
import CoreKit

private func weekGaugeState(_ state: ProgressState) -> GaugeModel.State {
    switch state {
    case .onTrack: return .onTrack
    case .behind: return .behind
    case .neutral: return .neutral
    }
}

private func weekStateColor(_ state: ProgressState) -> Color {
    switch state {
    case .onTrack: return Color.cobaltText
    case .behind: return Color.emberText
    case .neutral: return Color.textSecondary
    }
}

/// A goal collapsed to one row: title and score. Tap to expand (DESIGN.md §7.10).
struct WeekCollapsedRow: View {
    let model: WeekGoalModel
    let onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: 12) {
                Text(LockInFormat.titled(model.goal.title))
                    .font(.sectionTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(model.total == 0 ? "No habits" : model.scoreLabel)
                    .font(.subheadline)
                    .foregroundStyle(weekStateColor(model.state))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(minHeight: 44)
            .background { HabitsTileSurface() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.goal.title), \(model.total == 0 ? "no habits" : model.scoreLabel)")
        .accessibilityHint("Expands this goal")
    }
}

/// The expanded goal tile: score gauge, 7-day grid, flags and (last week only) the review fields.
struct WeekGoalTile: View {
    let model: WeekGoalModel
    let mode: WeekTileMode
    let draft: WeekDraft?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(model: WeekGoalModel, mode: WeekTileMode, draft: WeekDraft?) {
        self.model = model
        self.mode = mode
        self.draft = draft
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if model.total == 0 && model.rows.isEmpty {
                Text("No habits in this goal yet.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            } else {
                gauge
                grid
            }
            if !model.flags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.flags, id: \.self) { flag in
                        FlagBox(text: flag)
                    }
                }
                .accessibilitySortPriority(1)
            }
            switch mode {
            case .reviewable:
                if let draft {
                    WeekReviewFields(goal: model.goal, choices: model.bottleneckChoices,
                                     previousResult: model.previousResult, draft: draft)
                }
            case .past:
                pastSummary
            case .live:
                EmptyView()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { HabitsTileSurface() }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(LockInFormat.titled(model.goal.title))
                .font(.tileTitle)
                .foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Text(model.streakText)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var gauge: some View {
        let fraction = model.total == 0 ? 0 : Double(model.onTarget) / Double(model.total)
        return ProgressGauge(model: GaugeModel(fraction: fraction,
                                               setPoint: nil,
                                               label: model.scoreLabel,
                                               state: weekGaugeState(model.state),
                                               lowLabel: nil,
                                               highLabel: nil))
    }

    @ViewBuilder
    private var grid: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(model.rows, id: \.id) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.name)
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                        HStack(spacing: 3) {
                            ForEach(row.dots, id: \.id) { dot in
                                MarkDot(mark: dot.mark, scheduled: dot.scheduled, size: 13)
                                    .frame(width: 22, height: 22)
                            }
                            Spacer(minLength: 8)
                            setText(row)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.accessibilitySummary)
                }
            }
        } else {
            Grid(alignment: .center, horizontalSpacing: 3, verticalSpacing: 6) {
                GridRow {
                    Color.clear
                        .frame(height: 1)
                        .gridColumnAlignment(.leading)
                    ForEach(0..<7, id: \.self) { index in
                        Text(LockInFormat.weekdayLetters[index])
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                            .accessibilityHidden(true)
                    }
                    Text("set")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                        .accessibilityHidden(true)
                }
                ForEach(model.rows, id: \.id) { row in
                    GridRow {
                        Text(row.name)
                            .font(.subheadline)
                            .foregroundStyle(row.isArchived ? Color.textSecondary : Color.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(row.accessibilitySummary)
                        ForEach(row.dots, id: \.id) { dot in
                            MarkDot(mark: dot.mark, scheduled: dot.scheduled, size: 13)
                                .frame(width: 22, height: 22)
                                .accessibilityHidden(true)
                        }
                        setText(row)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private func setText(_ row: WeekHabitRow) -> some View {
        Text("\(row.done)/\(row.setPoint)")
            .font(.footnote.monospacedDigit())
            .foregroundStyle(row.belowSetPoint ? Color.emberText : Color.textSecondary)
            .lineLimit(1)
            .frame(minWidth: 32, alignment: .trailing)
    }

    @ViewBuilder
    private var pastSummary: some View {
        if let review = model.review {
            VStack(alignment: .leading, spacing: 4) {
                if let value = review.resultValue {
                    let name = model.goal.resultName.isEmpty ? "Result" : model.goal.resultName
                    let unit = model.goal.resultUnit.isEmpty ? "" : " \(model.goal.resultUnit)"
                    Text("\(name): \(WeekNumber.format(value))\(unit)")
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                }
                if let title = model.reviewBottleneckTitle {
                    Text("Bottleneck: \(title)")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
                if let note = review.note, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }
}

/// Result, bottleneck and note for the week being reviewed (DESIGN.md §7.10).
struct WeekReviewFields: View {
    let goal: Goal
    let choices: [Habit]
    let previousResult: Double
    @Bindable var draft: WeekDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            resultField
            if let value = WeekNumber.parse(draft.resultText) {
                Text(WeekNumber.delta(from: previousResult, to: value, unit: goal.resultUnit))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.leading, 4)
            }
            HStack {
                Picker("Bottleneck", selection: $draft.bottleneckID) {
                    Text("None").tag(UUID?.none)
                    ForEach(choices, id: \.id) { habit in
                        Text(habit.title).tag(Optional(habit.id))
                    }
                }
                .pickerStyle(.menu)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background { HabitsFieldSurface() }
            TextField("Note (optional)", text: $draft.note, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(minHeight: 44)
                .background { HabitsFieldSurface() }
        }
    }

    private var resultField: some View {
        HStack(spacing: 8) {
            Text(goal.resultName.isEmpty ? "Result" : goal.resultName)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            TextField(WeekNumber.format(previousResult), text: $draft.resultText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 64, maxWidth: 120)
                .accessibilityLabel("\(goal.resultName.isEmpty ? "Result" : goal.resultName)")
            if !goal.resultUnit.isEmpty {
                Text(goal.resultUnit)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background { HabitsFieldSurface() }
    }
}
