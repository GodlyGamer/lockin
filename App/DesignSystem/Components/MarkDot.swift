import SwiftUI
import CoreKit

/// §8.5 `MarkDot(mark:scheduled:size:)`, appearance per §7.10:
/// D = cobalt dot with glow, B = `#A3ABB8` dot, M = hollow `#4A505B` ring (1.5 pt),
/// not scheduled = 6×2 pt dash `#3A3F48`. A scheduled day with no mark yet (`mark == nil`) is a dashed ring.
/// Size is 13 pt in the Week grid and 16 pt in rows. Changing the mark pops the dot (scale 0.8 → 1.0, 0.2 s);
/// with Reduce Motion on it crossfades instead.
struct MarkDot: View {
    let mark: Mark?
    let scheduled: Bool
    let size: CGFloat
    /// Optional spoken weekday ("Monday"), giving the §8.8 label "Monday, done".
    let weekday: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(mark: Mark?, scheduled: Bool = true, size: CGFloat = Sizing.markDotRow, weekday: String? = nil) {
        self.mark = mark
        self.scheduled = scheduled
        self.size = size
        self.weekday = weekday
    }

    var body: some View {
        ZStack {
            symbol
        }
        .frame(width: size, height: size)
        .keyframeAnimator(initialValue: 1.0, trigger: popTrigger) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(Motion.markDotStartScale, duration: 0.001)
                CubicKeyframe(1.0, duration: Motion.markDotDuration)
            }
        }
        .animation(Motion.animation(.markDot, reduceMotion: reduceMotion), value: mark)
        .animation(Motion.animation(.markDot, reduceMotion: reduceMotion), value: scheduled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private var symbol: some View {
        if !scheduled {
            Capsule()
                .fill(Color.notScheduled)
                .frame(width: Sizing.dashWidth, height: Sizing.dashHeight)
        } else {
            switch mark {
            case .D:
                Circle()
                    .fill(Color.cobalt)
                    .shadow(color: Color.cobaltGlow.opacity(GlowSpec.gaugeOpacity), radius: max(size * 0.4, 4))
            case .B:
                Circle()
                    .fill(Color.markB)
            case .M:
                Circle()
                    .strokeBorder(Color.markMStroke, lineWidth: Sizing.markStrokeWidth)
            case nil:
                Circle()
                    .strokeBorder(
                        Color.markMStroke,
                        style: StrokeStyle(lineWidth: Sizing.markStrokeWidth, dash: [2.5, 2.5])
                    )
            }
        }
    }

    /// Changes whenever the mark changes; constant with Reduce Motion so the pop never runs.
    private var popTrigger: Int {
        if reduceMotion { return 0 }
        switch mark {
        case nil: return 0
        case .D: return 1
        case .B: return 2
        case .M: return 3
        }
    }

    private var stateDescription: String {
        guard scheduled else { return "not scheduled" }
        switch mark {
        case .D: return "done"
        case .B: return "bad-day version"
        case .M: return "missed"
        case nil: return "not marked yet"
        }
    }

    private var accessibilityDescription: String {
        if let weekday, !weekday.isEmpty {
            return "\(weekday), \(stateDescription)"
        }
        return stateDescription
    }
}

#Preview("MarkDot") {
    NightCanvas {
        VStack(spacing: Spacing.s16) {
            HStack(spacing: Spacing.s16) {
                MarkDot(mark: .D, scheduled: true, size: Sizing.markDotWeek)
                MarkDot(mark: .B, scheduled: true, size: Sizing.markDotWeek)
                MarkDot(mark: .M, scheduled: true, size: Sizing.markDotWeek)
                MarkDot(mark: nil, scheduled: true, size: Sizing.markDotWeek)
                MarkDot(mark: nil, scheduled: false, size: Sizing.markDotWeek)
            }
            HStack(spacing: Spacing.s16) {
                MarkDot(mark: .D, scheduled: true, size: Sizing.markDotRow)
                MarkDot(mark: .B, scheduled: true, size: Sizing.markDotRow)
                MarkDot(mark: .M, scheduled: true, size: Sizing.markDotRow)
                MarkDot(mark: nil, scheduled: true, size: Sizing.markDotRow)
                MarkDot(mark: nil, scheduled: false, size: Sizing.markDotRow)
            }
        }
    }
    .preferredColorScheme(.dark)
}
