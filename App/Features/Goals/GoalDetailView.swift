import SwiftUI
import CoreKit

struct GoalDetailView: View {
    let goalID: UUID

    var body: some View {
        Text("Goal detail")
    }
}

#Preview {
    NavigationStack { GoalDetailView(goalID: SampleData.goalID) }
        .environment(AppServices.preview())
        .environment(Router())
}
