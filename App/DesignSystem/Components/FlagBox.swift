import SwiftUI

/// §8.5 `FlagBox(text:)`: fill `#FF2D17` 10%, stroke 35%, `flag` icon, `#FFB4A3` text, radius 14. Solid.
/// VoiceOver reads "Flag, {text}" and gives it sort priority so it is read first inside a Week tile
/// (the tile must group its children with `.accessibilityElement(children: .contain)`).
struct FlagBox: View {
    let text: String

    init(text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s8) {
            Image(systemName: "flag")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.emberText)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.flagText)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s12)
        .background {
            RoundedRectangle.continuous(Radius.flagBox)
                .fill(Color.flagFill)
        }
        .overlay {
            RoundedRectangle.continuous(Radius.flagBox)
                .strokeBorder(Color.flagStroke, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Flag, \(text)")
        .accessibilitySortPriority(1)
    }
}

#Preview("FlagBox") {
    NightCanvas {
        VStack(spacing: Spacing.s12) {
            FlagBox(text: "Incline walk: 2 of 3 were B. The slot may be in the wrong place.")
            FlagBox(text: "Lift: 3 of 3 were B.")
        }
        .padding(.horizontal, Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
