import SwiftUI

// DESIGN.md §8.2. SF Pro (system). Every style maps to a Dynamic Type text style, so all of it scales;
// there are no fixed font sizes anywhere in the design system.
//
// SwiftUI already ships `.body`, `.callout`, `.subheadline`, `.footnote`, `.caption` and `.caption2` with exactly
// the §8.2 sizes and weights, so those tokens are NOT redeclared on `Font` (a second `Font.body` would be
// ambiguous). The four tokens SwiftUI does not have are declared below; `LockInTextStyle` names all ten.

extension Font {
    /// §8.2 screenTitle: `.largeTitle`, bold (tracking −0.5 is applied by `Text.lockInStyle(_:)` / `TitleText`).
    static let screenTitle = Font.largeTitle.weight(.bold)
    /// §8.2 tileTitle: `.title2`, semibold (tracking −0.3).
    static let tileTitle = Font.title2.weight(.semibold)
    /// §8.2 sectionTitle: `.headline`, semibold.
    static let sectionTitle = Font.headline.weight(.semibold)
    /// §8.2 gaugeNumber: `.subheadline`, medium, monospaced digits.
    static let gaugeNumber = Font.subheadline.weight(.medium).monospacedDigit()
}

/// The ten §8.2 tokens.
enum LockInTextStyle: CaseIterable {
    case screenTitle, tileTitle, sectionTitle, body, callout, subhead, footnote, caption, caption2, gaugeNumber

    /// The Dynamic Type font for this token.
    var font: Font {
        switch self {
        case .screenTitle: Font.screenTitle
        case .tileTitle: Font.tileTitle
        case .sectionTitle: Font.sectionTitle
        case .body: Font.body
        case .callout: Font.callout
        case .subhead: Font.subheadline
        case .footnote: Font.footnote
        case .caption: Font.caption
        case .caption2: Font.caption2
        case .gaugeNumber: Font.gaugeNumber
        }
    }

    /// Tracking in points: −0.5 for screenTitle, −0.3 for tileTitle, 0 for the rest.
    var tracking: CGFloat {
        switch self {
        case .screenTitle: -0.5
        case .tileTitle: -0.3
        default: 0
        }
    }
}

extension Text {
    /// Applies a §8.2 token: font (weight, monospaced digits) and tracking.
    func lockInStyle(_ style: LockInTextStyle) -> Text {
        self.font(style.font).tracking(style.tracking)
    }
}

extension View {
    /// Applies the font of a §8.2 token. SwiftUI can only track `Text`, so call this directly on a `Text`
    /// (before any other view modifier) to also get the tracking.
    func lockInStyle(_ style: LockInTextStyle) -> some View {
        font(style.font)
    }
}
