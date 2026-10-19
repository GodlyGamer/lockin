import SwiftUI

/// State of a map node (§4.8, §8.5). Pure data.
nonisolated enum MapNodeState: Equatable, Sendable {
    /// Cobalt glow and stroke.
    case onTrack
    /// Ember glow and stroke (also for an unfinished objective past its deadline).
    case behind
    /// Title in textSecondary with a check icon, no glow.
    case done
    /// Plain tile, no glow.
    case neutral
}

/// §8.5 `MapNode(title:state:dashed:)`: radius 14, tile gradient, 1 pt stroke, 10 pt glow in the state colour.
/// `dashed` draws the dashed border of the sustaining system. The node fills the width it is given (the map
/// layout sets it, minimum 72 pt) and grows taller instead of truncating: 2 lines normally, unlimited at
/// accessibility text sizes. `kind` ("Goal", "Principle", "System", "Milestone") only feeds VoiceOver, which
/// reads "{kind}: {title}, {state}".
struct MapNode: View {
    let title: String
    let state: MapNodeState
    let dashed: Bool
    let kind: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(title: String, state: MapNodeState, dashed: Bool = false, kind: String? = nil) {
        self.title = title
        self.state = state
        self.dashed = dashed
        self.kind = kind
    }

    var body: some View {
        HStack(spacing: Spacing.s4) {
            if state == .done {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(state == .done ? Color.textSecondary : Color.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.s8)
        .padding(.vertical, Spacing.s8)
        .frame(maxWidth: .infinity, minHeight: Sizing.minTouchTarget)
        .background {
            RoundedRectangle.continuous(Radius.mapNode)
                .fill(.tileGradient)
                .shadow(color: glowColor, radius: GlowSpec.nodeRadius)
        }
        .overlay { border }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private var border: some View {
        let shape = RoundedRectangle.continuous(Radius.mapNode)
        if dashed {
            shape.strokeBorder(strokeColor, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        } else {
            shape.strokeBorder(strokeColor, lineWidth: 1)
        }
    }

    private var glowColor: Color {
        switch state {
        case .onTrack: Color.cobaltGlow.opacity(GlowSpec.nodeOpacity)
        case .behind: Color.emberGlow.opacity(GlowSpec.nodeOpacity)
        case .done, .neutral: Color.clear
        }
    }

    private var strokeColor: Color {
        switch state {
        case .onTrack: Color.cobalt.opacity(0.6)
        case .behind: Color.ember.opacity(0.6)
        case .done, .neutral: Color.tileStroke
        }
    }

    private var accessibilityDescription: String {
        var text = title
        if let kind, !kind.isEmpty {
            text = "\(kind): \(title)"
        }
        switch state {
        case .onTrack: text += ", on track"
        case .behind: text += ", behind"
        case .done: text += ", done"
        case .neutral: break
        }
        return text
    }
}

#Preview("MapNode") {
    NightCanvas {
        VStack(spacing: Spacing.s12) {
            HStack(spacing: Spacing.s8) {
                MapNode(title: "Meals", state: .onTrack, dashed: false)
                MapNode(title: "Lifting M/W/F", state: .behind, dashed: false)
                MapNode(title: "Walk", state: .neutral, dashed: false)
            }
            HStack(spacing: Spacing.s8) {
                MapNode(title: "82.0 kg", state: .done, dashed: false)
                MapNode(title: "A much longer milestone title that wraps", state: .neutral, dashed: false)
            }
            MapNode(title: "Sleep by 23:30", state: .onTrack, dashed: true, kind: "System")
        }
        .padding(.horizontal, Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
