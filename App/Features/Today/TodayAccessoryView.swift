import SwiftUI
import CoreKit

/// DESIGN.md §7.3. The shell places this inside `.tabViewBottomAccessory`, which supplies the glass.
/// It adds no background of its own and handles its own tap.
struct TodayAccessoryView: View {
    @Environment(AppServices.self) private var services
    @Environment(Router.self) private var router

    var body: some View {
        let _ = services.store.revision
        let snapshot = services.store.snapshot()
        TimelineView(.everyMinute) { context in
            accessory(snapshot: snapshot, now: context.date)
        }
    }

    private func accessory(snapshot: StoreSnapshot, now: Date) -> some View {
        let day = HabitEngine.logicalDay(for: now)
        let plan = TodayPlan.build(snapshot: snapshot, day: day, now: now)
        let next = TodayPlan.next(in: plan, now: now)
        let clashes = TodayPlan.clashCount(snapshot: snapshot, now: now)
        let left = plan.habitsLeft
        let summary = summaryText(plan: plan, next: next)
        return Button {
            router.sheet = .today
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.cobaltText)
                    .accessibilityHidden(true)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if clashes > 0 {
                    Text(clashes == 1 ? "1 clash" : "\(clashes) clashes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background { Capsule().fill(Color.white.opacity(0.14)) }
                }
                if left > 0 {
                    Text("\(left) left")
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(summary: summary, left: left, clashes: clashes))
        .accessibilityHint("Opens today's plan")
    }

    private func summaryText(plan: TodayPlanModel, next: TodayItem?) -> String {
        if let next {
            if let minutes = next.minutes {
                return "\(next.title), \(LockInFormat.time(minutes))"
            }
            return next.title
        }
        return plan.isEmpty ? "Nothing planned today." : "All done today."
    }

    private func accessibilityText(summary: String, left: Int, clashes: Int) -> String {
        var parts = ["Today", summary]
        if left > 0 { parts.append("\(left) left") }
        if clashes > 0 { parts.append(clashes == 1 ? "1 clash" : "\(clashes) clashes") }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    TodayAccessoryView()
        .padding()
        .environment(AppServices.preview())
        .environment(Router())
}
