import SwiftUI
import CoreKit

/// Block sheet (DESIGN.md §5.1). Stub: filled in by a later commit.
struct BlockSheet: View {
    let blockID: UUID

    var body: some View {
        Text("Block")
    }
}

#Preview {
    BlockSheet(blockID: UUID())
        .environment(AppServices.preview())
        .environment(Router())
}
