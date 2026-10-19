import SwiftUI

// "Night glass" colour tokens, DESIGN.md §8.1. Dark only: there are no light-mode values.
//
// Every colour token is declared twice on purpose:
//   * `extension Color { static let … }` so `Color.cobalt` and `.tint(.cobalt)` work, and
//   * `extension ShapeStyle where Self == Color { static var … }` so the short form works in
//     style positions: `.foregroundStyle(.textSecondary)`, `.fill(.canvas)`, `.background(.blockFill)`.
// Gradients are `ShapeStyle` factories (`.fill(.tileGradient)`); the raw stop sets are `Gradient.…Stops`.
//
// Names deliberately avoid SwiftUI's own (`separator`, `tint`, `background`, `selection`, `placeholder` …),
// so the §8.1 `separator` token is called `rowSeparator`, and `field` is split into `fieldFill` / `fieldStroke`.

// MARK: - Color(hex:)

extension Color {
    /// `Color(hex: 0x3D6BFF)`. `opacity` is applied on top.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// `Color(hex: "#3D6BFF")`, `"3D6BFF"`, `"#FFF"` or `"#RRGGBBAA"`.
    /// Text that does not parse falls back to `textSecondary` (`#A3ABB8`), never crashes.
    init(hex: String, opacity: Double = 1) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard let value = UInt64(digits, radix: 16) else {
            self.init(hex: 0xA3ABB8, opacity: opacity)
            return
        }
        switch digits.count {
        case 3:
            let red = UInt32((value >> 8) & 0xF) * 17
            let green = UInt32((value >> 4) & 0xF) * 17
            let blue = UInt32(value & 0xF) * 17
            self.init(hex: (red << 16) | (green << 8) | blue, opacity: opacity)
        case 6:
            self.init(hex: UInt32(truncatingIfNeeded: value), opacity: opacity)
        case 8:
            let alpha = Double(value & 0xFF) / 255
            self.init(hex: UInt32(truncatingIfNeeded: value >> 8), opacity: opacity * alpha)
        default:
            self.init(hex: 0xA3ABB8, opacity: opacity)
        }
    }
}

// MARK: - Colour tokens

extension Color {
    // Surfaces
    /// `#050608`. Base background.
    static let canvas = Color(hex: 0x050608)
    /// `#2B2D33`. Top of the tile gradient.
    static let tileTop = Color(hex: 0x2B2D33)
    /// `#17181C`. Bottom of the tile gradient.
    static let tileBottom = Color(hex: 0x17181C)
    /// `#FFFFFF` at 9%. 1 pt tile border.
    static let tileStroke = Color.white.opacity(0.09)
    /// `#FFFFFF` at 6%. 1 pt rows inside tiles (§8.1 `separator`).
    static let rowSeparator = Color.white.opacity(0.06)
    /// `#FFFFFF` at 6%. Input and picker fill inside content.
    static let fieldFill = Color.white.opacity(0.06)
    /// `#FFFFFF` at 14%. Input and picker 1 pt stroke.
    static let fieldStroke = Color.white.opacity(0.14)
    /// `#23252B`. External calendar events.
    static let eventFill = Color(hex: 0x23252B)
    /// `#182553`. Goal blocks in the calendar.
    static let blockFill = Color(hex: 0x182553)

    // Text
    /// `#F2F4F7`.
    static let textPrimary = Color(hex: 0xF2F4F7)
    /// `#A3ABB8`.
    static let textSecondary = Color(hex: 0xA3ABB8)
    /// `#7C8494`. Captions (4.7:1 on tiles).
    static let textTertiary = Color(hex: 0x7C8494)

    // Cobalt: at or above the set point (or pro-rata expected)
    /// `#3D6BFF`. App tint, selected tab, D dots. Never used for text under 17 pt.
    static let cobalt = Color(hex: 0x3D6BFF)
    /// `#8FB0FF`. Cobalt-coloured text on dark backgrounds.
    static let cobaltText = Color(hex: 0x8FB0FF)
    /// `#3D6BFF`. Glow base (use at 0.75 opacity, radius 20; see `GlowSpec`).
    static let cobaltGlow = Color(hex: 0x3D6BFF)
    /// `#3D6BFF` at 10%. Monday check-in banner fill (§7.2).
    static let cobaltBannerFill = Color(hex: 0x3D6BFF, opacity: 0.10)
    /// `#8FB0FF` at 28%. Monday check-in banner 1 pt stroke (§7.2).
    static let cobaltBannerStroke = Color(hex: 0x8FB0FF, opacity: 0.28)

