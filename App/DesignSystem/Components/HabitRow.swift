import SwiftUI
import CoreKit

/// §8.5 `HabitRow`: title, subtitle and a trailing mark dot. Tapping the dot calls `onTapMark` (44×44 target),
/// tapping the rest of the row calls `onTapRow`. No background of its own: it sits on the canvas or inside a tile.
/// `scheduled` (default true) draws the "not scheduled" dash instead of a dot, for habits not due today.
struct HabitRow: View {
    let title: String
    let subtitle: String?
    let mark: Mark?
    let scheduled: Bool
    let onTapMark: () -> Void
    let onTapRow: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        mark: Mark?,
        scheduled: Bool = true,
        onTapMark: @escaping () -> Void,
        onTapRow: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.mark = mark
        self.scheduled = scheduled
        self.onTapMark = onTapMark
        self.onTapRow = onTapRow
    }

    var body: some View {
        HStack(spacing: Spacing.s8) {
            Button(action: onTapRow) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: Sizing.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(HabitRowPressStyle())
            .accessibilityLabel(rowAccessibilityLabel)

            Button(action: onTapMark) {
                MarkDot(mark: mark, scheduled: scheduled, size: Sizing.markDotRow)
                    .frame(width: Sizing.minTouchTarget, height: Sizing.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HabitRowPressStyle())
            .accessibilityLabel("Mark \(title)")
            .accessibilityValue(markDescription)
        }
        .padding(.vertical, Spacing.rowVertical)
    }

    private var rowAccessibilityLabel: String {
        if let subtitle, !subtitle.isEmpty {
            return "\(title), \(subtitle)"
        }
        return title
    }

    private var markDescription: String {
        guard scheduled else { return "not scheduled" }
        switch mark {
        case .D: return "done"
        case .B: return "bad-day version"
        case .M: return "missed"
        case nil: return "not marked yet"
        }
    }
}

private struct HabitRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

#Preview("HabitRow") {
    NightCanvas {
        VStack(spacing: 0) {
            HabitRow(title: "Lift", subtitle: "M W F · this week 2/3 · 4-week streak", mark: .D, onTapMark: {}, onTapRow: {})
            HabitRow(title: "Protein x4", subtitle: "daily · this week 5/7", mark: .B, onTapMark: {}, onTapRow: {})
            HabitRow(title: "Incline walk", subtitle: "5/wk · this week 1/5", mark: .M, onTapMark: {}, onTapRow: {})
            HabitRow(title: "Post-gym meal", subtitle: "M W F", mark: nil, onTapMark: {}, onTapRow: {})
            HabitRow(title: "Meal prep", subtitle: "Sun", mark: nil, scheduled: false, onTapMark: {}, onTapRow: {})
        }
        .padding(.horizontal, Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
