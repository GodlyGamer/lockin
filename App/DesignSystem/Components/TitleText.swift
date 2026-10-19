import SwiftUI

/// §8.5 `TitleText("Goals")`: appends the title-voice full stop ("Goals.", "10% body fat.", via
/// `LockInFormat.titled`) and applies screenTitle or tileTitle. Never store the full stop in data.
struct TitleText: View {
    enum Style {
        /// `.largeTitle` bold, tracking −0.5.
        case screen
        /// `.title2` semibold, tracking −0.3.
        case tile
    }

    private let text: String
    private let style: Style

    init(_ text: String, style: Style = .screen) {
        self.text = text
        self.style = style
    }

    var body: some View {
        Text(LockInFormat.titled(text))
            .lockInStyle(style == .screen ? .screenTitle : .tileTitle)
            .foregroundStyle(Color.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview("TitleText") {
    NightCanvas {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            TitleText("Goals")
            TitleText("10% body fat", style: .tile)
            TitleText("Already ends in a question?", style: .tile)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