    // Ember: behind. Never decoration, never on glass.
    /// `#FF2D17`. Behind-state base; clash border.
    static let ember = Color(hex: 0xFF2D17)
    /// `#FF6A4D`. Ember text.
    static let emberText = Color(hex: 0xFF6A4D)
    /// `#FF8A1A`. 2 pt trailing edge on the ember gauge fill.
    static let emberEdge = Color(hex: 0xFF8A1A)
    /// `#FF3B1F`. Glow base (use at 0.75 opacity, radius 20).
    static let emberGlow = Color(hex: 0xFF3B1F)
    /// `#FF2D17` at 10%. Flag box fill.
    static let flagFill = Color(hex: 0xFF2D17, opacity: 0.10)
    /// `#FF2D17` at 35%. Flag box 1 pt stroke.
    static let flagStroke = Color(hex: 0xFF2D17, opacity: 0.35)
    /// `#FFB4A3`. Flag box text.
    static let flagText = Color(hex: 0xFFB4A3)

    // Marks
    /// `#A3ABB8`. B dot.
    static let markB = Color(hex: 0xA3ABB8)
    /// `#4A505B`. M dot outline.
    static let markMStroke = Color(hex: 0x4A505B)
    /// `#3A3F48`. "Not scheduled" dash.
    static let notScheduled = Color(hex: 0x3A3F48)
    /// `#4A505B`. Map edges (1.2 pt).
    static let mapEdge = Color(hex: 0x4A505B)

    // Gauge
    /// `#FFFFFF` at 5%. Gauge track fill.
    static let gaugeTrackFill = Color.white.opacity(0.05)
    /// `#FFFFFF` at 14%. Gauge track 1 pt stroke.
    static let gaugeTrackStroke = Color.white.opacity(0.14)
    /// `#FFFFFF` at 7%. Gauge track dot grid (1 pt dots, 5 pt pitch).
    static let gaugeTrackDot = Color.white.opacity(0.07)
    /// `#FFFFFF` at 45%. Set-point tick.
    static let gaugeTick = Color.white.opacity(0.45)

    // Banners and toast (solid)
    /// `#FFFFFF` at 6%. PermissionBanner fill.
    static let bannerFill = Color.white.opacity(0.06)
    /// `#2B2D33`. Toast capsule (solid).
    static let toastFill = Color(hex: 0x2B2D33)
}

// MARK: - Colour tokens as ShapeStyle (short form in style positions)

extension ShapeStyle where Self == Color {
    static var canvas: Color { Color.canvas }
    static var tileTop: Color { Color.tileTop }
    static var tileBottom: Color { Color.tileBottom }
    static var tileStroke: Color { Color.tileStroke }
    static var rowSeparator: Color { Color.rowSeparator }
    static var fieldFill: Color { Color.fieldFill }
    static var fieldStroke: Color { Color.fieldStroke }
    static var eventFill: Color { Color.eventFill }
    static var blockFill: Color { Color.blockFill }

    static var textPrimary: Color { Color.textPrimary }
    static var textSecondary: Color { Color.textSecondary }
    static var textTertiary: Color { Color.textTertiary }

    static var cobalt: Color { Color.cobalt }
    static var cobaltText: Color { Color.cobaltText }
    static var cobaltGlow: Color { Color.cobaltGlow }
    static var cobaltBannerFill: Color { Color.cobaltBannerFill }
    static var cobaltBannerStroke: Color { Color.cobaltBannerStroke }

    static var ember: Color { Color.ember }
    static var emberText: Color { Color.emberText }
    static var emberEdge: Color { Color.emberEdge }
    static var emberGlow: Color { Color.emberGlow }
    static var flagFill: Color { Color.flagFill }
    static var flagStroke: Color { Color.flagStroke }
    static var flagText: Color { Color.flagText }

    static var markB: Color { Color.markB }
    static var markMStroke: Color { Color.markMStroke }
    static var notScheduled: Color { Color.notScheduled }
    static var mapEdge: Color { Color.mapEdge }

    static var gaugeTrackFill: Color { Color.gaugeTrackFill }
    static var gaugeTrackStroke: Color { Color.gaugeTrackStroke }
    static var gaugeTrackDot: Color { Color.gaugeTrackDot }
    static var gaugeTick: Color { Color.gaugeTick }

    static var bannerFill: Color { Color.bannerFill }
    static var toastFill: Color { Color.toastFill }
}

