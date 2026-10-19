import SwiftUI

/// §8.5 `NightCanvas { content }`: canvas colour + canvasGlow + horizonGlow + grain behind your content.
/// The background ignores safe areas (so the system tab bar always has light to refract); the content does not.
/// Use it as the root of every tab. Scroll views inside should extend under the tab bar, and `List`s need
/// `.scrollContentBackground(.hidden)` so the canvas shows through.
struct NightCanvas<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            NightBackdrop()
                .ignoresSafeArea()
            content
        }
    }
}

/// Canvas, glows and grain, sized to the full screen. All decorative.
private struct NightBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                Color.canvas
                // canvasGlow: ellipse with radii 130% × 55% of the screen, centred at x 50%, y −12%.
                // The gradient is an ellipse inscribed in its rect, so the rect is twice the radii.
                Rectangle()
                    .fill(.canvasGlow)
                    .frame(width: width * 2.6, height: height * 1.1)
                    .position(x: width * 0.5, y: height * -0.12)
                // horizonGlow: radii 100% × 30%, centred on the bottom edge.
                Rectangle()
                    .fill(.horizonGlow)
                    .frame(width: width * 2.0, height: height * 0.6)
                    .position(x: width * 0.5, y: height)
                GrainOverlay()
            }
            .frame(width: width, height: height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("NightCanvas") {
    NightCanvas {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            TitleText("Goals")
            Text("Canvas, canvas glow, horizon glow and grain sit behind everything.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}

#Preview("NightCanvas under a tab bar") {
    TabView {
        Tab("Goals", systemImage: "target") {
            NightCanvas {
                ScrollView {
                    VStack(spacing: Spacing.tileGap) {
                        ForEach(0..<6, id: \.self) { index in
                            GoalTile(
                                title: "Goal \(index + 1)",
                                daysLeft: 60 - index * 7,
                                gauge: GaugeModel(
                                    fraction: 0.4 + Double(index) * 0.1,
                                    setPoint: 0.6,
                                    label: "\(index + 4) of 12",
                                    state: index % 2 == 0 ? .onTrack : .behind
                                ),
                                resultText: "84.2 kg, target 82.0",
                                streakText: "no streak",
                                bottleneck: nil
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.screenMargin)
                }
            }
        }
        Tab("Calendar", systemImage: "calendar") {
            NightCanvas { Text("Calendar").foregroundStyle(Color.textPrimary) }
        }
    }
    .tint(Color.cobalt)
    .preferredColorScheme(.dark)
}
