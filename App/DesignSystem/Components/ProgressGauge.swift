import SwiftUI

/// Plain data for a `ProgressGauge` (§8.5). `fraction` and `setPoint` are 0...1 of the track width.
nonisolated struct GaugeModel: Equatable, Sendable {
    enum State: Equatable, Sendable {
        /// Cobalt: at or above the set point (or pro-rata expected).
        case onTrack
        /// Ember: behind.
        case behind
        /// No colour meaning (no habits yet, nothing to judge).
        case neutral
    }

    var fraction: Double
    /// Position of the set-point tick, 0...1. nil hides the tick.
    var setPoint: Double?
    /// Drawn inside the track, right-aligned: "9 of 12".
    var label: String
    var state: State
    /// Scale label above the left end: "0".
    var lowLabel: String?
    /// Scale label above the right end: "12".
    var highLabel: String?
    /// Full VoiceOver text, e.g. "This week, 9 of 12 done, set point 8, on track". When nil one is built from
    /// `label`, the set point percentage and `state`.
    var accessibilityText: String?

    init(
        fraction: Double,
        setPoint: Double? = nil,
        label: String,
        state: State,
        lowLabel: String? = nil,
        highLabel: String? = nil,
        accessibilityText: String? = nil
    ) {
        self.fraction = fraction
        self.setPoint = setPoint
        self.label = label
        self.state = state
        self.lowLabel = lowLabel
        self.highLabel = highLabel
        self.accessibilityText = accessibilityText
    }
}

extension GaugeModel.State {
    /// The glow colour for this state at full strength, or clear for neutral.
    var glowBase: Color {
        switch self {
        case .onTrack: Color.cobaltGlow
        case .behind: Color.emberGlow
        case .neutral: Color.clear
        }
    }
}

/// §8.5 `ProgressGauge(model:)`: track + fill + glow + set-point tick + label, with optional scale labels above.
/// Solid, never glass. Height is 38 pt at the default text size and scales with Dynamic Type.
struct ProgressGauge: View {
    let model: GaugeModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var trackHeight: CGFloat = Sizing.gaugeHeight

