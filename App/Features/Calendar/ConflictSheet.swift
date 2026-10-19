import SwiftUI
import CoreKit

/// Conflict sheet (DESIGN.md §5.4). Stub: filled in by a later commit.
struct ConflictSheet: View {
    let blockID: UUID

    var body: some View {
        Text("Conflict")
    }
}

#Preview {
    ConflictSheet(blockID: UUID())
        .environment(AppServices.preview())
        .environment(Router())
}
