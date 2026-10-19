import SwiftUI

/// DESIGN.md §8.6 motion. Every duration and curve lives here, and every function takes the Reduce Motion flag:
/// springs become `.easeInOut(duration: 0.2)` and moves become crossfades.
/// Read the flag with `@Environment(\.accessibilityReduceMotion)`, or use the `.motion(_:value:)` and
/// `.tileInsertion()` modifiers below, which read it for you.
nonisolated enum Motion {
    enum Kind {
        /// Gauge fill changes: `.spring(response: 0.5, dampingFraction: 0.8)`.
        case gaugeFill
        /// Mark dot change: scale 0.8 → 1.0 over 0.2 s.
        case markDot
        /// Tile insertion: opacity + move from the bottom, 0.3 s.
        case tileInsertion
        /// Toast in and out: 0.3 s.
        case toast
    }

    static let gaugeResponse: Double = 0.5
    static let gaugeDamping: Double = 0.8
    static let markDotStartScale: Double = 0.8
    static let markDotDuration: Double = 0.2
    static let tileInsertionDuration: Double = 0.3
    /// What springs and moves collapse to when Reduce Motion is on.
    static let reducedDuration: Double = 0.2
    /// How long a toast stays up.
    static let toastVisibleSeconds: Double = 2.5

    /// The animation for `kind`. With Reduce Motion on, always `.easeInOut(duration: 0.2)`.
    static func animation(_ kind: Kind, reduceMotion: Bool) -> Animation {
        if reduceMotion {
            return Animation.easeInOut(duration: reducedDuration)
        }
        switch kind {
        case .gaugeFill:
            return Animation.spring(response: gaugeResponse, dampingFraction: gaugeDamping)
        case .markDot:
            return Animation.easeOut(duration: markDotDuration)
        case .tileInsertion, .toast:
            return Animation.easeInOut(duration: tileInsertionDuration)
        }
    }

    /// Tile insertion: `.opacity` + `.move(edge: .bottom)`; a plain crossfade with Reduce Motion on.
    @MainActor
    static func tileInsertionTransition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            return AnyTransition.opacity
        }
        return AnyTransition.opacity.combined(with: AnyTransition.move(edge: .bottom))
    }

    /// Toast: opacity + move from the top; a plain crossfade with Reduce Motion on.
    @MainActor
    static func toastTransition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            return AnyTransition.opacity
        }
        return AnyTransition.opacity.combined(with: AnyTransition.move(edge: .top))
    }
}

extension View {
    /// `.animation(_:value:)` with the curve for `kind`, switched to the Reduce Motion version automatically.
    func motion<Value: Equatable>(_ kind: Motion.Kind, value: Value) -> some View {
        modifier(MotionModifier(kind: kind, value: value))
    }

    /// Sets the §8.6 tile insertion transition (opacity + move from the bottom, crossfade with Reduce Motion).
    /// Pair it with `.motion(.tileInsertion, value:)` on the container that inserts the tile.
    func tileInsertion() -> some View {
        modifier(TileInsertionModifier())
    }
}

private struct MotionModifier<Value: Equatable>: ViewModifier {
    let kind: Motion.Kind
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(kind: Motion.Kind, value: Value) {
        self.kind = kind
        self.value = value
    }

    func body(content: Content) -> some View {
        content.animation(Motion.animation(kind, reduceMotion: reduceMotion), value: value)
    }
}

private struct TileInsertionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(Motion.tileInsertionTransition(reduceMotion: reduceMotion))
    }
}
