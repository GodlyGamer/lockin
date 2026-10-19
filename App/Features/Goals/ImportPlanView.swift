import SwiftUI
import CoreKit

struct ImportPlanView: View {
    let goalID: UUID?

    var body: some View {
        Text("Import")
    }
}

#Preview {
    ImportPlanView(goalID: nil)
        .environment(AppServices.preview())
        .environment(Router())
}
