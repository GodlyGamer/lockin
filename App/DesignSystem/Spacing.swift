import SwiftUI

// DESIGN.md §8.3. Plain numbers, `nonisolated` so they can be read from any context (including
// `Canvas` and other `@Sendable` closures under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor).

/// Spacing scale 4, 8, 12, 16, 20, 24, 32 pt plus the named layout gaps.
nonisolated enum Spacing {
    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s20: CGFloat = 20
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32

    /// Screen side margin.
    static let screenMargin: CGFloat = 16
    /// Gap between tiles.
    static let tileGap: CGFloat = 12
    /// Tile padding, horizontal.
    static let tileHorizontal: CGFloat = 18
    /// Tile padding, vertical.
    static let tileVertical: CGFloat = 16
    /// Row vertical padding.
    static let rowVertical: CGFloat = 8
}

/// Corner radii. All are used with `.continuous` corners (see `RoundedRectangle.continuous(_:)`);
/// chips and the gauge are `Capsule`.
nonisolated enum Radius {
    static let tile: CGFloat = 28
    static let mapNode: CGFloat = 14
    static let field: CGFloat = 10
    /// Week flag box.
    static let flagBox: CGFloat = 14
    /// PermissionBanner (not in the spec table; matches the flag box).
    static let banner: CGFloat = 14
}

/// Sizes from §8.3.
nonisolated enum Sizing {
    /// Gauge height at the default text size (it scales with Dynamic Type through `@ScaledMetric`).
    static let gaugeHeight: CGFloat = 38
    /// Set-point tick: 1 pt wide, inset 6 pt top and bottom.
    static let gaugeTickWidth: CGFloat = 1
    static let gaugeTickInset: CGFloat = 6
    /// Gauge label sits 14 pt from the end.
    static let gaugeLabelInset: CGFloat = 14
    /// Gauge track dot grid: 1 pt dots on a 5 pt pitch.
    static let gaugeDotSize: CGFloat = 1
    static let gaugeDotPitch: CGFloat = 5

    /// Mark dot in the Week grid.
    static let markDotWeek: CGFloat = 13
    /// Mark dot in rows.
    static let markDotRow: CGFloat = 16
    /// "Not scheduled" dash.
    static let dashWidth: CGFloat = 6
    static let dashHeight: CGFloat = 2
    /// M dot outline width.
    static let markStrokeWidth: CGFloat = 1.5

    /// Minimum touch target, both sides.
    static let minTouchTarget: CGFloat = 44
    /// Minimum map node width (§4.8). The map layout enforces it; exposed for M5.
    static let mapNodeMinWidth: CGFloat = 72
    /// Map edge line width (§4.8).
    static let mapEdgeWidth: CGFloat = 1.2
}

extension RoundedRectangle {
    /// A continuous-corner rounded rectangle, which is how every radius in §8.3 is drawn.
    static func continuous(_ cornerRadius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}