// MARK: - Gradient stop sets

extension Gradient {
    /// canvasGlow: `#2A52D6` 0%, `#10204F` 38%, `#07090F` 72%, `#050608` 100%.
    static let canvasGlowStops = Gradient(stops: [
        Gradient.Stop(color: Color(hex: 0x2A52D6), location: 0.00),
        Gradient.Stop(color: Color(hex: 0x10204F), location: 0.38),
        Gradient.Stop(color: Color(hex: 0x07090F), location: 0.72),
        Gradient.Stop(color: Color(hex: 0x050608), location: 1.00)
    ])

    /// horizonGlow: `#1A2A5C` at 60% fading to the same colour at 0% (same hue, so no grey fringe).
    static let horizonGlowStops = Gradient(stops: [
        Gradient.Stop(color: Color(hex: 0x1A2A5C, opacity: 0.60), location: 0.0),
        Gradient.Stop(color: Color(hex: 0x1A2A5C, opacity: 0.0), location: 1.0)
    ])

    /// cobaltFill: `#9DB6FF` 0% → `#3D6BFF` 38% → `#2448E0` 100%.
    static let cobaltFillStops = Gradient(stops: [
        Gradient.Stop(color: Color(hex: 0x9DB6FF), location: 0.00),
        Gradient.Stop(color: Color(hex: 0x3D6BFF), location: 0.38),
        Gradient.Stop(color: Color(hex: 0x2448E0), location: 1.00)
    ])

    /// emberFill: `#FF7A5C` 0% → `#FF2D17` 45% → `#D91A0B` 100%.
    static let emberFillStops = Gradient(stops: [
        Gradient.Stop(color: Color(hex: 0xFF7A5C), location: 0.00),
        Gradient.Stop(color: Color(hex: 0xFF2D17), location: 0.45),
        Gradient.Stop(color: Color(hex: 0xD91A0B), location: 1.00)
    ])
}

// MARK: - Gradient shape styles

extension ShapeStyle where Self == EllipticalGradient {
    /// §8.1 canvasGlow. An ellipse *inscribed in the bounds it fills*, centred in them. `NightCanvas` fills a
    /// rect of 260% × 110% of the screen centred at (50%, −12%), which is the spec's 130% × 55% radii.
    static var canvasGlow: EllipticalGradient {
        EllipticalGradient(gradient: .canvasGlowStops, center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
    }

    /// §8.1 horizonGlow. An ellipse inscribed in the bounds it fills, centred in them. `NightCanvas` fills a
    /// rect of 200% × 60% of the screen centred on the bottom edge (radii 100% × 30%).
    static var horizonGlow: EllipticalGradient {
        EllipticalGradient(gradient: .horizonGlowStops, center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
    }

    /// §8.1 cobaltFill. Gauge fill when on track; highlight at x 12%.
    static var cobaltFill: EllipticalGradient {
        EllipticalGradient(gradient: .cobaltFillStops, center: UnitPoint(x: 0.12, y: 0.5), startRadiusFraction: 0, endRadiusFraction: 1.2)
    }

    /// §8.1 emberFill. Gauge fill when behind; highlight at x 18%.
    static var emberFill: EllipticalGradient {
        EllipticalGradient(gradient: .emberFillStops, center: UnitPoint(x: 0.18, y: 0.5), startRadiusFraction: 0, endRadiusFraction: 1.2)
    }
}

extension ShapeStyle where Self == LinearGradient {
    /// §8.1 tileTop → tileBottom, vertical. GoalTile, Week tiles, MapNode.
    static var tileGradient: LinearGradient {
        LinearGradient(
            colors: [Color.tileTop, Color.tileBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Glow numbers (§8.1 cobaltGlow / emberGlow, §8.5 MapNode)

/// Radius, offset and opacity of the state glows. Apply with `.shadow(color: Color.cobaltGlow.opacity(…), radius: …)`.
/// Cobalt = at or above the set point; ember = behind. Ember is never decoration.
nonisolated enum GlowSpec {
    /// Behind a gauge fill.
    static let gaugeRadius: CGFloat = 20
    static let gaugeOpacity: Double = 0.75
    /// Under a GoalTile.
    static let tileRadius: CGFloat = 30
    static let tileOffsetY: CGFloat = 14
    static let tileOpacity: Double = 0.55
    /// Around a MapNode.
    static let nodeRadius: CGFloat = 10
    static let nodeOpacity: Double = 0.55
}
