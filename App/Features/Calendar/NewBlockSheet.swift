import SwiftUI
import CoreKit

/// New block sheet (DESIGN.md §5.1). Stub: filled in by a later commit.
struct NewBlockSheet: View {
    let start: Date

    var body: some View {
        Text("New block")
    }
}

#Preview {
    NewBlockSheet(start: Date())
        .environment(AppServices.preview())
        .environment(Router())
}
