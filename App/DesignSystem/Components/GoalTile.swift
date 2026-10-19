import SwiftUI

/// §8.5 `GoalTile`: solid tile (tile gradient, 1 pt stroke, radius 28) with a state-coloured under-glow.
/// Contents: title with full stop, days left, `ProgressGauge`, result and streak, optional bottleneck line.
/// At accessibility text sizes the title and days left stack, and the footer wraps.
/// VoiceOver reads one element: "{title}, {days} days left, {gauge label}, result {resultText}, {streak}".
/// Wrap it in a `Button` / `NavigationLink` so double tap opens the goal.
struct GoalTile: View {
    let title: String
    let daysLeft: Int
    let gauge: GaugeModel
    let resultText: String
    let streakText: String
    /// The bottleneck habit's title; "Bottleneck: " is added here. nil or empty hides the line.
    let bottleneck: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        title: String,
        daysLeft: Int,
        gauge: GaugeModel,
        resultText: String,
        streakText: String,
        bottleneck: String? = nil
    ) {
        self.title = title
        self.daysLeft = daysLeft
        self.gauge = gauge
        self.resultText = resultText
        self.streakText = streakText
        self.bottleneck = bottleneck
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            header
            ProgressGauge(model: gauge)
            footer
            if let bottleneckLine {
                Text(bottleneckLine)
                    .font(.footnote)
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Spacing.tileHorizontal)
        .padding(.vertical, Spacing.tileVertical)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle.continuous(Radius.tile)
                .fill(.tileGradient)
                .shadow(
                    color: gauge.state.glowBase.opacity(GlowSpec.tileOpacity),
                    radius: GlowSpec.tileRadius,
                    x: 0,
                    y: GlowSpec.tileOffsetY
                )
        }
        .overlay {
            RoundedRectangle.continuous(Radius.tile)
                .strokeBorder(Color.tileStroke, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: Pieces

    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                TitleText(title, style: .tile)
                daysLeftLabel
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s8) {
                TitleText(title, style: .tile)
                    .frame(maxWidth: .infinity, alignment: .leading)
                daysLeftLabel
            }
        }
    }

    private var daysLeftLabel: some View {
        Text(daysLeftText)
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(daysLeft < 0 ? Color.emberText : Color.textSecondary)
            .fixedSize()
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s8) {
                resultLabel
                Spacer(minLength: Spacing.s8)
                streakLabel
            }
            VStack(alignment: .leading, spacing: Spacing.s4) {
                resultLabel
                streakLabel
            }
        }
    }

    private var resultLabel: some View {
        Text(resultText)
            .font(.subheadline)
            .foregroundStyle(Color.textSecondary)
            .lineLimit(1)
    }

    private var streakLabel: some View {
        Text(streakText)
            .font(.subheadline)
            .foregroundStyle(Color.textSecondary)
            .lineLimit(1)
    }

    // MARK: Text

    private var daysLeftText: String {
        switch daysLeft {
        case ..<0: return daysLeft == -1 ? "1 day overdue" : "\(-daysLeft) days overdue"
        case 0: return "Due today"
        case 1: return "1 day left"
        default: return "\(daysLeft) days left"
        }
    }

    private var bottleneckLine: String? {
        guard let bottleneck, !bottleneck.isEmpty else { return nil }
        return bottleneck.lowercased().hasPrefix("bottleneck") ? bottleneck : "Bottleneck: \(bottleneck)"
    }

    private var accessibilityDescription: String {
        var parts = [title, daysLeftText, gauge.label, "result \(resultText)", streakText]
        if let bottleneckLine {
            parts.append(bottleneckLine)
        }
        return parts.joined(separator: ", ")
    }
}

#Preview("GoalTile") {
    NightCanvas {
        ScrollView {
            VStack(spacing: Spacing.tileGap) {
                GoalTile(
                    title: "10% body fat",
                    daysLeft: 71,
                    gauge: GaugeModel(
                        fraction: 0.75, setPoint: 0.67, label: "9 of 12", state: .onTrack, lowLabel: "0", highLabel: "12"
                    ),
                    resultText: "84.2 kg, target 82.0",
                    streakText: "3-week streak",
                    bottleneck: "Protein x4"
                )
                GoalTile(
                    title: "Pass thermodynamics",
                    daysLeft: 9,
                    gauge: GaugeModel(
                        fraction: 0.3, setPoint: 0.6, label: "3 of 10", state: .behind, lowLabel: "0", highLabel: "10"
                    ),
                    resultText: "52%, target 70%",
                    streakText: "no streak",
                    bottleneck: "Past papers"
                )
                GoalTile(
                    title: "Read 12 books",
                    daysLeft: 200,
                    gauge: GaugeModel(fraction: 0, label: "no habits yet", state: .neutral),
                    resultText: "0 books, target 12",
                    streakText: "no streak",
                    bottleneck: nil
                )
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.s24)
        }
    }
    .preferredColorScheme(.dark)
}
