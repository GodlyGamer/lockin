import SwiftUI
import CoreKit

// Helpers shared by the Habits, Today and Week folders (module M4). Everything here is prefixed `Habits…`
// so it cannot clash with another module's names (one Swift module for the whole app).

/// Plain-language names for marks.
enum HabitsMarkText {
    static func name(_ mark: Mark) -> String {
        switch mark {
        case .D: return "Done"
        case .B: return "Bad-day version"
        case .M: return "Missed"
        }
    }
}

/// A solid tile: vertical tile gradient, 1 pt white 9% stroke, continuous corners (DESIGN.md §8.1, §8.3).
/// Content, never glass.
struct HabitsTileSurface: View {
    var radius: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(colors: [Color.tileTop, Color.tileBottom], startPoint: .top, endPoint: .bottom))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
            }
    }
}

/// The "field" look for inputs placed on content: fill white 6%, stroke white 14%, radius 10 (DESIGN.md §8.1, §8.3).
struct HabitsFieldSurface: View {
    var radius: CGFloat = 10

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            }
    }
}
