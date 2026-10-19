import SwiftUI
import CoreKit

/// DESIGN.md §8.4 haptic events. Pure data: `nonisolated` so it can be used anywhere.
nonisolated enum HapticEvent: Equatable, Sendable {
    /// D marked: `.success`.
    case dMarked
    /// B marked: `.impact(weight: .light)`.
    case bMarked
    /// M marked or a mark cleared: `.selection`.
    case mMarkedOrCleared
    /// Check-in finished: `.success`.
    case checkInFinished
    /// Block moved after a clash: `.impact(weight: .medium)`.
    case blockMoved
    /// Outline reorder or indent: `.selection`.
    case outlineReorder
    /// Import failed: `.error`.
    case importFailed

    /// The system feedback for this event.
    var feedback: SensoryFeedback {
        switch self {
        case .dMarked, .checkInFinished: .success
        case .bMarked: .impact(weight: .light)
        case .mMarkedOrCleared, .outlineReorder: .selection
        case .blockMoved: .impact(weight: .medium)
        case .importFailed: .error
        }
    }

    /// D → `.dMarked`, B → `.bMarked`, M or nil (cleared) → `.mMarkedOrCleared`.
    static func forMark(_ mark: Mark?) -> HapticEvent {
        switch mark {
        case .D: .dMarked
        case .B: .bMarked
        case .M, nil: .mMarkedOrCleared
        }
    }
}

extension View {
    /// Plays `event` whenever `trigger` changes (a thin wrapper over `.sensoryFeedback(_:trigger:)`).
    /// Use a counter or a changing value as the trigger; nothing plays on first appearance.
    func haptic<Trigger: Equatable>(_ event: HapticEvent, trigger: Trigger) -> some View {
        sensoryFeedback(event.feedback, trigger: trigger)
    }

    /// Plays the §8.4 mark haptic whenever `mark` changes: D success, B light impact, M or cleared selection.
    /// Nothing plays on first appearance. Attach it to a view that stays on screen after the mark is saved
    /// (a sheet that dismisses itself on tap cannot play it).
    func markHaptic(for mark: Mark?) -> some View {
        sensoryFeedback(trigger: mark) { _, newValue in
            HapticEvent.forMark(newValue).feedback
        }
    }
}
