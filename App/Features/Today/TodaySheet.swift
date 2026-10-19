import SwiftUI
import CoreKit

/// DESIGN.md §7.3: today's timeline. Presented bare by the shell through `Router.sheet`.
struct TodaySheet: View {
    @Environment(AppServices.self) private var services
    @Environment(Router.self) private var router

    var body: some View {
        let _ = services.store.revision
        let snapshot = services.store.snapshot()
        let now = Date()
        let day = HabitEngine.logicalDay(for: now)
        let plan = TodayPlan.build(snapshot: snapshot, day: day, now: now)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(plan: plan, day: day)
                if plan.isEmpty {
                    Text("Nothing planned today.")
                        .font(.body)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 24)
                } else {
                    if !plan.timed.isEmpty {
                        group(title: "Scheduled", items: plan.timed, day: day, showTime: true)
                    }
                    if !plan.untimed.isEmpty {
                        group(title: "Anytime", items: plan.untimed, day: day, showTime: false)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func header(plan: TodayPlanModel, day: LocalDay) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LockInFormat.titled("Today"))
                .font(.tileTitle)
                .foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(plan.habitsLeft > 0
                 ? "\(LockInFormat.dayMonth(day)) · \(plan.habitsLeft) left"
                 : LockInFormat.dayMonth(day))
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func group(title: String, items: [TodayItem], day: LocalDay, showTime: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.rowSeparator)
                            .frame(height: 1)
                    }
                    row(item, day: day, showTime: showTime)
                }
            }
            .padding(.horizontal, 16)
            .background { HabitsTileSurface(radius: 22) }
        }
    }

    private func row(_ item: TodayItem, day: LocalDay, showTime: Bool) -> some View {
        let isDimmed = item.blockStatus == .done
        return Button {
            open(item, day: day)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                if showTime {
                    Text(item.minutes.map { LockInFormat.time($0) } ?? "")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 48, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body)
                        .foregroundStyle(isDimmed ? Color.textSecondary : Color.textPrimary)
                        .lineLimit(2)
                    if let detail = item.detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                trailing(item)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func trailing(_ item: TodayItem) -> some View {
        switch item.kind {
        case .habit:
            MarkDot(mark: item.mark, scheduled: true, size: 16)
        case .block:
            switch item.blockStatus {
            case .some(.done):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityLabel("Done")
            case .some(.clash):
                Text("Clash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.emberText)
            default:
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    private func open(_ item: TodayItem, day: LocalDay) {
        switch item.kind {
        case .habit: router.sheet = .markHabit(item.refID, day)
        case .block: router.sheet = .block(item.refID)
        }
    }
}

#Preview {
    TodaySheet()
        .environment(AppServices.preview())
        .environment(Router())
}