    init(model: GaugeModel) {
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            if showsScale {
                scaleRow
            }
            track
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: Values

    private var clampedFraction: Double {
        model.fraction.isFinite ? min(max(model.fraction, 0), 1) : 0
    }

    private var clampedSetPoint: Double? {
        guard let setPoint = model.setPoint, setPoint.isFinite else { return nil }
        return min(max(setPoint, 0), 1)
    }

    private var showsScale: Bool {
        model.lowLabel != nil || model.highLabel != nil
    }

    private var accessibilityDescription: String {
        if let custom = model.accessibilityText, !custom.isEmpty {
            return custom
        }
        var parts = [model.label]
        if let setPoint = clampedSetPoint {
            parts.append("set point \(Int((setPoint * 100).rounded())) percent")
        }
        switch model.state {
        case .onTrack: parts.append("on track")
        case .behind: parts.append("behind")
        case .neutral: break
        }
        return parts.joined(separator: ", ")
    }

    private var fillStyle: AnyShapeStyle {
        switch model.state {
        case .onTrack:
            AnyShapeStyle(EllipticalGradient.cobaltFill)
        case .behind:
            AnyShapeStyle(EllipticalGradient.emberFill)
        case .neutral:
            AnyShapeStyle(LinearGradient(
                colors: [Color.markB.opacity(0.55), Color.markB.opacity(0.35)],
                startPoint: .leading,
                endPoint: .trailing
            ))
        }
    }

    private func fillWidth(in totalWidth: CGFloat) -> CGFloat {
        let fraction = clampedFraction
        guard fraction > 0, totalWidth > 0 else { return 0 }
        // Never narrower than a circle, so a tiny value still reads as a fill.
        return min(totalWidth, max(totalWidth * fraction, trackHeight))
    }

    // MARK: Scale labels above the track

    private var scaleRow: some View {
        HStack(spacing: 0) {
            Text(model.lowLabel ?? "")
            Spacer(minLength: 0)
            Text(model.highLabel ?? "")
        }
        .font(.caption2)
        .foregroundStyle(Color.textTertiary)
        .overlay { setPointCaption }
    }

    /// "set point" centred over the tick. It is
    /// dropped near either end, where it would collide with the end labels.
    private var setPointCaption: some View {
        GeometryReader { proxy in
            if let setPoint = clampedSetPoint, setPoint > 0.12, setPoint < 0.88 {
                Text("set point")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize()
                    .frame(width: 0, alignment: .center)
                    .position(x: proxy.size.width * setPoint, y: proxy.size.height / 2)
            }
        }
    }

    // MARK: Track

    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let filled = fillWidth(in: width)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gaugeTrackFill)
                GaugeDotGrid()
                    .clipShape(Capsule())
                if filled > 0 {
                    gaugeFill(width: filled)
                }
                if let setPoint = clampedSetPoint {
                    Rectangle()
                        .fill(Color.gaugeTick)
                        .frame(
                            width: Sizing.gaugeTickWidth,
                            height: max(height - 2 * Sizing.gaugeTickInset, 0)
                        )
                        .offset(x: width * setPoint - Sizing.gaugeTickWidth / 2)
                }
                Capsule()
                    .strokeBorder(Color.gaugeTrackStroke, lineWidth: 1)
            }
            .frame(width: width, height: height)
            .overlay(alignment: .trailing) { valueLabel }
            .animation(Motion.animation(.gaugeFill, reduceMotion: reduceMotion), value: model.fraction)
        }
        .frame(height: trackHeight)
    }

    private func gaugeFill(width: CGFloat) -> some View {
        Capsule()
            .fill(fillStyle)
            .frame(width: width, height: trackHeight)
            .overlay(alignment: .trailing) {
                if model.state == .behind {
                    emberRim
                }
            }
            .shadow(
                color: model.state.glowBase.opacity(GlowSpec.gaugeOpacity),
                radius: GlowSpec.gaugeRadius
            )
    }

    /// The 2 pt `emberEdge` on the leading end of an ember fill: the round end only.
    private var emberRim: some View {
        Capsule()
            .strokeBorder(Color.emberEdge, lineWidth: 2)
            .mask(alignment: .trailing) {
                Rectangle().frame(width: trackHeight / 2)
            }
    }

    private var valueLabel: some View {
        Text(model.label)
            .font(.gaugeNumber)
            .foregroundStyle(Color.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.trailing, Sizing.gaugeLabelInset)
            .allowsHitTesting(false)
    }
}

/// 1 pt dots on a 5 pt pitch at 7% white. Drawn in one `Canvas` pass; the closure only uses literals and
/// `nonisolated` constants so it is safe whether or not SwiftUI treats it as `@Sendable`.
private struct GaugeDotGrid: View {
    var body: some View {
        Canvas { context, size in
            let pitch = Sizing.gaugeDotPitch
            let dot = Sizing.gaugeDotSize
            var path = Path()
            var y = pitch / 2
            while y < size.height {
                var x = pitch / 2
                while x < size.width {
                    path.addRect(CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot))
                    x += pitch
                }
                y += pitch
            }
            context.fill(path, with: .color(Color(white: 1, opacity: 0.07)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("ProgressGauge") {
    NightCanvas {
        VStack(spacing: Spacing.s24) {
            ProgressGauge(model: GaugeModel(
                fraction: 0.75, setPoint: 0.67, label: "9 of 12", state: .onTrack, lowLabel: "0", highLabel: "12"
            ))
            ProgressGauge(model: GaugeModel(
                fraction: 0.4, setPoint: 0.67, label: "5 of 12", state: .behind, lowLabel: "0", highLabel: "12"
            ))
            ProgressGauge(model: GaugeModel(fraction: 0.1, label: "no habits yet", state: .neutral))
            ProgressGauge(model: GaugeModel(fraction: 1, setPoint: 1, label: "3 of 3 on target", state: .onTrack))
        }
        .padding(.horizontal, Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
